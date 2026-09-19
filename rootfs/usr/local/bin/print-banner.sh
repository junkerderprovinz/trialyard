#!/usr/bin/env bash
# Usage: print-banner.sh <container-name> <subtitle>
# Prints the init-log banner shared by the junkerderprovinz containers.
# TrialYard ships no banner art, so it always takes the plain-text fallback.

CONTAINER="${1:-Container}"
SUBTITLE="${2:-}"
BANNER_FILE="/usr/local/share/banner.txt"

echo ""

if [ -f "${BANNER_FILE}" ]; then
    cat "${BANNER_FILE}"
    echo ""
    echo ""
else
    echo ""
    echo "  Junker der Provinz"
    echo ""
fi

if [ -n "${SUBTITLE}" ]; then
    printf '  %s \xc2\xb7 %s\n' "${CONTAINER}" "${SUBTITLE}"
else
    printf '  %s\n' "${CONTAINER}"
fi
echo ""
