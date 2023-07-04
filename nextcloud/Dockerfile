ARG NEXTCLOUD_VERSION=27.0.0

FROM nextcloud:${NEXTCLOUD_VERSION}

RUN set -ex \
  && apt-get update && apt-get install --no-install-recommends -y \
    ffmpeg \
  && rm -rf /var/lib/apt/lists/*
