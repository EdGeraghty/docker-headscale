# ---
# Tool version args
ARG HEADSCALE_VERSION="0.23.0-beta1"
ARG HEADSCALE_SHA256="7042957a62ef3ac68435e4cfcbb401f301ef4a43effd26a458bdd695c5c92c25"
ARG HEADSCALE_ADMIN_VERSION="0.1.12b"
ARG LITESTREAM_VERSION="0.3.13"
ARG LITESTREAM_SHA256="eb75a3de5cab03875cdae9f5f539e6aedadd66607003d9b1e7a9077948818ba0"
# Container version args
ARG CADDY_BUILDER_VERSION="2.8.4-builder"
ARG MAIN_IMAGE_ALPINE_VERSION="3.20.2"

###########
# ---
# Build caddy with Cloudflare DNS support
FROM caddy:${CADDY_BUILDER_VERSION} AS caddy-builder

    RUN xcaddy build \
        --with github.com/caddy-dns/cloudflare

# ---
# Docker hates variables in COPY, apparently. Hello, workaround.
FROM goodieshq/headscale-admin:${HEADSCALE_ADMIN_VERSION} AS admin-gui

# --- 
# Build our main image
FROM alpine:${MAIN_IMAGE_ALPINE_VERSION}

    # ---
    # import our "global" `ARG` values into this stage
    ARG HEADSCALE_VERSION
    ARG HEADSCALE_SHA256
    ARG LITESTREAM_VERSION
    ARG LITESTREAM_SHA256

    # ---
    # upgrade system, install dependencies
    RUN --mount=type=cache,sharing=private,target=/var/cache/apk \
        set -eux; \
        apk upgrade; \
        # BusyBox's wget isn't reliable enough
        apk add wget --virtual BuildTimeDeps; \
        # I'm gonna need a better shell, too
        apk add bash; \
        # We need GNU sed
        apk add sed;

    # ---
    # Copy caddy from the first stage
    COPY --from=caddy-builder /usr/bin/caddy /usr/local/bin/caddy
    # Caddy smoke test
    RUN [ "$(command -v caddy)" = '/usr/local/bin/caddy' ]; \
        caddy version

    # ---
    # Headscale
    RUN { \
            wget --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 0 -q -O headscale https://github.com/juanfont/headscale/releases/download/v${HEADSCALE_VERSION}/headscale_${HEADSCALE_VERSION}_linux_amd64; \
            echo "${HEADSCALE_SHA256} *headscale" | sha256sum -c - >/dev/null 2>&1; \
            chmod +x headscale; \
            mv headscale /usr/local/bin/; \
        }; \
        # smoke test
        [ "$(command -v headscale)" = '/usr/local/bin/headscale' ]; \
        headscale version;
    
    # Litestream
    RUN { \
            wget --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 0 -q -O litestream.tar.gz https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM_VERSION}/litestream-v${LITESTREAM_VERSION}-linux-amd64.tar.gz; \
            echo "${LITESTREAM_SHA256} *litestream.tar.gz" | sha256sum -c - >/dev/null 2>&1; \
            tar -xf litestream.tar.gz; \
            mv litestream /usr/local/bin/; \
            rm -f litestream.tar.gz; \
        }; \
        # smoke test
        [ "$(command -v litestream)" = '/usr/local/bin/litestream' ]; \
        litestream version;
    
    # Headscale web GUI
    COPY --from=admin-gui /app/admin/ /data/admin-gui/admin/
    
    # Remove build-time dependencies
    RUN --mount=type=cache,target=/var/cache/apk \
        apk del BuildTimeDeps;

    # ---
    # copy configuration and templates
    COPY ./templates/headscale.template.yaml /etc/headscale/config.yaml
    COPY ./templates/litestream.template.yml /etc/litestream.yml
    COPY ./templates/caddy.template.yaml /etc/caddy/Caddyfile
    COPY ./scripts/container-entrypoint.sh /container-entrypoint.sh

    ENTRYPOINT ["/container-entrypoint.sh"]
