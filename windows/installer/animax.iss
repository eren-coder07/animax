; Inno Setup script — packs the Flutter Windows release folder into a
; single AnimaxSetup-<version>-x64.exe installer (per-user, no admin).
; Built by .github/workflows/build-windows.yml:
;   ISCC.exe /DAppVersion=1.9.2 windows\installer\animax.iss

#ifndef AppVersion
  #define AppVersion "2.5.0"
#endif

[Setup]
AppId={{6F1D2B7E-3A4C-4E8B-9C1D-5A7E2F3B9D41}
AppName=Animax
AppVersion={#AppVersion}
AppVerName=Animax {#AppVersion}
AppPublisher=Animax
DefaultDirName={localappdata}\Programs\Animax
DefaultGroupName=Animax
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\dist
OutputBaseFilename=AnimaxSetup-{#AppVersion}-x64
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\animax.exe
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Animax"; Filename: "{app}\animax.exe"
Name: "{autodesktop}\Animax"; Filename: "{app}\animax.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\animax.exe"; Description: "{cm:LaunchProgram,Animax}"; Flags: nowait postinstall skipifsilent
