#!/usr/bin/env bash
# Build-time core switch for this FlClash fork.
#   patched - FokySN1K/mihomo flclash-core (url-test-pool + cascade)
#   stock   - FokySN1K/mihomo flclash-stock (upstream FlClash core)
set -euo pipefail
mode="${1:-patched}"
root="$(cd "$(dirname "$0")/.." && pwd)"
core="$root/core/Clash.Meta"
[ -d "$core" ] || { echo "core/Clash.Meta is missing; run git submodule update --init --recursive" >&2; exit 1; }
case "$mode" in
  patched) ref=flclash-core ;;
  stock)   ref=flclash-stock ;;
  *) echo "Usage: $0 [patched|stock]" >&2; exit 2 ;;
esac
git -C "$core" fetch https://github.com/FokySN1K/mihomo.git "$ref"
git -C "$core" checkout FETCH_HEAD
echo "Core selected: $ref."