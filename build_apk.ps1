# Builds the Catalyst Android app as a release APK -> dist\catalyst_<version>.apk
#
#   .\build_apk.ps1            universal APK (works on every Android phone)
#   .\build_apk.ps1 -Small     smaller APK for modern 64-bit phones (arm64) only
#   .\build_apk.ps1 -Install   build, then install on a USB-connected phone (adb)
#
# Or just double-click build_apk.bat. Needs env.json (Supabase URL + anon key,
# the same values the web app uses) - copy env.example.json if it's missing.
param([switch]$Install, [switch]$Small)

$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter) { $flutter = "C:\Users\faisa\dev\flutter\bin\flutter.bat" }
if (-not (Test-Path $flutter)) { Write-Host "Flutter not found. Install it or add it to PATH." -ForegroundColor Red; exit 1 }
if (-not (Test-Path "env.json")) {
  Write-Host "env.json missing: copy env.example.json to env.json and fill in your Supabase URL + anon key." -ForegroundColor Red
  exit 1
}

Write-Host "Getting packages..." -ForegroundColor Cyan
& $flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Host "flutter pub get failed." -ForegroundColor Red; exit 1 }

# The file is named after the version in pubspec.yaml: catalyst_1.6.0.apk
$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value

Write-Host "Building release APK (first build downloads Gradle deps and takes a few minutes)..." -ForegroundColor Cyan
if ($Small) {
  & $flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build\symbols --dart-define-from-file=env.json
  $apk = "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
  $name = "catalyst_${version}_arm64.apk"
} else {
  & $flutter build apk --release --obfuscate --split-debug-info=build\symbols --dart-define-from-file=env.json
  $apk = "build\app\outputs\flutter-apk\app-release.apk"
  $name = "catalyst_$version.apk"
}
if ($LASTEXITCODE -ne 0) { Write-Host "Build failed - see the errors above." -ForegroundColor Red; exit 1 }

New-Item -ItemType Directory -Force dist | Out-Null
Copy-Item $apk "dist\$name" -Force
$mb = [math]::Round((Get-Item "dist\$name").Length / 1MB, 1)
Write-Host ""
Write-Host "APK ready: $PSScriptRoot\dist\$name ($mb MB)" -ForegroundColor Green
Write-Host "Copy it to your phone (USB, Drive, Telegram...) and open it to install." -ForegroundColor Green

if ($Install) {
  $adb = "C:\Users\faisa\dev\android-sdk\platform-tools\adb.exe"
  if (-not (Test-Path $adb)) { $adb = (Get-Command adb -ErrorAction SilentlyContinue).Source }
  if (-not $adb) { Write-Host "adb not found; install the APK manually." -ForegroundColor Yellow; exit 0 }
  Write-Host "Installing on the connected device..." -ForegroundColor Cyan
  & $adb install -r "dist\$name"
}
