#!/usr/bin/env pwsh
# Build-time core switch for this FlClash fork.
#   patched - use FokySN1K/mihomo flclash-core (url-test-pool + cascade)
#   stock   - use the upstream FlClash core tag
param(
    [ValidateSet('patched', 'stock')]
    [string]$Mode = 'patched'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$core = Join-Path $root 'core/Clash.Meta'
if (-not (Test-Path $core)) { throw 'core/Clash.Meta is missing; run git submodule update --init --recursive' }

if ($Mode -eq 'patched') {
    & git -C $core fetch https://github.com/FokySN1K/mihomo.git flclash-core
    if ($LASTEXITCODE -ne 0) { throw 'Failed to fetch flclash-core from FokySN1K/mihomo.' }
    & git -C $core checkout FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Failed to check out flclash-core.' }
    Write-Host 'Core selected: flclash-core (url-test-pool + cascade).'
} else {
    & git -C $core checkout flclash/v0.9.2
    if ($LASTEXITCODE -ne 0) { throw 'Failed to check out the upstream FlClash core tag.' }
    Write-Host 'Core selected: upstream FlClash core (flclash/v0.9.2).'
}