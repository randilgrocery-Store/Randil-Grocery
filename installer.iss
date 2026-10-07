; Inno Setup installer script for Randil Grocery POS
; This creates a professional setup.exe installer

[Setup]
AppName=Randil Grocery POS
AppVersion=1.0.0
AppPublisher=Jerusha Sharon - Randil Grocery
AppPublisherURL=https://www.randilgrocery.com
AppSupportURL=https://www.randilgrocery.com
AppUpdatesURL=https://www.randilgrocery.com
AppCopyright=Copyright © 2026 Jerusha Sharon. All rights reserved.
DefaultDirName={pf}\Randil Grocery POS
DefaultGroupName=Randil Grocery POS
OutputDir=C:\Users\jerus\Desktop\Randil Grocery POS\installer_output
OutputBaseFilename=Randil-Grocery-POS-Setup-v1.0
Compression=lzma2
SolidCompression=yes
DisableDirPage=no
DisableProgramGroupPage=no
AllowNoIcons=yes
PrivilegesRequired=lowest
ShowLanguageDialog=auto
UninstallDisplayIcon={app}\randil_grocery_pos.exe
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
VersionInfoCompany=Jerusha Sharon
VersionInfoProductName=Randil Grocery POS
VersionInfoProductVersion=1.0.0
VersionInfoCopyright=Jerusha Sharon 2024-2025

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 0,6.1

[Files]
; Main executable and DLL files
Source: "C:\Users\jerus\Desktop\Randil Grocery POS\build\windows\x64\runner\Release\randil_grocery_pos.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\Users\jerus\Desktop\Randil Grocery POS\build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\Users\jerus\Desktop\Randil Grocery POS\build\windows\x64\runner\Release\sqlite3.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\Users\jerus\Desktop\Randil Grocery POS\build\windows\x64\runner\Release\screen_retriever_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\Users\jerus\Desktop\Randil Grocery POS\build\windows\x64\runner\Release\window_manager_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion

; Data folder (assets, fonts, etc.)
Source: "C:\Users\jerus\Desktop\Randil Grocery POS\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Randil Grocery POS"; Filename: "{app}\randil_grocery_pos.exe"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,Randil Grocery POS}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Randil Grocery POS"; Filename: "{app}\randil_grocery_pos.exe"; WorkingDir: "{app}"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\Randil Grocery POS"; Filename: "{app}\randil_grocery_pos.exe"; WorkingDir: "{app}"; Tasks: quicklaunchicon

[Run]
Filename: "{app}\randil_grocery_pos.exe"; Description: "{cm:LaunchProgram,Randil Grocery POS}"; Flags: nowait postinstall skipifsilent

[Code]
// Optional: Add code here for custom installation logic
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    // Add any post-installation tasks here
    MsgBox('Randil Grocery POS has been successfully installed!'#13#13'Developer: Jerusha Sharon'#13#13'You can now launch the application from the Start Menu or Desktop shortcut.', 
           mbInformation, MB_OK);
  end;
end;
