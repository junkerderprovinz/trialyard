#!/usr/bin/env bash
# Overrides the Selkies base image's /defaults/startwm.sh.
#
# HOUSE RULE — the "<APP> IS READY" banner (printed by the separate
# svc-trialyard-ready service once the WebUI is serving) MUST be the LAST
# block in `docker logs`. The desktop session prints continuously; if its
# stdout stays on the service's stdio, its output trails *past* the READY
# banner and the log no longer ends on it. We therefore send the session to
# /dev/null, exactly like the stock base script does (same fix as krusader/
# jdownloader/handbrake).
#
# Do NOT remove this redirect to "keep the session log visible" — un-redirect
# only temporarily while actively debugging the desktop, then put it back.
#
# Identical to the base script otherwise, incl. the Nvidia/zink block: this is
# what makes the desktop's own OpenGL rendering (not just `nvidia-smi`) use
# the RTX 4070 Ti SUPER once the nvidia container runtime has injected
# /dev/dri into the container.

# Enable Nvidia GPU support if detected
if which nvidia-smi > /dev/null 2>&1 && ls -A /dev/dri 2>/dev/null && [ "${DISABLE_ZINK}" == "false" ]; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi

# Start DE — output stays on the service's stdio so it lands in the docker log.
exec dbus-launch --exit-with-session /usr/bin/openbox-session
