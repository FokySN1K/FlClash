#!/usr/bin/env pwsh
# Build-time core switch for this FlClash fork.
#   patched - FokySN1K/mihomo flclash-core (url-test-pool + cascade)
#   stock   - FokySN1K/mihomo flclash-stock (upstream FlClash core)
param(
    [ValidateSet('patched', 'stock')]
    [string]$Mode = 'patched'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$core = Join-Path $root 'core/Clash.Meta'
if (-not (Test-Path $core)) { throw 'core/Clash.Meta is missing; run git submodule update --init --recursive' }

$ref = if ($Mode -eq 'patched') { 'flclash-core' } else { 'flclash-stock' }
& git -C $core fetch https://github.com/FokySN1K/mihomo.git $ref
if ($LASTEXITCODE -ne 0) { throw "Failed to fetch $ref from FokySN1K/mihomo." }
& git -C $core checkout FETCH_HEAD
if ($LASTEXITCODE -ne 0) { throw "Failed to check out $ref." }
Write-Host "Core selected: $ref."