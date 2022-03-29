unit Instalador;

interface

uses
  Winapi.Windows, WinInet, System.SysUtils, System.Classes, System.Zip,
  Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Mask, Vcl.Printers,
  ShlObj, ActiveX, ComObj, Registry, IniFiles, Urlmon, Vcl.Controls, IdStack,
  Data.Bind.Components, Data.Bind.ObjectScope, REST.Types, REST.Client;

type
  TForm1 = class(TForm)
    Label1: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Button1: TButton;
    chkTSprint: TCheckBox;
    chkPainel: TCheckBox;
    txtUser: TMaskEdit;
    txtRemota: TEdit;
    txtPainel: TEdit;
    chkArquivos: TCheckBox;
    RESTClient1: TRESTClient;
    RESTRequest1: TRESTRequest;
    RESTResponse1: TRESTResponse;
    chkAdobe: TCheckBox;
    procedure chkTSprintKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure chkArquivosKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure FormCreate(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure chkPainelKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure chkAdobeKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
  private
    { Private declarations }
    function criptografar(texto: string): string;
  public
    { Public declarations }
  end;

var
  Form1: TForm1;
  Directory, TSprintDirectory, ShellStartup, IconDirectory, UrlDirectory: string;
  EqTsPort, defaultPrinter: string;
  ProjectName: string;
  UnilabIcon, ArquivosIcon, PainelIcon: string;
  URLacesso, URLPainel, URLArquivos: string;
  Cripto: array [0 .. 9] of string;
  zipFile: TZipFile;
  F, arq: TextFile;

implementation

{$R *.dfm}

const
  SID_IUniformResourceLocatorA = '{FBF23B80-E3F0-101B-8488-00AA003E56F8}';
  SID_IUniformResourceLocatorW = '{CABB0DA0-DA57-11CF-9974-0020AFD79762}';
  SID_InternetShortcut = '{FBF23B40-E3F0-101B-8488-00AA003E56F8}';

type
  PUrlInvokeCommandInfoA = ^TUrlInvokeCommandInfoA;
  TUrlInvokeCommandInfoA = record
    dwcbSize,
    dwFlags: DWORD;  // Bit field of IURL_INVOKECOMMAND_FLAGS
    hwndParent: HWND;  // Parent window. Valid only if IURL_INVOKECOMMAND_FL_ALLOW_UI is set.
    pcszVerb: LPCSTR;  // Verb to invoke. Ignored if IURL_INVOKECOMMAND_FL_USE_DEFAULT_VERB is set.
  end;

  PUrlInvokeCommandInfoW = ^TUrlInvokeCommandInfoW;
  TUrlInvokeCommandInfoW = record
    dwcbSize,
    dwFlags: DWORD;
    hwndParent: HWND;
    pcszVerb: LPCWSTR;
  end;

  IUniformResourceLocatorA = interface( IUnknown )
    [SID_IUniformResourceLocatorA]
    function SetURL( pcszURL: LPCSTR; dwInFlags: DWORD ): HRESULT; stdcall;
    function GetURL( ppszURL: LPSTR ): HRESULT; stdcall;
    function InvokeCommand( purlici: PUrlInvokeCommandInfoA ): HRESULT; stdcall;

  end;

  IUniformResourceLocatorW = interface( IUnknown )
    [SID_IUniformResourceLocatorW]
    function SetURL( pcszURL: LPCWSTR; dwInFlags: DWORD ): HRESULT; stdcall;
    function GetURL( ppszURL: LPWSTR ): HRESULT; stdcall;
    function InvokeCommand(purlici: PUrlInvokeCommandInfoW ): HRESULT; stdcall;
  end;

function SetURL( sFile, sUrl: Widestring ): Integer;
const
  CLSID_InternetShortCut: TGUID= SID_InternetShortcut;
var
  oUrl: IUniformResourceLocatorW;
  oFile: IPersistFile;
  hFile: THandle;
begin
  // First, the existing file's content should be emptied
  hFile:= CreateFileW( PWideChar(sFile), GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0 );
  if hFile= INVALID_HANDLE_VALUE then begin
    result:= 1;  // File might not exist, sharing violation, etc.
    exit;
  end;

  // Initial file pointer is at position 0
  if not SetEndOfFile( hFile ) then begin
    result:= 2;  // Missing permissions, etc.
    CloseHandle( hFile );
    exit;
  end;

  // Gracefully end accessing the file
  if not CloseHandle( hFile ) then begin
    result:= 3;  // File system crashed, etc.
    exit;
  end;

  // Using COM to access properties
  result:= 0;
  try
    oUrl:= CreateComObject( CLSID_InternetShortCut ) as IUniformResourceLocatorW;
  except
    result:= 4;  // CLSID unsupported, COM not available, etc.
  end;
  if result<> 0 then exit;

  // Opening the file again
  oFile:= oUrl as IPersistFile;
  if oFile.Load( PWideChar(sFile), STGM_READWRITE )<> S_OK then begin
    result:= 5;  // Sharing violations, access permissions, etc.
    exit;
  end;

  // Set the property as per interface - only saving the file is not enough
  if oUrl.SetURL( PWideChar(sUrl), 0 )<> S_OK then begin
    result:= 6;
    exit;
  end;

  // Storing the file's new content - setting only the property is not enough
  if oFile.Save( PWideChar(sFile), TRUE )<> S_OK then begin
    result:= 7;
    exit;
  end;

  // Success!
  result:= 0;
end;

{Fun��o para pegar impressora padr�o do Windows}
function GetDefaultPrinterName: string;

begin

  if (Printer.PrinterIndex >= 0) then
  begin
    Result := Printer.Printers[Printer.PrinterIndex];
  end

  {Caso n�o tenha nenhuma impressora padr�o}
  else
  begin
    Result := 'Nenhuma impressora padr�o foi detectada.';
  end;

end;

function GetMacAddress: String;
var
  lib: Cardinal;
  funcao: function(GUID: PGUID): Longint; stdcall;
  GUID1, GUID2: TGUID;
begin

  result := '00-00-00-00-00-00';

  lib := LoadLibrary( 'rpcrt4.dll' );

  if lib <> 0 then
    begin

      @funcao := GetProcAddress( lib, 'UuidCreateSequential' );

      if Assigned( funcao ) then
        begin

          if ( funcao( @GUID1 ) = 0 ) and
             ( funcao( @GUID2 ) = 0 ) and
             ( GUID1.D4[2] = GUID2.D4[2] ) and ( GUID1.D4[3] = GUID2.D4[3] ) and
             ( GUID1.D4[4] = GUID2.D4[4] ) and ( GUID1.D4[5] = GUID2.D4[5] ) and
             ( GUID1.D4[6] = GUID2.D4[6] ) and ( GUID1.D4[7] = GUID2.D4[7] ) then
          begin

            result := IntToHex( GUID1.D4[2], 2 ) + '-' + IntToHex( GUID1.D4[3], 2 ) + '-' +
                      IntToHex( GUID1.D4[4], 2 ) + '-' + IntToHex( GUID1.D4[5], 2 ) + '-' +
                      IntToHex( GUID1.D4[6], 2 ) + '-' + IntToHex( GUID1.D4[7], 2 );

          end;

        end;

      { ** Liberando a biblioteca utilizada pela rotina ** }
      FreeLibrary( lib );

    end;

end;


function GetIP : String;
begin
  TIdStack.IncUsage;
  try
    Result := GStack.LocalAddress;
  finally
    TIdStack.DecUsage;
  end;
end;

//function GetComputerNameFunc : string;
//var ipbuffer : string;
//      nsize : dword;
//begin
//   nsize := 255;
//   SetLength(ipbuffer,nsize);
//   if GetComputerName(pchar(ipbuffer),nsize) then
//      result := ipbuffer;
//end;

{Armazenar o diret�rio do Desktop}
function DesktopDir: string;
var
  DesktopPidl: PItemIDList;
  DesktopPath: array [0 .. MAX_PATH] of Char;

begin

  SHGetSpecialFolderLocation(0, CSIDL_DESKTOP, DesktopPidl);
  SHGetPathFromIDList(DesktopPidl, DesktopPath);
  Result := IncludeTrailingPathDelimiter(DesktopPath);

end;

{Fun��o que realiza o Download a partir de uma URL, utilizada para baixar o TSprint}
function DownloadArquivo(const Origem, Destino: String): Boolean;
const BufferSize = 1024;
var
  hSession, hURL: HInternet;
  Buffer: array[1..BufferSize] of Byte;
  BufferLen: DWORD;
  f: File;
  sAppName: string;
begin
// Result   := False;
 sAppName := ExtractFileName(Application.ExeName);
 hSession := InternetOpen(PChar(sAppName),
                INTERNET_OPEN_TYPE_PRECONFIG,
               nil, nil, 0);
 try
  hURL := InternetOpenURL(hSession,
            PChar(Origem),
            nil,0,0,0);
  try
   AssignFile(f, Destino);
   Rewrite(f,1);
   repeat
    InternetReadFile(hURL, @Buffer,
                     SizeOf(Buffer), BufferLen);
    BlockWrite(f, Buffer, BufferLen)
   until BufferLen = 0;
   CloseFile(f);
   Result:=True;
  finally
   InternetCloseHandle(hURL)
  end
 finally
  InternetCloseHandle(hSession)
 end
end;

{Criptografar a senha do TSprint}
function TForm1.criptografar(texto: string): string;
var
  retorno, letra: string;
  I, x, y: Integer;
  cripto2: array [0 .. 9] of string;
begin
  cripto2[0] := '36';
  cripto2[1] := '6D';
  cripto2[2] := '6E';
  cripto2[3] := '6F';
  cripto2[4] := '70';
  cripto2[5] := '71';
  cripto2[6] := '72';
  cripto2[7] := '73';
  cripto2[8] := '74';
  cripto2[9] := '35';
  for I := 0 to 9 do
  begin
    cripto[I] := IntToStr(I);
  end;

  for x := 1 To 5 do
  begin
    letra := Copy(texto, x, 1);
    for y := 0 to 9 do
    begin
      if letra = cripto[y] then
      begin
        retorno := retorno + cripto2[y];
      end;
    end;
    Result := retorno + '494949';
  end;

end;

{Criar arquivo .url}
procedure CriarAtalhoDaNet(const NomeDoArquivo, URL, URLIcon: string);
var
  INI: TIniFile;
begin
  INI := TIniFile.Create(UrlDirectory + NomeDoArquivo + '.url');
  with INI do
    try
      // Escrevendo a URL do Atalho
      WriteString('InternetShortcut', 'URL', URL);

      // Extraindo �cone de um Execut�vel, neste caso do EXE do Internet Explorer
      WriteString('InternetShortcut', 'IconFile', URLIcon);

      // Colocando o �ndice do �cone, porque o executavel possui mais de um �cone
      WriteString('InternetShortcut', 'IconIndex', '0');

    finally
      FreeAndNil(INI);
    end;
  FreeAndNil(INI);
end;

{Criar atalho dos arquivos}
procedure CreateShortcut(FileName, InitialDir, ShortcutName, ShortcutFolder,
  sNewIconFileName: String; Parameters: PWideChar);

var
  MyObject: IUnknown;
  MySLink: IShellLink;
  MyPFile: IPersistFile;
  directory: String;
  WFileName: WideString;
  MyReg: TRegIniFile;

  // Diret�rio ShellStartup
  shellStartup: string;
  nsize: Cardinal;
  UserName: string;

begin
  MyObject := CreateComObject(CLSID_ShellLink);
  MySLink := MyObject as IShellLink;
  MyPFile := MyObject as IPersistFile;

  // Diret�rio ShellStartup
  nsize := 25;
  SetLength(UserName, nsize);
  GetUserName(PChar(UserName), nsize);
  SetLength(UserName, nsize - 1);

  shellStartup := 'C:\Users\' + UserName + '\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup';

  with MySLink do
  begin
    SetArguments(Parameters);
    SetPath(PChar(FileName));
    SetWorkingDirectory(PChar(InitialDir));
    SetIconLocation(PWideChar(sNewIconFileName), 0);
  end;

  if ShortcutName = 'Servidor de Impress�o' then
  begin
    MyReg := TRegIniFile.Create('Software\\MicroSoft\\Windows\\CurrentVersion\\Explorer');
    directory := MyReg.ReadString('Shell Folders', 'Desktop', '');
    WFileName := shellStartup + '\' + ShortcutName + '.lnk';
    MyPFile.Save(PWChar(WFileName), False);
    MyReg.Free;

    MyReg := TRegIniFile.Create('Software\\MicroSoft\\Windows\\CurrentVersion\\Explorer');
    directory := MyReg.ReadString('Shell Folders', 'Desktop', '');
    WFileName := directory + '\' + ShortcutName + '.lnk';
    MyPFile.Save(PWChar(WFileName), False);
    MyReg.Free;
  end

  else
  begin

    MyReg := TRegIniFile.Create('Software\\MicroSoft\\Windows\\CurrentVersion\\Explorer');
    directory := MyReg.ReadString('Shell Folders', 'Desktop', '');
    WFileName := directory + '\' + ShortcutName + '.lnk';
    MyPFile.Save(PWChar(WFileName), False);
    MyReg.Free;

  end;
end;

procedure TForm1.Button1Click(Sender: TObject);
var
 user, userADM, userAdv: string;
 painelPort, remotePort: string;
 versaoTSprint, TSprint, versaoTXT, confTSprint,
 print_doc_cnf, confImpressora, defaultPrinter, destinoZIP, criptografia, destino: string;
 jsonBody, API_URL, Token, MacAddress, IPv4, HostName, Data_Hora, adobeEXE, installDirectory, adobe :string;
 i: integer;
 Date: TDateTime;
 Computer: PChar;
 CSize: DWORD;

begin
  user := txtUser.Text;
  userADM := (Copy(user, 1, 5));
  userAdv := (Copy(user, 6, (Length(Trim(user))) - 5));

  painelPort := txtPainel.Text;
  remotePort := txtRemota.Text;

  URLPainel := 'http://' + userADM + '-web.unilab.app.br:' + PainelPort + '/?'+ userADM;
  URLacesso := 'http://' + userADM + '.unilab.app.br:' + RemotePort + '/';
  URLArquivos := 'http://' + userADM + '-web.unilab.app.br:3080/arquivos';

  if (user = '') or (RemotePort = '') then
    begin
      ShowMessage('� necess�rio preencher o usu�rio e a porta remota para a instala��o');
      Abort;
    end
  else
    if (chkTSprint.Checked = True) then
    begin
      createDir(directory + 'TSprint');
      versaoTXT := 'http://uniware.com.br/updates/tsprint/versao.txt';
      destino := tsprintDirectory + 'versao.txt';

      DownloadArquivo(versaoTXT, destino);

      AssignFile(arq, tsprintDirectory + 'versao.txt');
      Reset(arq);
      Readln(arq, versaoTSprint);
      CloseFile(arq);
      DeleteFile(tsprintDirectory + 'versao.txt');

      TSprint := 'http://uniware.com.br/updates/tsprint/tsprint_v' + versaoTSprint + '.zip';
      destinoZIP := tsprintDirectory + 'TSprint.zip';

      DownloadArquivo(TSprint, destinoZIP);

      zipFile := TZipFile.Create;
      zipFile.Open(tsprintDirectory + 'TSprint.zip', zmRead);
      zipFile.ExtractAll(tsprintDirectory);
      zipFile.Close;

      criptografia := criptografar(user);
      createDir(tsprintDirectory + 'conf');
      confTsprint := '{"servidor":1,"maxthreads":20,"url":"http:\/\/' + userADM
      + '-web.unilab.app.br\/tsprint","codigo_adm":"' + userADM +
      '","rdp_user":"' + user + '","porta":' + EqTsPort +
      ',"intervalo":2,"token":"' + criptografia +
      '","MainApp":"TSPrint","FingerPrint":0}';
      AssignFile(F, tsprintDirectory + 'conf\geral_cnf.data');
      Rewrite(F);
      Writeln(F, confTsprint);
      CloseFile(F);

      defaultPrinter := getDefaultPrinterName;
      for i := length(Trim(defaultPrinter)) DownTo 1 do
        begin
          if Copy(defaultPrinter, i, 1) = '\' then
          Insert('\', defaultPrinter, i);
        end;

      confImpressora := '[{"ID":1,"FOLDER":"root","PRINTERNAME":"' +
      defaultPrinter +'","DOWNLOAD":"Sim","PRINT":"Sim"},{"ID":2,"FOLDER":"pdf","PRINTERNAME":"'
      + DefaultPrinter + '","DOWNLOAD":"Sim","PRINT":"N\u00E3o"}]';
      print_doc_cnf := tsprintDirectory + 'conf\print_doc_cnf.data';

      if not FileExists(print_doc_cnf) then
        begin
          AssignFile(F, print_doc_cnf);
          Rewrite(F);
          Writeln(F, confImpressora);
          CloseFile(F);
        end;

      CreateShortcut(tsprintDirectory + 'TSprint.Exe', tsprintDirectory,
      'Servidor de Impress�o', tsprintDirectory + 'TSprint.Exe', '', 'a');
      DeleteFile(tsprintDirectory + 'TSprint.zip');
      DeleteFile(directory + 'TSprint.zip');
    end;

    createDir(UrlDirectory);

    {Criar atalho da �rea de arquivos}
    if (chkArquivos.Checked = True) then
      begin
        CriarAtalhoDaNet('Area de Arquivos', URLArquivos, ArquivosIcon);
        setUrl(UrlDirectory + 'Area de Arquivos.url', URLArquivos);
        CreateShortcut(UrlDirectory + 'Area de Arquivos.url', UrlDirectory,
        '�rea de Arquivos', UrlDirectory + 'Area de Arquivos.url',
        ArquivosIcon, '');
      end;

      {Criar atalho do painel de senha}
    if (chkPainel.Checked = True) and (PainelPort <> '') then
    begin
      AssignFile(arq, directory + '\' + 'Link.txt');
      Rewrite(arq);
      Writeln(arq, 'http://' + userADM + '.unilab.app.br:' + RemotePort + '/');
      Writeln(arq, 'http://' + userADM + '-web.unilab.app.br/tsprint');
      Writeln(arq, 'http://' + userADM + '-web.unilab.app.br:' + EqTsPort + '/'
        + userADM + '-uniequip/');
      Writeln(arq, 'http://' + userADM + '-web.unilab.app.br:3080/arquivos');
      Writeln(arq, 'http://' + userADM + '-web.unilab.app.br:' + PainelPort +
        '/?' + userADM);
      CloseFile(arq);
      CriarAtalhoDaNet('Painel de Senha', URLPainel, PainelIcon);
      setUrl(UrlDirectory + 'Painel de Senha.url', URLPainel);
      CreateShortcut(UrlDirectory + 'Painel de Senha.url', UrlDirectory,
      'Painel de Senha', UrlDirectory + 'Painel de Senha.url', PainelIcon, '');
    end
    else if (chkPainel.Checked = True) and (PainelPort = '') then
    begin
      ShowMessage('Informe a porta do painel para o acesso');
      Abort;
    end
    else if PainelPort <> '' then
    begin
      AssignFile(arq, directory + '\' + 'Link.txt');
      Rewrite(arq);
      Writeln(arq, 'http://' + userADM + '.unilab.app.br:' + RemotePort + '/');
      Writeln(arq, 'http://' + userADM + '-web.unilab.app.br/tsprint');
      Writeln(arq, 'http://' + userADM + '-web.unilab.app.br:' + EqTsPort + '/'
        + userADM + '-uniequip/');
      Writeln(arq, 'http://' + userADM + '-web.unilab.app.br:3080/arquivos');
      Writeln(arq, 'http://' + userADM + '-web.unilab.app.br:' + PainelPort +
        '/?' + userADM);
      CloseFile(arq);
    end
    else
    begin
      AssignFile(arq, directory + '\' + 'Link.txt');
      Rewrite(arq);
      Writeln(arq, 'http://' + userADM + '.unilab.app.br:' + RemotePort + '/');
      Writeln(arq, 'http://' + userADM + '-web.unilab.app.br/tsprint');
      Writeln(arq, 'http://' + userADM + '-web.unilab.app.br:' + EqTsPort + '/'
        + userADM + '-uniequip/');
      Writeln(arq, 'http://' + userADM + '-web.unilab.app.br:3080/arquivos');
      CloseFile(arq);
    end;

    if (chkAdobe.Checked = True) then
    begin
      createDir(directory + 'Install');
      installDirectory := directory + 'Install\';

      adobeEXE := 'http://3.87.227.77/instalador_api/install/adobe/adobe.exe';
      adobe := installDirectory + 'adobe.exe';

      DownloadArquivo(adobeEXE, adobe);
    end;

    AssignFile(arq, directory + '\' + 'Senha Unilab.txt');
    Rewrite(arq);
    Writeln(arq, '@' + user);
    Writeln(arq, '');
    Writeln(arq, 'http://' + userADM + '-web.unilab.app.br:3080/arquivos');
    Writeln(arq, 'Login: ' + userADM);
    Writeln(arq, 'Senha: ');
    CloseFile(arq);

    CriarAtalhoDaNet('Unilab', URLacesso, UnilabIcon);
    setUrl(UrlDirectory + 'Unilab.url', URLacesso);

    CreateShortcut(UrlDirectory + 'Unilab.url', UrlDirectory, 'Unilab ' + userAdv,
    UrlDirectory + 'Unilab.url', UnilabIcon, '');
    CreateShortcut(directory + 'Senha Unilab.txt', directory, 'Senha Unilab',
    directory + 'Senha Unilab.txt', '', '');
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil);

    Computer:=#0;
    CSize:=MAX_COMPUTERNAME_LENGTH + 1;
    try
    GetMem(Computer,CSize);
    if GetComputerName(Computer,CSize ) then
        HostName := Computer;
    finally
    FreeMem(Computer);
    end;
    
    MacAddress := GetMacAddress;
    IPv4 := GetIp;
    Date := Now();
    Data_Hora := DateTimeToStr(Date);
    Data_Hora := FormatDateTime('yyyy-mm-dd HH:mm:ss', Date);

    jsonBody := '{"ADM": "' +
    userADM + '","USER": "' + user + '","IPV4": "' +
    IPv4 + '","MACADDRESS": "' + MacAddress + '","HOSTNAME": "' +
    HostName + '","DTCADASTRO": "' + Data_Hora + '"}';
    RESTRequest1.Params[1].Value := jsonBody;
    RESTRequest1.Execute;
    ShowMessage('Instalado com Sucesso');

    Application.Terminate;

    AssignFile(arq, directory + 'selfdelete.bat');
    Rewrite(arq);
    Writeln(arq, '@echo off');
    Writeln(arq, '@ping localhost -n 1>NUL');
    Writeln(arq, 'taskkill /F /IM ' + ExtractFileName(Application.ExeName));
    Writeln(arq, 'del /s /q "' + Application.ExeName + '"');
    Writeln(arq, 'del /s /q "%~f0"');
    CloseFile(arq);
    WinExec(PAnsiChar(AnsiString(directory + 'selfdelete.bat')), 0);
end;

procedure TForm1.chkAdobeKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key.ToString = '13' then
  begin
    if chkAdobe.Checked = True then
    begin
      chkAdobe.Checked := False;
    end
    else
      chkAdobe.Checked := True;
  end;
end;

procedure TForm1.chkArquivosKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key.ToString = '13' then
  begin
    if chkArquivos.Checked = True then
    begin
      chkArquivos.Checked := False;
    end
    else
      chkArquivos.Checked := True;
  end;
end;

procedure TForm1.chkPainelKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
   if Key.ToString = '13' then
  begin
    if chkPainel.Checked = True then
    begin
      chkPainel.Checked := False;
    end
    else
      chkPainel.Checked := True;
  end;
end;

procedure TForm1.chkTSprintKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key.ToString = '13' then
  begin
    if chkTSprint.Checked = True then
    begin
      chkTSprint.Checked := False;
    end
    else
      chkTSprint.Checked := True;
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin

  directory := ExtractFilePath(Application.ExeName);
  iconDirectory := directory + 'Icons\';
  tsprintDirectory := directory + 'TSprint\';
  UrlDirectory := directory + 'Atalhos de internet\';

  painelIcon := iconDirectory + 'PainelDeSenhas.ico';
  arquivosIcon := iconDirectory + 'AreaDeArquivos.ico';
  unilabIcon := iconDirectory + 'Unilab.ico';

  eqTsPort := '3080';

  if FileExists(directory + 'Unilab.url') then
    begin
      DeleteFile(directory + 'Unilab.url');
    end;

    if FileExists(directory + 'Painel de Senha.url') then
    begin
      DeleteFile(directory + 'Painel de Senha.url');
    end;

    if FileExists(directory + 'Area de Arquivos.url') then
    begin
      DeleteFile(directory + 'Area de Arquivos.url');
    end;
end;

end.
