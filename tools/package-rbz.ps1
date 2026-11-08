# Packages the SketchUp extension as an .rbz (a zip with model_builder.rb at
# its root) into hosts\sketchup\dist\. Install it via
# Extensions > Extension Manager > Install Extension. Do not install the .rbz
# while the dev loader is present; run install-dev-loader.ps1 -Uninstall first.
#
#   powershell -ExecutionPolicy Bypass -File tools\package-rbz.ps1
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repo "hosts\sketchup\src"
$dist = Join-Path $repo "hosts\sketchup\dist"
$version = (Select-String -Path (Join-Path $src "model_builder\version.rb") -Pattern "VERSION = '([^']+)'").Matches[0].Groups[1].Value

New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "model_builder-$version.zip"
$rbz = Join-Path $dist "model_builder-$version.rbz"
Remove-Item $zip, $rbz -ErrorAction SilentlyContinue

Compress-Archive -Path (Join-Path $src "model_builder.rb"), (Join-Path $src "model_builder") -DestinationPath $zip
Move-Item $zip $rbz
Write-Host "Built $rbz"
