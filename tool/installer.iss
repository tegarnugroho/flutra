; Inno Setup script for Flutra.
;
; Not run by hand — tool\build.ps1 compiles it and supplies the version and
; paths, so the installer can never disagree with the binary it wraps:
;
;   ISCC.exe /DMyAppVersion=1.0.4 /DSourceDir=... /DOutputDir=... installer.iss

#ifndef MyAppVersion
  #error MyAppVersion must be passed with /D — build via tool\build.ps1
#endif
#ifndef SourceDir
  #error SourceDir must be passed with /D — build via tool\build.ps1
#endif
#ifndef OutputDir
  #define OutputDir "..\build\installer"
#endif

#define MyAppName "Flutra"
#define MyAppPublisher "Tegar Nugroho"
#define MyAppURL "https://github.com/tegarnugroho/android_sdk_manager"
#define MyAppExeName "flutra.exe"

[Setup]
; Identifies the product across versions. Never change it: a new AppId makes
; Windows treat an upgrade as a second, parallel installation.
AppId={{44359FD9-1412-4751-9983-3F53BB31BA68}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
VersionInfoVersion={#MyAppVersion}

; Per-user by default, so installing needs no admin prompt. The app only ever
; writes to its own app-data folder and to HKCU (the run-at-startup setting),
; so nothing here needs machine-wide rights.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes

; The app is x64-only, like the Flutter Windows build it wraps.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

OutputDir={#OutputDir}
OutputBaseFilename=Flutra-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Flutter release output: the exe, its DLLs and the data folder.
; Excludes are build leftovers, not shipped artefacts — *.msix is the other
; packaging target's output and native_assets.json is a build manifest.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.msix,native_assets.json,*.pdb,*.exp,*.lib"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

; Deliberately no [UninstallDelete]: settings, the storage report and the dev
; log live in %APPDATA%\com.flutra\Flutra (the folder
; path_provider derives from the exe's CompanyName/ProductName). Wiping it on
; uninstall would also wipe it on every reinstall-over-upgrade, and losing a
; user's SDK path overrides is not worth the tidiness.

[Code]
// The app holds its own exe open while running, so an upgrade over a live
// install fails halfway. Ask first rather than leaving a half-written folder.
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  if Exec('cmd.exe', '/c tasklist /FI "IMAGENAME eq {#MyAppExeName}" | find /I "{#MyAppExeName}"',
          '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0) then
  begin
    if MsgBox('{#MyAppName} is running and must be closed before installing.' + #13#10#13#10 +
              'Close it now?', mbConfirmation, MB_YESNO) = IDYES then
      Exec('taskkill.exe', '/F /IM {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
    else
      Result := False;
  end;
end;
