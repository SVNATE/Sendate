; Inno Setup Script for Sendate Windows Installer
; Download Inno Setup from: https://jrsoftware.org/isinfo.php

#define MyAppName "Sendate"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "SVNATE"
#define MyAppURL "https://sendate.svnate.com"
#define MyAppExeName "sendate.exe"

[Setup]
; Unique App ID - DO NOT change this between versions
AppId={{A7F3B2C1-5D4E-4F6A-8B9C-0E1D2F3A4B5C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; Output location (relative to this .iss file)
OutputDir=..\..\build\installer
OutputBaseFilename=Sendate-{#MyAppVersion}-Setup
; Installer icon
SetupIconFile=..\runner\resources\app_icon.ico
; Compression
Compression=lzma2/ultra64
SolidCompression=yes
; UI
WizardStyle=modern
; Privileges - per-user install (no admin required)
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Uninstaller
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
; Architecture
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Minimum Windows version (Windows 10)
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startupentry"; Description: "Start Sendate when Windows starts"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
; Main executable and all files from the release build
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; Start with Windows (optional task)
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: startupentry
; Add firewall exception for local network discovery
Root: HKCU; Subkey: "Software\{#MyAppName}"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; Flags: uninsdeletekey

[Run]
; Launch app after install
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// Add Windows Firewall rule during install for network discovery
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    // Add inbound firewall rule for Sendate (TCP)
    Exec('netsh', 'advfirewall firewall add rule name="Sendate TCP" dir=in action=allow program="' + ExpandConstant('{app}\{#MyAppExeName}') + '" protocol=tcp enable=yes', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    // Add inbound firewall rule for Sendate (UDP - for discovery)
    Exec('netsh', 'advfirewall firewall add rule name="Sendate UDP" dir=in action=allow program="' + ExpandConstant('{app}\{#MyAppExeName}') + '" protocol=udp enable=yes', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

// Remove firewall rules on uninstall
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    Exec('netsh', 'advfirewall firewall delete rule name="Sendate TCP"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec('netsh', 'advfirewall firewall delete rule name="Sendate UDP"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;
