; Inno Setup 6.3+; compile through scripts/package.py.
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef PackageName
  #error PackageName is required
#endif

[Setup]
AppId={{D2B32ACF-3F94-4D3D-8D3C-847F45A1D428}
AppName=Kazumi
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\Kazumi
DefaultGroupName=Kazumi
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputBaseFilename={#PackageName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\kazumi.exe
CloseApplications=yes
ChangesAssociations=yes

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Icons]
Name: "{group}\Kazumi"; Filename: "{app}\kazumi.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\Kazumi"; Filename: "{app}\kazumi.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
; Register deep links for this user; quote both the executable and URL argument.
Root: HKCU; Subkey: "Software\Classes\kazumi"; ValueType: string; ValueName: ""; ValueData: "URL:Kazumi Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\kazumi"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\kazumi\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\kazumi.exe"",0"
Root: HKCU; Subkey: "Software\Classes\kazumi\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\kazumi.exe"" ""%1"""

[Run]
Filename: "{app}\kazumi.exe"; Description: "Launch Kazumi"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
