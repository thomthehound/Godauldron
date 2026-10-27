#!/usr/bin/env bash
# Install only missing runner dependencies. Do not upgrade preinstalled tools
# or block GPU CI indefinitely on an unresponsive Ubuntu package mirror.
set -euo pipefail

if (( $# == 0 )); then
    echo "Usage: $0 package..." >&2
    exit 2
fi

missing=()
for package in "$@"; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed'; then
        printf 'Already installed: %s\n' "$package"
    else
        missing+=("$package")
    fi
done

if (( ${#missing[@]} == 0 )); then
    echo "All requested Ubuntu dependencies are present; skipping apt."
    exit 0
fi

printf 'Installing missing Ubuntu dependencies: %s\n' "${missing[*]}"
apt_options=(-o Acquire::Retries=2 -o Acquire::http::Timeout=20
             -o Acquire::https::Timeout=20)
sudo env DEBIAN_FRONTEND=noninteractive timeout --signal=TERM --kill-after=5s 120s \
    apt-get "${apt_options[@]}" update
sudo env DEBIAN_FRONTEND=noninteractive timeout --signal=TERM --kill-after=5s 180s \
    apt-get "${apt_options[@]}" install -y --no-install-recommends --no-upgrade "${missing[@]}"

for package in "${missing[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed'; then
        printf 'Dependency installation incomplete: %s\n' "$package" >&2
        exit 1
    fi
done
