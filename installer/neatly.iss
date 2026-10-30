; Instalador do Neatly (Inno Setup 6). Sem administrador: instala para o
; usuário atual em %LOCALAPPDATA%\Programs\Neatly.
;   iscc /DVersao=2.0.0 installer\neatly.iss

#ifndef Versao
  #define Versao "0.0.0"
#endif

[Setup]
AppId={{89271CB6-882D-4043-B40C-FE4C5C978FF4}
AppName=Neatly
AppVersion={#Versao}
AppVerName=Neatly {#Versao}
AppPublisher=Arturo Andreatta
AppPublisherURL=https://github.com/ArturoAndreatta/neatly
AppSupportURL=https://github.com/ArturoAndreatta/neatly/issues
DefaultDirName={localappdata}\Programs\Neatly
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
OutputDir=saida
OutputBaseFilename=NeatlySetup
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\neatly.exe
UninstallDisplayName=Neatly
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=force
RestartApplications=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "pt"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "atalho"; Description: "Atalho na área de trabalho"

[Files]
Source: "..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Atalhos do Neatly 1 (abriam o painel no navegador). Os novos vêm logo depois.
Type: files; Name: "{userdesktop}\Neatly.lnk"
Type: files; Name: "{userprograms}\Neatly.lnk"
Type: files; Name: "{userdesktop}\Organizador de Downloads.lnk"
Type: files; Name: "{userprograms}\Organizador de Downloads.lnk"
Type: files; Name: "{userdesktop}\Painel Downloads.lnk"
Type: files; Name: "{userprograms}\Painel Downloads.lnk"

[Icons]
Name: "{userprograms}\Neatly"; Filename: "{app}\neatly.exe"
Name: "{userdesktop}\Neatly"; Filename: "{app}\neatly.exe"; Tasks: atalho

[Run]
Filename: "{app}\neatly.exe"; Description: "Abrir o Neatly"; Flags: nowait postinstall skipifsilent
; Atualização silenciosa (pelo próprio app): abre de novo sozinho.
Filename: "{app}\neatly.exe"; Flags: nowait; Check: WizardSilent

[UninstallRun]
; Uma tarefa só, com o gatilho diário e o de logon (Arrumar ao ligar o PC).
Filename: "schtasks.exe"; Parameters: "/Delete /TN Neatly /F"; Flags: runhidden; RunOnceId: "TarefaNeatly"

[UninstallDelete]
Type: filesandordirs; Name: "{localappdata}\Neatly"

[Code]
procedure Rodar(const Exe, Parametros: String);
var
  Codigo: Integer;
begin
  Exec(Exe, Parametros, '', SW_HIDE, ewWaitUntilTerminated, Codigo);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    { Neatly 1: fecha o painel (PowerShell na porta 8765) e tira a tarefa
      dele. A tarefa diária "Neatly" o app novo regrava ao abrir. }
    Rodar(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      '-NoProfile -Command "Get-CimInstance Win32_Process | ' +
      'Where-Object { $_.CommandLine -like ''*\Neatly\painel.ps1*'' } | ' +
      'ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"');
    Rodar('schtasks.exe', '/Delete /TN "Neatly - Painel" /F');
  end;
end;
