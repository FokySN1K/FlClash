#!/usr/bin/env bash
# Build-time core switch for this FlClash fork.
#   patched - use FokySN1K/mihomo flclash-core (url-test-pool + cascade)
#   stock   - use the upstream FlClash core tag
set -euo pipefail
mode="${1:-patched}"
root="$(cd "$(dirname "$0")/.." && pwd)"
core="$root/core/Clash.Meta"
[ -d "$core" ] || { echo "core/Clash.Meta is missing; run git submodule update --init --recursive" >&2; exit 1; }
case "$mode" in
  patched)
    git -C "$core" fetch https://github.com/FokySN1K/mihomo.git flclash-core
    git -C "$core" checkout FETCH_HEAD
    echo "Core selected: flclash-core (url-test-pool + cascade)."
    ;;
  stock)
    git -C "$core" checkout flclash/v0.9.2
    echo "Core selected: upstream FlClash core (flclash/v0.9.2)."
    ;;
  *)
    echo "Usage: $0 [patched|stock]" >&2
    exit 2
    ;;
esac