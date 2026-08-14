#ifndef MyAppVersion
  #error MyAppVersion must be provided to ISCC.
#endif
#ifndef BuildRoot
  #error BuildRoot must be provided to ISCC.
#endif

#define MyAppName "Secure Tiles"
#define PortableName "Secure-Tiles-Portable-v" + MyAppVersion + ".exe"

[Setup]
AppId={{A81EF90B-8D5F-49D2-AEAA-570A1F8CF404}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=H0l10W
AppPublisherURL=https://github.com/H0l10W/secure-tiles
DefaultDirName={localappdata}\Programs\Secure Tiles
DefaultGroupName=Secure Tiles
DisableProgramGroupPage=yes
OutputDir={#BuildRoot}\dist
OutputBaseFilename=Secure-Tiles-Setup-v{#MyAppVersion}
SetupIconFile={#BuildRoot}\assets\secure_tiles.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\SecureTiles.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "{#BuildRoot}\dist\{#PortableName}"; DestDir: "{app}"; DestName: "SecureTiles.exe"; Flags: ignoreversion
Source: "{#BuildRoot}\CHANGELOG.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Secure Tiles"; Filename: "{app}\SecureTiles.exe"
Name: "{autodesktop}\Secure Tiles"; Filename: "{app}\SecureTiles.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\SecureTiles.exe"; Description: "Launch Secure Tiles"; Flags: nowait postinstall skipifsilent
