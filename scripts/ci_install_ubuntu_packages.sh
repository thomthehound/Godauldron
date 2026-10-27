#!/usr/bin/env bash
# Install only missing runner dependencies. Do not upgrade preinstalled tools
# or block GPU CI indefinitely on an unresponsive Ubuntu package mirror.
set -euo pipefail

if (( $# == 0 )); then
    echo "Usage: $0 package..." >&2
    exit 2
fi

# Runner toolchains may be supplied outside dpkg, so check capabilities
# rather than downloading redundant CMake/GCC/Ninja packages.
is_available() {
    local package="$1"
    case "$package" in
        cmake) command -v cmake >/dev/null 2>&1 ;;
        ninja-build) command -v ninja >/dev/null 2>&1 ;;
        build-essential) command -v c++ >/dev/null 2>&1 &&
                         command -v make >/dev/null 2>&1 ;;
        glslang-tools) command -v glslangValidator >/dev/null 2>&1 ;;
        libvulkan-dev) command -v pkg-config >/dev/null 2>&1 &&
                       pkg-config --exists vulkan ;;
        xvfb) command -v xvfb-run >/dev/null 2>&1 ;;
        mesa-vulkan-drivers)
            for dir in /usr/share/vulkan/icd.d /etc/vulkan/icd.d; do
                if [[ -d "$dir" ]] &&
                   find "$dir" -iname '*lvp*.json' -print -quit | grep -q .; then
                    return 0
                fi
            done
            return 1 ;;
        *)
            dpkg-query -W -f='${Status}' "$package" 2>/dev/null |
                grep -qx 'install ok installed' ;;
    esac
}

missing=()
for package in "$@"; do
    if is_available "$package"; then
        printf 'Already available: %s\n' "$package"
    else
        missing+=("$package")
    fi
done

if (( ${#missing[@]} == 0 )); then
    echo "All requested Ubuntu dependencies are present; skipping apt."
    exit 0
fi

printf 'Installing missing Ubuntu dependencies: %s\n' "${missing[*]}"
# Keep downloaded .deb packages in a workspace cache restored across CI runs.
# apt still resolves package versions from current indexes; stale archives are
# never installed merely because they exist in the cache.
cache_dir="${GITHUB_WORKSPACE:-$PWD}/.ci-apt-archives"
mkdir -p "$cache_dir"
sudo install -d -o _apt -g root -m 755 "$cache_dir/partial"
apt_options=(-o Acquire::Retries=2 -o Acquire::http::Timeout=20
             -o Acquire::https::Timeout=20
             -o "Dir::Cache::archives=$cache_dir"
             -o APT::Keep-Downloaded-Packages=true)
sudo env DEBIAN_FRONTEND=noninteractive timeout --signal=TERM --kill-after=5s 120s \
    apt-get "${apt_options[@]}" update
sudo env DEBIAN_FRONTEND=noninteractive timeout --signal=TERM --kill-after=5s 420s \
    apt-get "${apt_options[@]}" install -y --no-install-recommends --no-upgrade "${missing[@]}"

for package in "${missing[@]}"; do
    if ! is_available "$package"; then
        printf 'Dependency installation incomplete: %s\n' "$package" >&2
        exit 1
    fi
done
