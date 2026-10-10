# Build the Windows installer from an existing release build (run
# scripts\build_all.ps1 first). Needs Inno Setup 6.3+ (https://jrsoftware.org/isinfo.php).
#
#   powershell -ExecutionPolicy Bypass -File scripts\build_installer.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\build_installer.ps1 -Iscc "D:\Inno Setup 6\ISCC.exe"

param(
    # Inno Setup command-line compiler; looked up in the usual places if not given.
    [string]$Iscc = ""
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Frontend = Join-Path $Root "frontend"
$Release = Join-Path $Frontend "build\windows\x64\runner\Release"
$InstallerDir = Join-Path $Root "installer"
$Script = Join-Path $InstallerDir "diagnostic_app.iss"
$VcRuntime = Join-Path $InstallerDir "build\vcruntime"

function Find-Iscc {
    $cmd = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, (Join-Path $env:LOCALAPPDATA "Programs"))) {
        if (-not $base) { continue }
        $candidate = Join-Path $base "Inno Setup 6\ISCC.exe"
        if (Test-Path $candidate) { return $candidate }
    }
    throw "ISCC.exe not found. Install Inno Setup 6 or pass -Iscc <path to ISCC.exe>."
}

if (-not $Iscc) { $Iscc = Find-Iscc }

# An installer without the backend would install fine and then fail on every
# start, so refuse to build one.
foreach ($f in @("diagnostic_app.exe", "data\flutter_assets\assets\backend\diagnostic_backend.zip")) {
    if (-not (Test-Path (Join-Path $Release $f))) {
        throw "$f missing from $Release. Run scripts\build_all.ps1 first."
    }
}

# "version: 1.2.3+4" -> "1.2.3"; the build number is not part of the installer version.
$versionLine = Select-String -Path (Join-Path $Frontend "pubspec.yaml") -Pattern '^version:\s*([0-9.]+)' | Select-Object -First 1
if (-not $versionLine) { throw "No version found in pubspec.yaml" }
$Version = $versionLine.Matches[0].Groups[1].Value

Write-Host "==> Stage MSVC runtime"
# Read through Sysnative from a 32-bit PowerShell, or WOW64 redirection would
# hand over the 32-bit DLLs from SysWOW64.
$System = if ([Environment]::Is64BitProcess) { "System32" } else { "Sysnative" }
New-Item -ItemType Directory -Force $VcRuntime | Out-Null
foreach ($dll in @("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")) {
    Copy-Item (Join-Path $env:WINDIR "$System\$dll") (Join-Path $VcRuntime $dll) -Force
}

Write-Host "==> Inno Setup ($Iscc), version $Version"
& $Iscc "/DAppVersion=$Version" "/DReleaseDir=$Release" "/DVcRuntimeDir=$VcRuntime" $Script
if ($LASTEXITCODE -ne 0) {
    throw "ISCC failed with exit code $LASTEXITCODE"
}

Write-Host "`nDone: $(Join-Path $InstallerDir "output\MedicalDiagnosisAssistant-$Version-setup.exe")"
