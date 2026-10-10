; Inno Setup script for the Windows installer. Build it with
; scripts\build_installer.ps1, which passes the defines below; compiling this
; file directly works too and falls back to the defaults.
;
; The backend needs no entry of its own: it is a Flutter asset
; (data\flutter_assets\assets\backend\), so it comes along with the Release
; folder, and the app unpacks it to %LOCALAPPDATA% on first start.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef ReleaseDir
  #define ReleaseDir "..\frontend\build\windows\x64\runner\Release"
#endif
; The MSVC runtime DLLs Flutter's runner links against, staged by
; build_installer.ps1. Shipped next to the exe so the app also starts on
; machines without the Visual C++ Redistributable.
#ifndef VcRuntimeDir
  #define VcRuntimeDir "build\vcruntime"
#endif

#define AppName "Medical Diagnosis Assistant"
#define AppExeName "diagnostic_app.exe"
#define BackendExeName "diagnostic_backend.exe"
; Must match CompanyName\ProductName in frontend\windows\runner\Runner.rc:
; path_provider builds the app's cache folder from them.
#define AppCacheDir "{localappdata}\com.diagnostic\diagnostic_app"

[Setup]
; Identifies the app across versions, so an update replaces the install
; instead of adding a second one. Never change it.
AppId={{64F41A41-DC38-434C-90F8-73F03710753A}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=com.diagnostic
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
; {localappdata} is only touched by the uninstaller, to clear the backend cache
; of the user running it; other users' caches are simply left behind.
UsedUserAreasWarning=no
; Flutter's Windows build is x64 only.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=output
OutputBaseFilename=MedicalDiagnosisAssistant-{#AppVersion}-setup
SetupIconFile=..\frontend\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Lets Setup close a running copy of the app before replacing its files.
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#VcRuntimeDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; The backend runs from the cache folder, not {app}, so the app closing does
; not guarantee it is gone; a running backend would keep its folder locked.
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#BackendExeName}"; Flags: runhidden; RunOnceId: "KillBackend"

[UninstallDelete]
; The unpacked backend (a few hundred MB), recreated from the asset on start.
; User data (config, sessions CSVs, model configs) lives in Documents and is
; deliberately left alone.
Type: filesandordirs; Name: "{#AppCacheDir}\backend"
Type: dirifempty; Name: "{#AppCacheDir}"
Type: dirifempty; Name: "{localappdata}\com.diagnostic"
