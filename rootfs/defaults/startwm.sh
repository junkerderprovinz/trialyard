#!/usr/bin/env bash
# Overrides the Selkies base image's /defaults/startwm.sh, which sends the
# session to /dev/null. The session's output stays on the service's stdio here,
# so it lands in the docker log.
exec dbus-launch --exit-with-session /usr/bin/openbox-session
