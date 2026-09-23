# syntax=docker/dockerfile:1.27
#
# TrialYard: a permanent GPU-accelerated desktop on Selkies for the testing a
# cloud sandbox cannot do, such as cross-browser checks and GPU work.
#
# It follows the krusader and jdownloader images: LinuxServer's Selkies base,
# s6-overlay init, the HTTPS WebUI on 3001 and no login by default. The GPU
# wiring (Runtime=nvidia, NVIDIA_VISIBLE_DEVICES=all,
# NVIDIA_DRIVER_CAPABILITIES=compute,video,utility) comes from the working
# handbrake container and is supplied at `docker run` or by the Unraid
# template, which keeps the image vendor-neutral.
#
# The flavor is pinned to ubunturesolute, the one krusader, jdownloader and
# handbrake ship, and to a digest, because a builder that already holds an older
# ubunturesolute would otherwise keep using it.
ARG BASE_TAG=ubunturesolute@sha256:6cfa54196b6e0dade64f5e51517fd12c4275ceda7519c0e18ad168cb4508c050
FROM ghcr.io/linuxserver/baseimage-selkies:${BASE_TAG}

LABEL maintainer="junkerderprovinz"
LABEL org.opencontainers.image.title="trialyard"
LABEL org.opencontainers.image.description="TrialYard: internal permanent GPU-accelerated test/dev sandbox on Selkies (Firefox + Chrome, git/build-essential, Python/Node/Go). Not a public image."
LABEL org.opencontainers.image.vendor="junkerderprovinz"

# TITLE feeds the PWA manifest and SELKIES_UI_TITLE the web client's tab and
# sidebar; this base needs both.
#
# The Selkies server enables basic auth by default and will not start without a
# password. With SELKIES_ENABLE_BASIC_AUTH=false there is no login unless
# CUSTOM_USER and PASSWORD are set, which nginx then enforces.
ENV TITLE="TrialYard" \
    SELKIES_UI_TITLE="TrialYard" \
    SELKIES_ENABLE_BASIC_AUTH="false"

RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git curl wget ca-certificates gnupg jq unzip xz-utils \
        build-essential pkg-config \
        python3 python3-pip python3-venv python3-dev \
        # Without fonts, browsers and xterm render text as empty boxes.
        fontconfig \
        fonts-noto fonts-noto-color-emoji \
        fonts-dejavu fonts-dejavu-core fonts-dejavu-extra \
        fonts-liberation fonts-liberation2 \
        fonts-hack \
        # Sets the wallpaper with the right-click hint, see rootfs/defaults/autostart.
        feh \
        locales; \
    fc-cache -f -v >/dev/null 2>&1 || true; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Firefox comes from Mozilla's apt repo: Ubuntu's own package is a Snap stub,
# and Snaps do not run inside containers.
RUN set -eux; \
    install -d -m 0755 /etc/apt/keyrings; \
    wget -qO /etc/apt/keyrings/packages.mozilla.org.asc \
        https://packages.mozilla.org/apt/repo-signing-key.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
        > /etc/apt/sources.list.d/mozilla.list; \
    printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
        > /etc/apt/preferences.d/mozilla; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        firefox xdg-utils; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
ENV MOZ_CRASHREPORTER_DISABLE=1

RUN set -eux; \
    install -d -m 0755 /etc/apt/keyrings; \
    wget -qO- https://dl.google.com/linux/linux_signing_key.pub \
        | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg; \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        google-chrome-stable; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Node.js and Go are pinned to the versions the projects tested here run in CI.
RUN set -eux; \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash -; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
# Global npm installs go to the persistent /config volume so they survive a
# container recreate.
ENV NPM_CONFIG_PREFIX=/config/npm-global
ENV PATH="${NPM_CONFIG_PREFIX}/bin:${PATH}"

# The tarball is checked against the checksum go.dev's dl API publishes, so a
# GO_VERSION bump needs no hash edit.
ARG GO_VERSION=1.26.0
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in \
        amd64) goarch=amd64 ;; \
        arm64) goarch=arm64 ;; \
        *) echo "unsupported arch for Go: ${arch}"; exit 1 ;; \
    esac; \
    tarball="go${GO_VERSION}.linux-${goarch}.tar.gz"; \
    curl -fsSL -o "/tmp/${tarball}" "https://go.dev/dl/${tarball}"; \
    expected_sha="$(curl -fsSL 'https://go.dev/dl/?mode=json&include=all' \
        | python3 -c "import json,sys; data=json.load(sys.stdin); \
            files=[f for r in data for f in r.get('files',[]) if f.get('filename')=='${tarball}']; \
            print(files[0]['sha256'] if files else '')")"; \
    if [ -z "${expected_sha}" ]; then echo "could not resolve go.dev checksum for ${tarball}"; exit 1; fi; \
    echo "${expected_sha}  /tmp/${tarball}" | sha256sum -c -; \
    tar -C /usr/local -xzf "/tmp/${tarball}"; \
    rm -f "/tmp/${tarball}"
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH=/config/go
ENV PATH="${GOPATH}/bin:${PATH}"

# Only the shared libraries Playwright's browsers need, not the browsers
# themselves: Firefox and Chrome are installed above, and a project can still
# download its own. install-deps runs through npx, hence after Node.
RUN set -eux; \
    npx --yes playwright@latest install-deps; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# openbox-xdg-autostart logs "requires PyXDG to be installed" on every boot
# without it. A layer of its own at the end keeps the expensive layers above
# cached.
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3-xdg; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY rootfs/ /

# Empties the base image's "linuxserver.io" logo and drops its donate lines so
# the log shows only this container's banner.
RUN set -eux; \
    : > /etc/s6-overlay/s6-rc.d/init-adduser/branding 2>/dev/null || true; \
    run=/etc/s6-overlay/s6-rc.d/init-adduser/run; \
    if [ -f "$run" ]; then \
        sed -i -e '/To support LSIO projects visit:/d' -e '\#linuxserver\.io/donate#d' "$run"; \
    fi

RUN chmod +x \
    /usr/local/bin/print-banner.sh \
    /usr/local/bin/chrome-launch \
    /etc/s6-overlay/s6-rc.d/init-trialyard/run \
    /etc/s6-overlay/s6-rc.d/svc-trialyard-ready/run \
    /defaults/autostart \
    /defaults/startwm.sh

# init-nginx copies /usr/share/selkies/www/icon.png to favicon.ico and icon.png
# on every start and builds the PWA manifest around ${TITLE}. The build fails if
# the base moves that path.
COPY assets/icon.png /usr/local/share/trialyard-icon.png
RUN set -eux; \
    dst=/usr/share/selkies/www/icon.png; \
    [ -f "$dst" ] || { echo "ERROR: $dst missing, the selkies base layout changed; update the branding override"; exit 1; }; \
    cp /usr/local/share/trialyard-icon.png "$dst"; \
    echo "trialyard: branded selkies icon at $dst"

# The wallpaper carries a small "right-click the desktop" hint. Without it a
# fresh session, with no taskbar and no app started, looks broken.
COPY assets/wallpaper.png /usr/local/share/trialyard-wallpaper.png

ENV KEYBOARD_LAYOUT=us \
    GTK_THEME=Adwaita:dark \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# The base image serves 3000 (HTTP) and 3001 (HTTPS). Any HTTP status counts
# as healthy, a 401 from basic auth included.
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD ["/bin/sh", "-c", "c=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 5 https://127.0.0.1:${CUSTOM_HTTPS_PORT:-3001}/); [ \"$c\" != \"000\" ] || exit 1"]
