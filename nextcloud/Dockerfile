ARG NEXTCLOUD_VERSION=27.0.0

FROM nextcloud:${NEXTCLOUD_VERSION}

RUN set -ex \
  && apt-get update && apt-get install --no-install-recommends -y \
    ffmpeg \
  && rm -rf /var/lib/apt/lists/*

# Disable OPcache JIT — unstable on ARM64 (Pi 5), segfaults php-fpm during app
# install/upgrade (upstream PHP bug php/php-src#16829, see nextcloud/docker#2576).
COPY zz-disable-opcache-jit.ini /usr/local/etc/php/conf.d/zz-disable-opcache-jit.ini
