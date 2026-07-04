#!/usr/bin/env bash

# Set PATH so we can use standard tools on NixOS
export PATH="/run/current-system/sw/bin:/bin:/usr/bin:$PATH"

# Find all /nix/store/... paths in the arguments and environment and realise them.
# The regex matches exactly the Nix store path format.
paths=$( (/usr/bin/env; printf "%s\n" "$@") | grep -o -E '/nix/store/[a-z0-9]{32}-[a-zA-Z0-9+\._?=~-]+' | sort -u || true )

TMP_LOG=/tmp/path-$$.log
echo "PATH: ${PATH}" > "${TMP_LOG}"
echo "ALL paths: $paths" >> "${TMP_LOG}"

for p in $paths; do
    if [ ! -e "$p" ]; then
        echo "Realize: $p" >> "${TMP_LOG}"
        nix-store --realise "$p" > /dev/null 2>&1 || true
    fi
done

echo "Command: $@" >> "${TMP_LOG}"

# Execute the actual command
exec "$@"
