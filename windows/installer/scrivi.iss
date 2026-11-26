; Installationsprogramm für Scrivi (Inno Setup). Wird beim Build erzeugt:
;   iscc /DAppVersion=0.1.50 windows\installer\scrivi.iss
; Scrivi wird nur für den eigenen Benutzer installiert (keine Admin-Rechte nötig),
; in %LOCALAPPDATA%\Programs\Scrivi. Dort darf sich Scrivi selbst aktualisieren.
; Die Stücke liegen woanders (%APPDATA%\Scrivi) und bleiben beim Deinstallieren.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{706EA91F-3C12-4A3E-AF25-99E9641102F6}
AppName=Scrivi
AppVersion={#AppVersion}
AppVerName=Scrivi {#AppVersion}
AppPublisher=Scrivi
DefaultDirName={localappdata}\Programs\Scrivi
DisableDirPage=yes
DefaultGroupName=Scrivi
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\build\installer
OutputBaseFilename=Scrivi-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Scrivi.exe
UninstallDisplayName=Scrivi
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
ShowLanguageDialog=no
LanguageDetectionMethod=uilanguage
CloseApplications=force
RestartApplications=no

[Languages]
; Sprache nach Windows: Deutsch (Schweizer Schreibweise) oder Englisch.
Name: "de"; MessagesFile: "German-CH.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Scrivi"; Filename: "{app}\Scrivi.exe"
Name: "{autodesktop}\Scrivi"; Filename: "{app}\Scrivi.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Scrivi.exe"; Description: "{cm:LaunchProgram,Scrivi}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Programmordner ganz wegräumen (auch alte Dateien von Updates). Die Noten
; liegen nicht hier und bleiben erhalten.
Type: filesandordirs; Name: "{app}"
