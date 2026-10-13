; Inno Setup installer script for Randil Grocery POS
; This creates a professional setup.exe installer
;
; Build (from this folder):
;   "C:\Users\jerus\AppData\Local\Programs\Inno Setup 6\ISCC.exe" installer.iss
;
; NOTE: All paths are RELATIVE to this .iss file so the script keeps
; working if the project folder is moved to another drive/folder.

[Setup]
AppName=Randil Grocery POS
AppVersion=1.1.20
AppPublisher=Jerusha Sharon - Randil Grocery
AppPublisherURL=https://www.randilgrocery.com
AppSupportURL=https://www.randilgrocery.com
AppUpdatesURL=https://www.randilgrocery.com
AppCopyright=Copyright ?? 2026 Jerusha Sharon. All rights reserved.
; Install to Program Files with a proper elevation prompt (reliable on client PCs)
DefaultDirName={autopf}\Randil Grocery POS
DefaultGroupName=Randil Grocery POS
OutputDir=installer_output
OutputBaseFilename=Randil-Grocery-POS-Setup-v1.1.20
Compression=lzma2
SolidCompression=yes
DisableDirPage=no
DisableProgramGroupPage=no
AllowNoIcons=yes
PrivilegesRequired=admin
ShowLanguageDialog=auto
UninstallDisplayIcon={app}\randil_grocery_pos.exe
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
VersionInfoCompany=Jerusha Sharon
VersionInfoProductName=Randil Grocery POS
VersionInfoProductVersion=1.1.20
VersionInfoVersion=1.1.20
VersionInfoCopyright=Jerusha Sharon 2026

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Entire compiled Flutter Windows release (exe + ALL plugin DLLs + data\).
; The exe alone is only a launcher - it needs every DLL next to it.
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Microsoft C++ runtime, bundled app-local so the POS starts on any PC
; (fixes "VCRUNTIME140_1.dll was not found" on machines without the VC++ Redistributable).
Source: "redist\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "redist\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "redist\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "redist\msvcp140_1.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "redist\msvcp140_2.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Randil Grocery POS"; Filename: "{app}\randil_grocery_pos.exe"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,Randil Grocery POS}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Randil Grocery POS"; Filename: "{app}\randil_grocery_pos.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\randil_grocery_pos.exe"; Description: "{cm:LaunchProgram,Randil Grocery POS}"; Flags: nowait postinstall skipifsilent

[Code]
// Friendly confirmation once installation finishes
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    MsgBox('Randil Grocery POS has been successfully installed!'#13#13'Developer: Jerusha Sharon'#13#13'You can now launch the application from the Start Menu or Desktop shortcut.',
           mbInformation, MB_OK);
  end;
end;

