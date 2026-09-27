# Build the release app for Windows: bundle the backend with PyInstaller, drop
# it into the Flutter assets, then build the Flutter app around it.
#
#   powershell -ExecutionPolicy Bypass -File scripts\build_all.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\build_all.ps1 -Python C:\Python312\python.exe

param(
    # Interpreter used to create the build venv.
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Backend = Join-Path $Root "backend"
$Frontend = Join-Path $Root "frontend"
$Venv = Join-Path $Backend ".venv-build"
$VenvPython = Join-Path $Venv "Scripts\python.exe"
$AssetDir = Join-Path $Frontend "assets\backend"

# $ErrorActionPreference does not cover native commands, so check each one.
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    # pip and PyInstaller log to stderr; when the script's output is redirected,
    # Windows PowerShell turns those lines into errors, which "Stop" would make
    # fatal. The exit code is the real signal.
    $ErrorActionPreference = "Continue"
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "'$Exe $($Arguments -join ' ')' failed with exit code $LASTEXITCODE"
    }
}

# A separate venv from the dev one (backend\.venv), so whatever happens to be
# installed there for development does not end up in the bundle.
Write-Host "==> Python venv ($Venv)"
if (-not (Test-Path $VenvPython)) {
    Invoke-Native $Python @("-m", "venv", $Venv)
}
Invoke-Native $VenvPython @("-m", "pip", "install", "--upgrade", "pip")
Invoke-Native $VenvPython @("-m", "pip", "install", "-r", (Join-Path $Backend "requirements.txt"), "pyinstaller")

Write-Host "==> PyInstaller"
# One folder, zipped: a one-file build unpacks itself on every launch, which
# with antivirus scanning the fresh files took ~15 s each time.
Invoke-Native $VenvPython @((Join-Path $Backend "build_backend.py"), "--onedir", "--zip")

Write-Host "==> Copy backend into Flutter assets"
New-Item -ItemType Directory -Force $AssetDir | Out-Null
# Anything left from an earlier build would be shipped too.
Get-ChildItem $AssetDir -Exclude ".gitkeep" | Remove-Item -Recurse -Force
foreach ($f in @("diagnostic_backend.zip", "diagnostic_backend.sha256")) {
    Copy-Item (Join-Path $Backend "dist\$f") (Join-Path $AssetDir $f) -Force
}

Write-Host "==> flutter build windows"
Push-Location $Frontend
try {
    Invoke-Native "flutter" @("build", "windows", "--release")
} finally {
    Pop-Location
}

Write-Host "`nDone: $(Join-Path $Frontend 'build\windows\x64\runner\Release')"
