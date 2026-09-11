; Inno Setup script for ShellVibe.
;
; Produces a per-user installer. ShellVibe needs no elevated privilege to run
; and asking for one at install time is what makes a terminal client look like
; something that wants more of the machine than it does; per-user also means the
; installer never has to be run as administrator on a locked-down workstation.
;
; Driven from tool/packaging/windows_package.ps1, which passes the version and
; the directory the build landed in.

#define AppName "ShellVibe"
#define AppPublisher "Mustafa Kilic"
#define AppUrl "https://github.com/klc/shellvibe"
#define AppExe "shellvibe.exe"

[Setup]
AppId={{9F2C4B1E-5A7D-4E3F-9C21-8B6D0A4E7F13}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile={#SourceRoot}\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=ShellVibe-{#AppVersion}-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Per-user: {autopf} resolves to the local app data program-files equivalent and
; no UAC prompt is raised.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExe}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole build output, because the Flutter runner resolves data\ and the
; plugin DLLs relative to its own executable and breaks if they are split up.
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
