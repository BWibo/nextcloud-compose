# Caddy: trusted proxies and real-client-IP headers

This directory holds the Caddy reverse-proxy configuration for the Nextcloud stack. This document explains the trusted-proxy / real-client-IP header chain — what each header means, how Caddy is configured to consume them, what Nextcloud needs in turn, and how to inspect the chain at runtime with the built-in debug endpoint.

## The proxy chain

For a typical deployment the request path looks like this:

```
real client ──► (optional) edge LB / TLS terminator ──► Caddy ──► Nextcloud-FPM
   1.2.3.4             172.32.0.2                  172.20.0.10        app:9000
                                                   fd20:20::10
```

The internal `net` bridge runs dual-stack, so Caddy's container has both an IPv4 (`${CADDY_IP}`) and an IPv6 ULA address (`${CADDY_IP_V6}`). Either may show up as Nextcloud's `REMOTE_ADDR` depending on which stack Docker uses for a given request.

At each hop, the immediate peer's IP shows up as the TCP-level `REMOTE_ADDR`. To preserve the original client identity, every well-behaved proxy in the chain prepends or appends standard "forwarded" headers. Each downstream consumer (Caddy, then Nextcloud) must be told which upstream peers it trusts to set those headers — otherwise it ignores them as untrusted user input.

## Header reference

| Header | Set by | Caddy reads it as | Nextcloud reads it as |
|---|---|---|---|
| `X-Forwarded-For` | Each proxy appends the IP of the peer it received from | Source for `{client_ip}` when the immediate peer is in `trusted_proxies` | Source for the real client IP when the immediate peer is in `trusted_proxies` |
| `X-Forwarded-Proto` | Set by the TLS terminator to `http` or `https` | Used by `php_fastcgi` to populate `HTTPS=on` for FPM when `https` | Used to build absolute URLs (`overwriteprotocol`) |
| `X-Forwarded-Host` | Set by upstream proxies to the original `Host` value | Available to handlers; not auto-rewritten | Used in conjunction with `overwritehost` if configured |
| `X-Real-IP` | Some proxies (nginx by default) set this to the immediate client IP | Available; not used for `{client_ip}` unless explicitly listed in `client_ip_headers` | Optional alternative to XFF if listed in `forwarded_for_headers` |
| `Forwarded` (RFC 7239) | Modern proxies; combines for/by/host/proto into one header | Caddy parses the `for=` parameter for `client_ip` resolution | Recognised if listed in `forwarded_for_headers` |
| `Via` | Each proxy may add itself for traceability | Logged but not interpreted | Logged but not interpreted |

The TCP peer (the actual socket address Caddy sees) is exposed separately as `{http.request.remote.host}`. That is what `REMOTE_ADDR` would be for a non-proxy-aware app.

## Caddy configuration in this repo

The global `servers` block (in [`Caddyfile`](Caddyfile)) declares which peer IPs Caddy trusts to set the forwarded headers:

```caddyfile
servers {
    trusted_proxies static 172.32.0.2/32
    trusted_proxies_strict
}
```

- `trusted_proxies static <cidr>...` — when the immediate peer matches, Caddy parses `X-Forwarded-For` / `Forwarded` to populate `{client_ip}`. Otherwise `{client_ip}` falls back to the TCP peer.
- `trusted_proxies_strict` — Caddy will *not* forward the request's `X-Forwarded-*` headers upstream when the peer isn't trusted, preventing client-spoofed forwarded headers from reaching Nextcloud.

The `php_fastcgi app:9000` directive then forwards the request (and a normalised `HTTPS=on` / `X-Forwarded-Proto`) to Nextcloud-FPM at the immediate-peer level. Inside Nextcloud, `REMOTE_ADDR` is therefore Caddy's container IP — either `${CADDY_IP}` (default `172.20.0.10`) or `${CADDY_IP_V6}` (default `fd20:20::10`) from `.env`.

### Placeholders worth knowing

