# syntax=docker/dockerfile:1.26
#
# TrialYard — internal GPU-accelerated test/dev sandbox (Selkies)
# -----------------------------------------------------------------------------
# NOT a public junkerderprovinz app. No GitHub repo, no CA listing, no README.
# Permanent, general-purpose desktop on Bottich for real-hardware testing
# (Selkies PR/e2e work, cross-browser checks, ad-hoc GPU/dev tasks) that a
# generic cloud sandbox cannot do (no browser, no GPU). Built directly on the
# host from this Dockerfile; not pushed to any registry.
#
# House pattern copied from junkerderprovinz/krusader and junkerderprovinz/
# jdownloader: LinuxServer Selkies base image, s6-overlay init, HTTPS WebUI on
# 3001, no-login-by-default, GPU wiring copied verbatim from the confirmed
# working junkerderprovinz/handbrake container (`docker inspect HandBrake`):
# Runtime=nvidia, NVIDIA_VISIBLE_DEVICES=all,
# NVIDIA_DRIVER_CAPABILITIES=compute,video,utility — supplied at `docker run`
# / via the Unraid template, not baked into this image (keeps the image
# vendor-neutral, same as HandBrake's own image).
#
# Flavor PINNED on purpose (never :latest, never the floating :dev tag — that
# was a one-off fix for a krusader-specific clipboard bug, not the standing
# default): ubunturesolute matches what krusader/jdownloader/handbrake
# currently ship.
ARG BASE_TAG=ubunturesolute
FROM ghcr.io/linuxserver/baseimage-selkies:${BASE_TAG}

LABEL maintainer="junkerderprovinz"
LABEL org.opencontainers.image.title="trialyard"
LABEL org.opencontainers.image.description="TrialYard — internal permanent GPU-accelerated test/dev sandbox on Selkies (Firefox + Chrome, git/build-essential, Python/Node/Go). Not a public image."
LABEL org.opencontainers.image.vendor="junkerderprovinz"

# TITLE feeds the PWA manifest; SELKIES_UI_TITLE is the visible tab/sidebar
# title of the Selkies web client — both must be set on this base.
#
# SELKIES_ENABLE_BASIC_AUTH=false: Selkies' server enables basic auth by
# DEFAULT with well-known default credentials (ubuntu / mypasswd). Same house
# fix as krusader/jdownloader/handbrake: no login unless CUSTOM_USER/PASSWORD
# are explicitly set (init-nologin strips empty values before nginx reads
# them).
ENV TITLE="TrialYard" \
    SELKIES_UI_TITLE="TrialYard" \
    SELKIES_ENABLE_BASIC_AUTH="false"

# ---------------------------------------------------------------------------
# Base toolchain: git, curl, build-essential/gcc, Python 3 + pip, fonts, locale
# ---------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        # Version control + fetch tools
        git curl wget ca-certificates gnupg jq unzip xz-utils \
        # C/C++ toolchain
        build-essential pkg-config \
        # Python 3
        python3 python3-pip python3-venv python3-dev \
        # Fonts — without these, browsers/xterm render text as empty boxes
        fontconfig \
        fonts-noto fonts-noto-color-emoji \
        fonts-dejavu fonts-dejavu-core fonts-dejavu-extra \
        fonts-liberation fonts-liberation2 \
        fonts-hack \
        # Desktop background setter (autostart uses this for the baked-in
        # "right-click for apps" wallpaper hint — see rootfs/defaults/autostart)
        feh \
        # Locale
        locales; \
    fc-cache -f -v >/dev/null 2>&1 || true; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ---------------------------------------------------------------------------
# Firefox — official Mozilla apt repo (Ubuntu's own "firefox" package is a
# Snap stub; Snaps don't run inside containers). Same source as jdownloader's
# opt-in browser, but ALWAYS installed and active here — cross-browser testing
# is the whole point of this sandbox.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Google Chrome — official Google apt repo (real standalone binary, not a
# Snap). Chromium-based browser for cross-browser testing alongside Firefox.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Node.js — NodeSource, pinned to the major version jdp's own repos target
# (bombvault, cannonadecommander, featherdrop, navidrome, tus-js-client CI all
# run node-version 24).
# ---------------------------------------------------------------------------
RUN set -eux; \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash -; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
# npm global installs + cache land in the persistent /config volume instead of
# the container's writable layer, so they survive a container recreate.
ENV NPM_CONFIG_PREFIX=/config/npm-global
ENV PATH="${NPM_CONFIG_PREFIX}/bin:${PATH}"

