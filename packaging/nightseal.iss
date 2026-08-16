#ifndef MyAppVersion
  #error MyAppVersion must be provided to ISCC.
#endif
#ifndef BuildRoot
  #error BuildRoot must be provided to ISCC.
#endif

#define MyAppName "Nightseal"
#define PortableName "Nightseal-Portable-v" + MyAppVersion + ".exe"

[Setup]
AppId={{A81EF90B-8D5F-49D2-AEAA-570A1F8CF404}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=H0l10W
AppPublisherURL=https://github.com/H0l10W/nightseal
DefaultDirName={localappdata}\Programs\Nightseal
DefaultGroupName=Nightseal
DisableProgramGroupPage=yes
OutputDir={#BuildRoot}\dist
OutputBaseFilename=Nightseal-Setup-v{#MyAppVersion}
SetupIconFile={#BuildRoot}\assets\nightseal.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\Nightseal.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "{#BuildRoot}\dist\{#PortableName}"; DestDir: "{app}"; DestName: "Nightseal.exe"; Flags: ignoreversion
Source: "{#BuildRoot}\CHANGELOG.md"; DestDir: "{app}"; Flags: ignoreversion

[InstallDelete]
Type: files; Name: "{app}\SecureTiles.exe"
Type: files; Name: "{autodesktop}\Secure Tiles.lnk"
Type: files; Name: "{autoprograms}\Secure Tiles.lnk"

[Icons]
Name: "{autoprograms}\Nightseal"; Filename: "{app}\Nightseal.exe"
Name: "{autodesktop}\Nightseal"; Filename: "{app}\Nightseal.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\Nightseal.exe"; Description: "Launch Nightseal"; Flags: nowait postinstall skipifsilent
