; AUWKI Agent - Inno Setup 安装脚本
; 用法（由 build_installer.ps1 自动调用）：
;   ISCC.exe AUWKI-Agent.iss /DStageDir="C:\path\to\stage" /DAppVersion=1.2.0

#ifndef AppVersion
  #define AppVersion "1.2.0"
#endif
#ifndef AppName
  #define AppName "AUWKI Agent"
#endif
#ifndef AppExeName
  #define AppExeName "auwki_agent.exe"
#endif
#ifndef StageDir
  #define StageDir "..\..\dist\installer\stage"
#endif

[Setup]
AppId={{7E1E6D6A-3B2C-4E9F-9C31-8F4A2B6C0D1E}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=AUWKI
AppVerName={#AppName} {#AppVersion}
DefaultDirName={commonpf32}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=..\..\dist\installer
OutputBaseFilename=AUWKI-Agent-Setup-{#AppVersion}-windows-x64
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763

[Languages]
Name: "chinesesimplified"; MessagesFile: "{#SourcePath}languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