| Placeholder | What it returns |
|---|---|
| `{http.request.remote.host}` | TCP peer IP (the literal connection source) |
| `{client_ip}` | Real client IP after `trusted_proxies` parsing — falls back to remote.host when the peer is not trusted |
| `{http.request.scheme}` | Connection scheme between client and Caddy (peer-level, *not* the original client's scheme when behind a TLS terminator) |
| `{http.request.host}` | Effective `Host` header value |
| `{http.request.header.X-Forwarded-For}` | Raw header value, untouched |

Note: `{http.request.client_ip}` is **not** a valid Caddy placeholder — use `{client_ip}` (or its longer form `{http.vars.client_ip}`).

## Internal docker network (dual-stack)

The compose stack runs the internal `net` bridge as **dual-stack** — both IPv4 and an IPv6 ULA prefix. This is configured by four `.env` variables and one `enable_ipv6: true` flag on the network in `docker-compose.yml`:

| `.env` variable | Default | Purpose |
|---|---|---|
| `DOCKER_NET_SUBNET` | `172.20.0.0/24` | IPv4 subnet for the `net` bridge. |
| `DOCKER_NET_SUBNET_V6` | `fd20:20::/64` | IPv6 ULA subnet for the `net` bridge. Must be inside `fd00::/8` (RFC 4193). |
| `CADDY_IP` | `172.20.0.10` | Fixed IPv4 address pinned to the Caddy container. Must lie inside `DOCKER_NET_SUBNET`. |
| `CADDY_IP_V6` | `fd20:20::10` | Fixed IPv6 address pinned to the Caddy container. Must lie inside `DOCKER_NET_SUBNET_V6`. |

All four are referenced with `${VAR:?…}` in `docker-compose.yml`, so the stack refuses to start if any is unset. Other services (`db`, `redis`, `app`, `cron`) get random v4 and v6 addresses from the same subnets via Docker's IPAM — only Caddy is pinned, because Nextcloud's `trusted_proxies` needs to reference a stable address.

### Why dual-stack matters for `trusted_proxies`

When the `app` container resolves `caddy` (or vice versa), Docker's embedded DNS may return either an A or AAAA record depending on the container's resolver and the request path. If `trusted_proxies` only contains the IPv4 address but Caddy actually connects to FPM over IPv6 (or vice versa), Nextcloud sees an untrusted peer, drops the forwarded headers, and reports every request as coming from Caddy itself. **Both** `${CADDY_IP}` and `${CADDY_IP_V6}` must be in `trusted_proxies`.

### Choosing your own subnets

If you change the defaults — typically because `172.20.0.0/24` clashes with an existing LAN, VPN, or Docker network on the host — keep these constraints in mind:

- **IPv4**: any free RFC 1918 range (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`). Avoid CGNAT space (`100.64.0.0/10`) — Tailscale uses it.
- **IPv6**: any ULA prefix (`fd00::/8`). Best practice is to randomise the 40-bit Global ID per host (e.g. `fd<random40bit>::/64`) so two hosts you later peer over WireGuard / Tailscale don't collide. Avoid `fc00::/8` (reserved, not registered) and link-local `fe80::/10`.
- **No overlap** with anything the host is already attached to. An overlap silently breaks routing — the host prefers the more specific route and connections to LAN hosts from inside containers (or LAN → container) black-hole.
- After changing subnets, the bridge must be recreated: `docker compose down && ./create.sh`. Docker won't apply IPAM changes to a live network.

### Verifying the dual-stack setup

```bash
docker network inspect nextcloud_net | jq '.[0].IPAM.Config, .[0].Containers'
```

Expected: two `IPAM.Config` entries (the v4 and v6 subnets), and the `caddy` container shows both `IPv4Address: 172.20.0.10/24` and `IPv6Address: fd20:20::10/64`. From inside the `app` container:

```bash
docker exec -it nextcloud-app-1 sh -c 'getent ahosts caddy'
# both an A and AAAA line should appear
```

## Nextcloud configuration (the downstream half)

Caddy correctly parsing the headers is only half the job. Nextcloud's PHP layer must also be told to trust Caddy's IP, otherwise it treats `REMOTE_ADDR` (i.e. `172.20.0.10`) as the real client and ignores the forwarded headers. The relevant `config.php` keys:

| Key | Purpose | Default |
|---|---|---|
| `trusted_proxies` | Array of proxy IPs whose `X-Forwarded-For` / configured forwarded headers Nextcloud will believe | empty |
| `forwarded_for_headers` | Header names to read for the real IP | `["HTTP_X_FORWARDED_FOR"]` |
| `overwriteprotocol` | Force scheme used when generating URLs | empty (auto) |
| `overwritehost` | Force host used when generating URLs | empty |
| `overwrite.cli.url` | Base URL used by background jobs | from install |

The Nextcloud Docker image's `NC_` env-var handler does **not** support array values — there is no JSON / CSV / space-separated form for `trusted_proxies`. Set it imperatively instead:

```bash
docker exec -i --user 33 nextcloud-app-1 ./occ config:system:set trusted_proxies 0 --value=172.20.0.10
docker exec -i --user 33 nextcloud-app-1 ./occ config:system:set trusted_proxies 1 --value=fd20:20::10
docker exec -i --user 33 nextcloud-app-1 ./occ config:system:set overwriteprotocol --value=https
```

(Replace `172.20.0.10` / `fd20:20::10` with whatever `CADDY_IP` and `CADDY_IP_V6` are set to in `.env`. Both entries are needed because the `net` bridge is dual-stack — the request from Caddy to `app` may arrive over either family.)

## Debugging the chain

The Caddyfile defines two snippets — `(debug_headers_off)` (the no-op default) and `(debug_headers_on)` — selected at parse time by the `CADDY_DEBUG_SNIPPET` env var. Toggle in `.env`:

```env
CADDY_DEBUG_SNIPPET=debug_headers_on
```

Then `./caddy_update.sh` to recreate the Caddy container. While `_on`, two things activate:

### 1. JSON access log to stdout

Caddy emits one structured JSON record per request to stdout, captured by Docker's logging driver. Tail it with:

```bash
docker compose logs -f caddy
```

Each record contains the full `request.headers` map (including all the forwarded headers above), `request.remote_ip` (TCP peer), and `request.client_ip` (parsed via `trusted_proxies`). Useful for diffing what *should* arrive vs. what actually does.

### 2. `/caddy-debug-headers` endpoint

A plain-text endpoint that echoes back exactly what Caddy sees for a single request. Curl it through the proxy chain you want to verify:

```bash
curl -k https://your.domain/caddy-debug-headers
```

Example output from a deployment behind an upstream LB at `172.32.0.2`:

```text
remote_ip (peer):  172.32.0.2
client_ip (real):  172.32.0.40
host:              cloud.example.com
proto (peer):      http
X-Forwarded-For:   172.32.0.40
X-Forwarded-Proto: https
X-Forwarded-Host:  cloud.example.com
X-Real-IP:
Forwarded:
Via:               2.0 Caddy
```

How to read it:

- `remote_ip (peer)` is the upstream LB (`172.32.0.2`) — that matches the `trusted_proxies` entry, so Caddy honours the forwarded headers.
- `client_ip (real)` is the original client (`172.32.0.40`) — extracted from `X-Forwarded-For` because the peer was trusted. If the peer were *not* trusted, this would equal `remote_ip`.
- `proto (peer)` is `http` because TLS is terminated at the upstream LB and the LB ↔ Caddy hop is plain HTTP. The original client's scheme is in `X-Forwarded-Proto: https`.
- `X-Real-IP` and `Forwarded` are empty — the upstream LB doesn't emit them. Not a problem; XFF is enough.

When you're done debugging, set `CADDY_DEBUG_SNIPPET=debug_headers_off` in `.env` and run `./caddy_update.sh` to silence the JSON access log and remove the endpoint.

## Common failure modes

- **Nextcloud admin UI / log shows everything coming from `172.20.0.10` or `fd20:20::10`** — Caddy is parsing correctly but Nextcloud's `trusted_proxies` does not include Caddy's IP for the family in question. Set both v4 and v6 entries via `occ` (see above).
- **`client_ip (real)` equals `remote_ip (peer)`** — the immediate peer isn't in Caddy's `trusted_proxies` list. Either add its CIDR or check that the request actually transits the proxy you think it does.
- **`proto (peer)` is `http` but app behaves as if HTTP** — Nextcloud isn't honouring `X-Forwarded-Proto`. Set `overwriteprotocol=https` and confirm `forwarded_for_headers` includes the right header names if you've customised the upstream.
- **HSTS warnings during Let's Encrypt staging** — the `Strict-Transport-Security` header in the `Caddyfile` is enabled by default; comment it out when using `acme_ca` for staging or `tls internal`, otherwise browsers refuse to add an exception.
