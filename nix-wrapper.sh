#!/usr/bin/env bash

# Set PATH so we can use standard tools on NixOS
export PATH="/run/current-system/sw/bin:/bin:/usr/bin:$PATH"

# Find all /nix/store/... paths in the arguments and environment and realise them.
# The regex matches exactly the Nix store path format.
paths=$( (env; printf "%s\n" "$@") | grep -o -E '/nix/store/[a-z0-9]{32}-[a-zA-Z0-9+\._?=~-]+' | sort -u || true )

for p in $paths; do
    if [ ! -e "$p" ]; then
        nix-store --realise "$p" > /dev/null 2>&1 || true
    fi
done

# Execute the actual command
exec "$@"
