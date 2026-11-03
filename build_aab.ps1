# Builds the Catalyst Android app for Google Play: a signed App Bundle ->
# dist\catalyst_<version>.aab, to upload in Play Console (Test and release).
#
#   .\build_aab.ps1
#
# Or just double-click build_aab.bat. The Play build differs from the APK in one
# way: Google Play updates it, so it never looks for new versions on GitHub
# ("STORE=play", see lib/config.dart). Needs env.json (as for build_apk.ps1) and
# android\key.properties with the keystore the APKs are signed with, which is
# also the upload key Play Console knows.
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter) { $flutter = "C:\Users\faisa\dev\flutter\bin\flutter.bat" }
if (-not (Test-Path $flutter)) { Write-Host "Flutter not found. Install it or add it to PATH." -ForegroundColor Red; exit 1 }
if (-not (Test-Path "env.json")) {
  Write-Host "env.json missing: copy env.example.json to env.json and fill in your Supabase URL + anon key." -ForegroundColor Red
  exit 1
}
# Without key.properties the build falls back to the debug key, and Play refuses debug-signed bundles.
if (-not (Test-Path "android\key.properties")) {
  Write-Host "android\key.properties missing: Google Play only takes bundles signed with your upload key." -ForegroundColor Red
  exit 1
}

Write-Host "Getting packages..." -ForegroundColor Cyan
& $flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Host "flutter pub get failed." -ForegroundColor Red; exit 1 }

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
# The same version code as this version's APKs (2000 + the build number): it only
# ever goes up, and a phone with the GitHub APK takes the Play version as an update
# (when Play signs with the same key).
$build = [int](Select-String -Path pubspec.yaml -Pattern '^version:\s*[0-9.]+\+([0-9]+)').Matches[0].Groups[1].Value

Write-Host "Building the release App Bundle (first build downloads Gradle deps and takes a few minutes)..." -ForegroundColor Cyan
& $flutter build appbundle --release --build-number=$(2000 + $build) --obfuscate --split-debug-info=build\symbols --dart-define-from-file=env.json --dart-define=STORE=play
if ($LASTEXITCODE -ne 0) { Write-Host "Build failed - see the errors above." -ForegroundColor Red; exit 1 }

New-Item -ItemType Directory -Force dist | Out-Null
$name = "catalyst_$version.aab"
Copy-Item "build\app\outputs\bundle\release\app-release.aab" "dist\$name" -Force
# R8's mapping, for Play Console -> App bundle explorer -> Downloads -> ReTrace mapping file.
$mapping = "build\app\outputs\mapping\release\mapping.txt"
if (Test-Path $mapping) { Copy-Item $mapping "dist\catalyst_${version}_mapping.txt" -Force }
$mb = [math]::Round((Get-Item "dist\$name").Length / 1MB, 1)
Write-Host ""
Write-Host "App Bundle ready: $PSScriptRoot\dist\$name ($mb MB, version code $(2000 + $build))" -ForegroundColor Green
Write-Host "Upload it in Play Console -> Test and release. Keep build\symbols to read crash stack traces." -ForegroundColor Green
