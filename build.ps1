<#
.SYNOPSIS
    Export the Godot project to a standalone Windows executable.

.DESCRIPTION
    .\build.ps1              release build -> dist\snake.exe
    .\build.ps1 -Debug       debug build (keeps a console window)
    .\build.ps1 -SkipImport  skip the resource import pass

    The previous executable is deleted first, so the freshly produced binary
    can never be confused with an older one.
#>
param(
    [switch]$Debug,
    [switch]$SkipImport
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$project = Join-Path $root "game"
$exe = Join-Path $root "dist\snake.exe"
$preset = "Windows Desktop"

function Find-Godot {
    if ($env:GODOT -and (Test-Path $env:GODOT)) { return $env:GODOT }
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Godot\Godot_v*_win64_console.exe",
        "$env:LOCALAPPDATA\Programs\Godot\Godot_v*_win64.exe"
    )
    foreach ($pattern in $candidates) {
        $found = Get-ChildItem $pattern -ErrorAction SilentlyContinue |
                 Sort-Object Name -Descending | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    $onPath = Get-Command godot -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    throw "Godot not found. Install it or set the GODOT environment variable."
}

$godot = Find-Godot
Write-Output "[build] godot: $godot"

if (Test-Path $exe) {
    Remove-Item $exe -Force
    Write-Output "[build] removed previous snake.exe"
}
New-Item -ItemType Directory -Force -Path (Split-Path $exe) | Out-Null

if (-not $SkipImport) {
    Write-Output "[build] importing resources"
    & $godot --headless --import --path $project | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "[build] import FAILED with code $LASTEXITCODE" }
}

$mode = if ($Debug) { "--export-debug" } else { "--export-release" }
Write-Output "[build] $mode `"$preset`""
& $godot --headless --path $project $mode $preset | Out-Null
if ($LASTEXITCODE -ne 0) { throw "[build] export FAILED with code $LASTEXITCODE" }
if (-not (Test-Path $exe)) { throw "[build] FAILED: executable not produced" }

$item = Get-Item $exe
Write-Output "[build] OK -> $exe"
Write-Output ("[build] size={0:N1} MiB built={1:yyyy-MM-ddTHH:mm:ss}" -f ($item.Length / 1MB), $item.LastWriteTime)
