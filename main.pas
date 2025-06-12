unit Main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ActnList, FileInfo, Sockets
  {$IFDEF UNIX}, BaseUnix, syncobjs, StrUtils{$ENDIF}
  {$IFDEF MSWINDOWS}, Windows, Winsock2{$ENDIF}
  ;

const
  PORT = 40001;
  BUFFER_SIZE = High(Word);

var
  PacketSize: UInt64 = 0;
  CS: TCriticalSection;

type
  { TUDPServerThread }

  TUDPServerThread = class(TThread)
  private
    Sock: LongInt;
    Addr: TInetSockAddr;
    FOnPacket: TThreadMethod;
    FLastMessage: string;
    FLastMessageSize: Integer;
    procedure DoNotify;
    procedure SetSocketNonBlocking;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    property OnPacket: TThreadMethod read FOnPacket write FOnPacket;
    property LastMessage: string read FLastMessage;
    property LastMessageSize: Integer read FLastMessageSize;
  end;

  { TfMain }

  TfMain = class(TForm)
    acMain: TActionList;
    acStartStopServer: TAction;
    btnStartStopServer: TButton;
    gbLog: TGroupBox;
    gbServer: TGroupBox;
    mLog: TMemo;
    pBottom: TPanel;
    pClient: TPanel;
    pTop: TPanel;
    procedure acStartStopServerExecute(Sender: TObject);
    procedure acStartStopServerUpdate(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FServerStarted: Boolean;
    UDPThread: TUDPServerThread;
    procedure LogAddLine(const AData: String);
    procedure SetFonts;
  public

  end;

var
  fMain: TfMain;

implementation

{$R *.lfm}

{ TUDPServerThread }

procedure TUDPServerThread.DoNotify;
begin
  if Assigned(FOnPacket) then
    FOnPacket;
end;

procedure TUDPServerThread.SetSocketNonBlocking;
{$IFDEF UNIX}
var
  flags: LongInt;
begin
  flags := fpFcntl(Sock, F_GETFL, 0);
  fpFcntl(Sock, F_SETFL, flags or O_NONBLOCK);
end;
{$ENDIF}

{$IFDEF MSWINDOWS}
var
  NonBlocking: u_long;
begin
  NonBlocking := 1;
  ioctlsocket(Sock, LongInt(FIONBIO), @NonBlocking);
end;
{$ENDIF}

procedure TUDPServerThread.Execute;
var
  FDSet: TFDSet;
  TV: TTimeVal;
  Buffer: array[0..BUFFER_SIZE-1] of Char;
  FromAddr: TInetSockAddr;
  AddrLen: TSockLen;
  Received: Integer;
  MsgPtr: PString;
begin
  while not Terminated do begin
    {$IFDEF UNIX}
    fpFD_ZERO(FDSet);
    fpFD_SET(Sock, FDSet);
    {$ENDIF}
    {$IFDEF MSWINDOWS}
    FD_ZERO(FDSet);
    FD_SET(Sock, FDSet);
    {$ENDIF}
    TV.tv_sec := 0;
    TV.tv_usec := 100000;
    {$IFDEF UNIX}
    if fpSelect(Sock + 1, @FDSet, nil, nil, @TV) > 0 then begin
    {$ENDIF}
    {$IFDEF MSWINDOWS}
    if Select(Sock + 1, @FDSet, nil, nil, @TV) > 0 then begin
    {$ENDIF}
      AddrLen := SizeOf(FromAddr);
      Received := fpRecvFrom(Sock, @Buffer, BUFFER_SIZE, 0, @FromAddr, @AddrLen);
      if Received > 0 then begin
        FLastMessageSize := Received;
        Inc(PacketSize, Received);
        //LogBuffer.Add(TObject(CreateFmt('%s - %s', [DateTimeToStr(Now), FLastMessage])));
        //LogBuffer.Add(TObject(FLastMessage));
        SetString(FLastMessage, Buffer, Received);
        New(MsgPtr);
        MsgPtr^ := FLastMessage;

        Synchronize(@DoNotify);
      end;
    end;
  end;
end;

constructor TUDPServerThread.Create;
begin
  inherited Create(True);
  FreeOnTerminate := True;
  Sock := fpSocket(AF_INET, SOCK_DGRAM, 0);
  if Sock = -1 then
    raise Exception.Create('Неуспешно създаване на сокет');
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := htons(PORT);
  Addr.sin_addr.s_addr := htonl(INADDR_ANY);
  if fpBind(Sock, @Addr, SizeOf(Addr)) = -1 then
    raise Exception.Create('Неуспешен bind на сокет');
  SetSocketNonBlocking;
end;

destructor TUDPServerThread.Destroy;
begin
  if Sock <> -1 then begin
    {$IFDEF UNIX}
    fpClose(Sock);
    {$ENDIF}
    {$IFDEF MSWINDOWS}
    closesocket(Sock);
    WSACleanup; // добра практика, особено ако си инициализирал Winsock
    {$ENDIF}
  end;
  inherited Destroy;
end;

{ TfMain }

procedure TfMain.FormCreate(Sender: TObject);
var
  FileVerInfo: TFileVersionInfo;
begin
  {$ifopt D+}
  Self.Caption := ApplicationName + ' --== ' + 'DEBUG' + ' ==--' ;
  {$else}
  Self.Caption := ApplicationName;
  {$endif}
  FileVerInfo:=TFileVersionInfo.Create(nil);
  try
    FileVerInfo.ReadFileInfo;
    //writeln('Company: ',FileVerInfo.VersionStrings.Values['CompanyName']);
    //writeln('File description: ',FileVerInfo.VersionStrings.Values['FileDescription']);
    //writeln('File version: ',FileVerInfo.VersionStrings.Values['FileVersion']);
    //writeln('Internal name: ',FileVerInfo.VersionStrings.Values['InternalName']);
    //writeln('Legal copyright: ',FileVerInfo.VersionStrings.Values['LegalCopyright']);
    //writeln('Original filename: ',FileVerInfo.VersionStrings.Values['OriginalFilename']);
    //writeln('Product name: ',FileVerInfo.VersionStrings.Values['ProductName']);
    //writeln('Product version: ',FileVerInfo.VersionStrings.Values['ProductVersion']);
    Self.Caption := Self.Caption + ' - Version ' + FileVerInfo.VersionStrings.Values['FileVersion'];
  finally
    FileVerInfo.Free;
  end;

  FServerStarted := False;

  SetFonts;

  {$IFDEF UNIX}
  CS := TCriticalSection.Create;
  {$ENDIF}
  {$IFDEF WINDOWS}
  InitializeCriticalSection(CS);
  {$ENDIF}
end;

procedure TfMain.FormDestroy(Sender: TObject);
begin
  if Assigned(UDPThread) then begin
    UDPThread.Terminate;
    UDPThread.WaitFor;
    UDPThread := nil;
    UDPThread.Free;
  end;

  {$IFDEF UNIX}
  CS.Free;
  {$ENDIF}
  {$IFDEF WINDOWS}
  DeleteCriticalSection(CS);
  {$ENDIF}
end;

procedure TfMain.LogAddLine(const AData: String);
var
  TimeStamp: String;
begin
  TimeStamp := FormatDateTime('[hh:mm:ss.zzz] ', SysUtils.Now);
  mLog.Lines.Add(TimeStamp + AData);
end;

procedure TfMain.SetFonts;
begin
  {$IFDEF UNIX}
  mLog.Font.Name := 'DejaVu Sans';
  {$ENDIF}
  {$IFDEF MSWINDOWS}
  mLog.Font.Name := 'Consolas';
  {$ENDIF}
end;

procedure TfMain.acStartStopServerExecute(Sender: TObject);
begin
  FServerStarted := not FServerStarted;
  if FServerStarted then begin
    UDPThread := TUDPServerThread.Create;
    UDPThread.Start;
    LogAddLine('Сървър стартиран.');
  end else begin
    if Assigned(UDPThread) then begin
      UDPThread.Terminate;
      UDPThread.WaitFor;
      UDPThread := nil;
      LogAddLine('Сървър спрян.');
    end;
  end;
end;

procedure TfMain.acStartStopServerUpdate(Sender: TObject);
begin
  (Sender as TAction).Caption := IfThen(FServerStarted, 'Stop', 'Start');
end;

end.