# ---------------------------------------------------------------------------
# Go — pinned to the minor version jdp's own repos target (bombvault, shiplog,
# cannonadecommander CI all run go-version 1.26). Downloaded from the official
# go.dev tarball and verified against go.dev's own published checksum (fetched
# live from the dl API) rather than a hardcoded hash, since go.dev publishes
# new patch releases within this minor series over time.
# ---------------------------------------------------------------------------
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
# GOPATH/module cache in the persistent /config volume (same reasoning as npm above).
ENV GOPATH=/config/go
ENV PATH="${GOPATH}/bin:${PATH}"

# ---------------------------------------------------------------------------
# Playwright OS-level browser dependencies (shared libs Chromium/Firefox/
# WebKit need under Playwright automation) WITHOUT downloading Playwright's
# own bundled browser binaries — Firefox + Chrome are already installed above
# as real system browsers, so a project's own `npm i -D playwright` can point
# at them (or download its own if truly needed) without doubling the image
# size. `install-deps` only apt-installs the shared-library list; it needs
# Node/npx, hence placed after the Node.js step.
# ---------------------------------------------------------------------------
RUN set -eux; \
    npx --yes playwright@latest install-deps; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# openbox-xdg-autostart needs PyXDG, else it logs "requires PyXDG to be
# installed" on every boot (same fix as jdownloader's Dockerfile). Kept as its
# own tiny layer at the end so it does not bust the cache of the much more
# expensive layers above (Firefox/Chrome/Node/Go/Playwright downloads).
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3-xdg; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ---------------------------------------------------------------------------
# Skeleton-configs + s6-overlay init scripts
# ---------------------------------------------------------------------------
COPY rootfs/ /

# Suppress LSIO base-image branding so the log stays clean (same house fix as
# krusader/jdownloader/handbrake): empty the "linuxserver.io" ASCII logo and
# strip the donate lines from init-adduser/run.
RUN set -eux; \
    : > /etc/s6-overlay/s6-rc.d/init-adduser/branding 2>/dev/null || true; \
    run=/etc/s6-overlay/s6-rc.d/init-adduser/run; \
    if [ -f "$run" ]; then \
        sed -i -e '/To support LSIO projects visit:/d' -e '\#linuxserver\.io/donate#d' "$run"; \
    fi

RUN chmod +x \
    /usr/local/bin/print-banner.sh \
    /usr/local/bin/chrome-launch \
    /etc/s6-overlay/s6-rc.d/init-nologin/run \
    /etc/s6-overlay/s6-rc.d/init-trialyard/run \
    /etc/s6-overlay/s6-rc.d/svc-trialyard-ready/run \
    /defaults/autostart \
    /defaults/startwm.sh

# ---------------------------------------------------------------------------
# Browser-tab favicon / branding — same single-path mechanism as krusader/
# jdownloader/handbrake: init-nginx copies /usr/share/selkies/www/icon.png to
# favicon.ico + icon.png on every start and writes the PWA manifest around
# ${TITLE}. Fail loudly if the path moves (base layout changed).
# ---------------------------------------------------------------------------
COPY assets/icon.png /usr/local/share/trialyard-icon.png
RUN set -eux; \
    dst=/usr/share/selkies/www/icon.png; \
    [ -f "$dst" ] || { echo "ERROR: $dst missing — selkies base layout changed, update the branding override"; exit 1; }; \
    cp /usr/local/share/trialyard-icon.png "$dst"; \
    echo "trialyard: branded selkies icon at $dst"

# Desktop wallpaper: #161616 fill plus a small "right-click the desktop for
# Terminal / Firefox / Google Chrome" hint (bottom-center), set by
# rootfs/defaults/autostart via feh. Without this, a fresh session is a
# totally blank canvas with no taskbar and no auto-started app, which reads
# as broken rather than as "right-click for the menu".
COPY assets/wallpaper.png /usr/local/share/trialyard-wallpaper.png

# ---------------------------------------------------------------------------
# Standard ENV (overridable via the Unraid template)
# ---------------------------------------------------------------------------
ENV KEYBOARD_LAYOUT=us \
    GTK_THEME=Adwaita:dark \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Ports served by the base image (3000/HTTP, 3001/HTTPS).

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD ["/bin/sh", "-c", "c=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 5 https://127.0.0.1:${CUSTOM_HTTPS_PORT:-3001}/); [ \"$c\" != \"000\" ] || exit 1"]
