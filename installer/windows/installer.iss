; Inno Setup Script for CB File Hub
; Creates a single .exe installer

#define MyAppName "CB File Hub"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "COOLBIRDZIK"
#define MyAppURL "https://github.com/coolbirdzik/cb-file-hub"
#define MyAppExeName "cb_file_hub.exe"

[Setup]
; NOTE: The value of AppId uniquely identifies this application.
; Do not use the same AppId value in installers for other applications.
AppId={{683B4433-9621-4C1F-9A64-4F980BB8465D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
LicenseFile=assets\LicenseAgreement.txt
OutputDir=..\..\cb_file_manager\build\windows\installer
OutputBaseFilename=CBFileHub-Setup
SetupIconFile=..\..\cb_file_manager\windows\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
ChangesAssociations=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "vietnamese"; MessagesFile: "compiler:Languages\Vietnamese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\cb_file_manager\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\cb_file_manager\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Registry]
; Advertise choices; Windows Settings remains responsible for the user's defaults.
Root: HKLM; Subkey: "Software\Classes\CBFileHub.File.torrent"; ValueType: string; ValueData: "CB File Hub Torrent"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\CBFileHub.File.torrent\DefaultIcon"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"",0"
Root: HKLM; Subkey: "Software\Classes\CBFileHub.File.torrent\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" --open-torrent ""%1"""
Root: HKLM; Subkey: "Software\Classes\.torrent\OpenWithProgids"; ValueType: string; ValueName: "CBFileHub.File.torrent"; ValueData: ""; Flags: uninsdeletevalue
Root: HKLM; Subkey: "Software\Classes\CBFileHub.Magnet"; ValueType: string; ValueData: "CB File Hub Magnet Link"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Classes\CBFileHub.Magnet"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKLM; Subkey: "Software\Classes\CBFileHub.Magnet\DefaultIcon"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"",0"
Root: HKLM; Subkey: "Software\Classes\CBFileHub.Magnet\shell\open\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" --open-torrent ""%1"""
Root: HKLM; Subkey: "Software\COOLBIRDZIK\CB File Hub\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "CB File Hub"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\COOLBIRDZIK\CB File Hub\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Torrent library and file manager"
Root: HKLM; Subkey: "Software\COOLBIRDZIK\CB File Hub\Capabilities\FileAssociations"; ValueType: string; ValueName: ".torrent"; ValueData: "CBFileHub.File.torrent"
Root: HKLM; Subkey: "Software\COOLBIRDZIK\CB File Hub\Capabilities\URLAssociations"; ValueType: string; ValueName: "magnet"; ValueData: "CBFileHub.Magnet"
Root: HKLM; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "CB File Hub"; ValueData: "Software\COOLBIRDZIK\CB File Hub\Capabilities"; Flags: uninsdeletevalue

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
