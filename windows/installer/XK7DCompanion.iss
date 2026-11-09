; XK-7D Companion for Windows: the installer (Inno Setup 6).
; Built by windows\build.ps1:  ISCC /DAppVersion=x.y.z /DSourceDir=...\dist\app /DOutputName=... XK7DCompanion.iss
;
; Installs for the current person only, into their own Programs folder, so it never asks for an
; administrator password. Adds a Start menu entry and an entry in Settings, Apps for uninstalling.
; Uninstalling leaves settings alone. WinSparkle runs this same installer quietly to update.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\dist\app"
#endif
#ifndef OutputName
  #define OutputName "XK-7D-Companion-Setup"
#endif

[Setup]
; Never change AppId: it's how Windows knows a new version replaces the old one.
AppId={{FDF52F9A-A8E7-4E33-BFAC-FC086FF03106}
AppName=XK-7D Companion
AppVersion={#AppVersion}
AppVerName=XK-7D Companion {#AppVersion}
AppPublisher=Matthew Whitaker
AppPublisherURL=https://github.com/Matthew2244/xk7d-companion
AppSupportURL=https://github.com/Matthew2244/xk7d-companion/issues
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\XK-7D Companion
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename={#OutputName}
UninstallDisplayIcon={app}\XK7DCompanion.exe
UninstallDisplayName=XK-7D Companion
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Close a running copy before replacing it.
CloseApplications=yes
RestartApplications=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

[Tasks]
Name: "desktopicon"; Description: "Put XK-7D Companion on the desktop"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[InstallDelete]
; A new version may drop files the old one had: start clean inside the app folder only.
Type: filesandordirs; Name: "{app}\*.dll"

[Icons]
Name: "{autoprograms}\XK-7D Companion"; Filename: "{app}\XK7DCompanion.exe"
Name: "{autodesktop}\XK-7D Companion"; Filename: "{app}\XK7DCompanion.exe"; Tasks: desktopicon

[Run]
; After a normal install: offer to open it. After a quiet update (WinSparkle): open it again.
Filename: "{app}\XK7DCompanion.exe"; Description: "Open XK-7D Companion now"; Flags: nowait postinstall skipifsilent
Filename: "{app}\XK7DCompanion.exe"; Flags: nowait; Check: Relaunch

[Code]
// WinSparkle passes /relaunch=1 when it runs this quietly to update, so the app comes back by
// itself. A quiet install without it (CI, an administrator) opens nothing.
function Relaunch(): Boolean;
begin
  Result := WizardSilent() and (ExpandConstant('{param:relaunch|0}') = '1');
end;
