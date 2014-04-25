{===========================================================================
 ���� ������ �������� ������� ��� ��������� � �������� LPTWDMIO.SYS
 �����: ������ �.�., http://progrex.narod.ru, 2003�.
 ������: freeware.
 ===========================================================================
 Bugtrack:

 25.08.2002 -- ��������� ����������� ��� �������� ��������� ��� � ��������� LPT,
 ��������� ������ ��� ������������ �������� ��� Windows NT/2000/XP

 27.08.2002 -- ��������� ��������� ��������� ������ � ������ EPP � ���������
 ������� �����-������ �� ���������� Windows 9X.

 01.02.2003 -- ���������� ������ � ���������� Writepk � Readpk (���� �� ����������)

 14.04.2002 -- ���������� ������ � ������� IsPortBidirectional

 ===========================================================================}
unit LPTIO;

interface
uses
  VC,
  Windows;

const
   { ��� ������u������ ����� }
  DRV_LINK_NAME                         : string = '\\.\LptAccessAgent';

   { ���� ��������� �������� }
  IOCTL_READ_PORTS                      : Cardinal = $00220050; // ������ ��������� LPT
  IOCTL_WRITE_PORTS                     : Cardinal = $00220060; // ������ � �������� LPT

   { ������ ������ LPT }
  LPT1                                  : Byte = $10; // ���� $3BC
  LPT2                                  : Byte = $20; //      $378
  LPT3                                  : Byte = $30; //      $278

   { �������� ��������� ����� }
  LPT_DATA_REG                          : Byte = 0; // ������� ������
  LPT_STATE_REG                         : Byte = 1; // ������� ���������
  LPT_CONTROL_REG                       : Byte = 2; // ������� ����������
  LPT_EPP_ADDRESS                       : Byte = 3; // ������� ������ EPP
  LPT_EPP_DATA                          : Byte = 4; // ������� ������ EPP

   { ������� �������� ��������� / ������ 25 pin / ������ Centronic }
   { ������� ������� �������� ���������� }
  STROBE                                : Byte = $01; { �����,          1 /1             }
  AUTOFEED                              : Byte = $02; { ������������,   14/14            }
  Init                                  : Byte = $04; { �������������,  16/31            }
  SELECTIN                              : Byte = $08; { ����� ��������, 17/36            }
  IRQE                                  : Byte = $10; { ����������,     ------           }
  Direction                             : Byte = $20; { ����������� ��, ------           }

   { ������� ������� �������� ��������� }
  IRQS                                  : Byte = $04; { ���� ����������,------           }
  ERROR                                 : Byte = $08; { ������� ������, 15/32            }
  SELECT                                : Byte = $10; { ������� ������, 13/13            }
  PAPEREND                              : Byte = $20; { ����� ������,   12/12            }
  ACK                                   : Byte = $40; { ���������� � ����� ������, 10/10}
  BUSY                                  : Byte = $80; { ���������,      11/11            }

   { ��������� ��� ������ � ���������� �������� }
  SC_MANAGER_ALL_ACCESS                 : Cardinal = $000F003F;
  SERVICE_ALL_ACCESS                    : Cardinal = $000F01FF;

  SWC_NAME                              : string = 'lptwdmio'; { ��������� ��� ������� }
  SWC_DISPLAY_NAME                      : string = 'LPT port direct access service'; { �������� �������, ����� �������� ������������ :) }

type
   { ��������� �����-������ }
  ADRDATASTRUCT = record
    Adr: Byte; { ����� == <����� �����> or <�������� ��������>      }
    data: Byte; { ������ ��� ������ ��� ����� ��� ������������ ����� }
  end;
  PADRDATASTRUCT = ^ADRDATASTRUCT;

   { ���� ��� ��������� � ��������� �������� NT }
  SC_HANDLE = Cardinal; // ��� ������ ��� ��������� � ��������� ��������

   { ����������� ��� ��� ��������� � �-� OpenSCManager }
  POpenSCManager = function(lpMachineName, lpDatabaseName: PChar;
    dwDesiredAccess: DWORD): SC_HANDLE; stdcall;

   { ����������� ��� ��� ��������� � �-� CloseServiceHandle }
  PCloseServiceHandle = function(hSCObject: SC_HANDLE): BOOL; stdcall;

   { ����������� ��� ��� ��������� � �-� CreateService }
  PCreateService = function(hSCManager: SC_HANDLE;
    lpServiceName, lpDisplayName: PChar;
    dwDesiredAccess, dwServiceType, dwStartType, dwErrorControl: DWORD;
    lpBinaryPathName, lpLoadOrderGroup: PChar;
    lpdwTagId: LPDWORD;
    lpDependencies, lpServiceStartName, lpPassword: PChar): SC_HANDLE; stdcall;

   { ����������� ��� ��� ��������� � �-� StartService }
  PStartService = function(hService: SC_HANDLE; dwNumServiceArgs: DWORD;
    var lpServiceArgVectors: PChar): BOOL; stdcall;

   { ����������� ��� ��� ��������� � �-� OpenService }
  POpenService = function(hSCManager: SC_HANDLE; lpServiceName: PChar;
    dwDesiredAccess: DWORD): SC_HANDLE; stdcall;

   { ����������� ��� ��� ��������� � �-� DeleteService }
  PDeleteService = function(hService: SC_HANDLE): BOOL; stdcall;

   { ����� ��� ��������� � �������� LPTWDMIO.sys }
  TLptPortConnection = class
  private
    hdrv: Cardinal; // ����� ������������ ��������
    winnt: boolean; // ������� ��������� NT

      { ������, ����������� � ������ ��������� �������� �� ���������� NT }
    UnregisterService: boolean; // ����, ������������ ������������� �������� ������� lptwdmio �� �������� ���������� � Win NT
    hdll: Cardinal; // ����� ���������� advapi32.dll
    SysBinaryName: AnsiString; // ��� ����� ��������
    ServiceArgVectors: PChar; // ��������������� ���������� ��� ������ StartService
    OpenSCManager_: POpenSCManager; // ��������� �� �-� OpenSCManager Win32 API
    CloseServiceHandle_: PCloseServiceHandle; // -//- CloseServiceHandle
    CreateService_: PCreateService; // -//- CreateService
    StartService_: PStartService; // -//- StartService
    OpenService_: POpenService; // -//- OpenService
    DeleteService_: PDeleteService; // -//- DeleteService

      // ����� ������� ������
    PortPresent: array[0..2] of boolean;

      { ��������� ������ ������ � ���� �� ��� Windows 9x }
    procedure Writepk(Addr: Word; data: Byte);

      { ��������� ����� ������ �� ����� �� ��� Windows 9x }
    function Readpk(Addr: Word): Byte;

  public
    constructor Create; // �����������
    destructor Destroy; override; // ����������

    function Ready: boolean; // ���������� ������� ����������/������������

      // �-� ���������� true, ���� �������� �� ��������� NT
    function IsNtPlatform: boolean;

      // �-� ������������ ������� �����. ��������� true, ���� ���� ������������.
    function IsPortPresent(LptNumber: Byte): boolean;

      // �-� ������������ ����� �� �����������������
    function IsPortBidirectional(LptNumber: Byte): boolean;

      // ������� ��� ������ ��������� LPT. ���������� true, ���� ������ ������ �������.
      // PairArray -- ������ �������� ADRDATASTRUCT, � ������� ����� ����������� ������ �� ������.
      //  ����� Adr ������ ���� ���������������� ���������� (<����� ����� LPT>or<�������� ��������>),
      //  ��������: PairArray[i].Adr := LPT1 or LPT_STATE_REG;
      //
      // PairCount -- ���������� �������� � ������� PairArray.
    function ReadPorts(PairArray: PADRDATASTRUCT; PairCount: Cardinal): boolean;

      // ������� ��� ������ ������ � �������� LPT. ���������� true, ���� ������ ������ �������.
      // PairArray -- ��. ����, + ����� Data �������� ADRDATASTRUCT ������ ��������� ������ ��� ������
      //  � ��������������� �������� �����.
      // PairCount -- ��. ����.
    function WritePorts(PairArray: PADRDATASTRUCT; PairCount: Cardinal): boolean;

      // ������� ��� ������ ������ �������� ���������� �����
    function ReadPort(LptNumber: Byte; RegOffset: Byte): Byte;

      // ��������� ��� ������ �������� � ������� �����
    procedure WritePort(LptNumber: Byte; RegOffset: Byte; Value: Byte);

      // ��������� ��� ���������� ��������
      // Time -- �������� �������� � ���. ���������� �������� - �� 0 �� 50 ���.
    procedure Delay(Time: Cardinal);

  end; {class}
  PLptPortConnection = ^TLptPortConnection;

implementation
uses Unit1;

// �����������

constructor TLptPortConnection.Create;
var
  osv                                   : OSVERSIONINFO; // ��������� ��� ��������� ������ ���������
  hSCMahager                            : SC_HANDLE; // ����� ��������� ��������
  hServiceHandle                        : SC_HANDLE; // ����� ������� lptwdmio
begin
  inherited Create;
   // ��������� �������������
  hdrv := INVALID_HANDLE_VALUE;
  UnregisterService := False;
  hdll := 0;

   // ������ ������ ��
  osv.dwOSVersionInfoSize := SizeOf(osv);
  GetVersionex(osv);
  winnt := (osv.dwPlatformId = VER_PLATFORM_WIN32_NT); // NT-� ��� ���?

   // ������� ��������� � ���������
  SetLastError(NO_ERROR);

  if winnt then //wli
    hdrv := CreateFile(PChar(DRV_LINK_NAME),
      GENERIC_READ or GENERIC_WRITE,
      FILE_SHARE_READ or FILE_SHARE_WRITE,
      nil,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      0);

  if hdrv = INVALID_HANDLE_VALUE then
    if winnt then // �� ������� ��������� � ���������. �� �� ��� ���������� �������.
    begin
            // Windows NT -- ������� ��������� ������� ����� �������� ���������� ���������
      hdll := LoadLibrary(PChar('ADVAPI32.DLL')); // ������� ��������� �� �-� ��������� ��������.
      if hdll <> 0 then
      begin
                  // Re: ����� ��������� �������� � �� NT, � �� 9x, ���������� ������������ �������� AdvApi32.dll
                   // ������� ��������� �� �-� � AdvApi32.dll
        OpenSCManager_ := POpenSCManager(GetProcAddress(hdll, PChar('OpenSCManagerA')));
        CloseServiceHandle_ := PCloseServiceHandle(GetProcAddress(hdll, PChar('CloseServiceHandle')));
        CreateService_ := PCreateService(GetProcAddress(hdll, PChar('CreateServiceA')));
        StartService_ := PStartService(GetProcAddress(hdll, PChar('StartServiceA')));
        OpenService_ := POpenService(GetProcAddress(hdll, PChar('OpenServiceA')));
        DeleteService_ := PDeleteService(GetProcAddress(hdll, PChar('DeleteService')));

                  // �������� � ���������� ��������
        hSCMahager := OpenSCManager_(nil, nil, SC_MANAGER_ALL_ACCESS);
        if 0 <> hSCMahager then
        begin // ��������� �������
          SysBinaryName := TR4W_PATH_NAME + 'LPTWDMIO.SYS'; // ��� ��������� sys
                        // ������� �������� �������
          hServiceHandle := CreateService_(hSCMahager,
            PChar(SWC_NAME), // ��� �������
            PChar(SWC_DISPLAY_NAME), // ������������ ���
            SERVICE_ALL_ACCESS, // ����� �������
            1, // SERVICE_KERNEL_DRIVER
            3, // SERVICE_DEMAND_START
            1, // SERVICE_ERROR_NORMAL
            PChar(SysBinaryName),
            nil,
            nil,
            nil,
            nil,
            nil);
          if 0 = hServiceHandle then
          begin // ��������, ������ ��� ������ �����
            hServiceHandle := OpenService_(hSCMahager, PChar(SWC_NAME), SERVICE_ALL_ACCESS); // ������� ���
          end;
          if 0 <> hServiceHandle then
          begin // ��, ��������� ������
            ServiceArgVectors := nil;
            StartService_(hServiceHandle, 0, ServiceArgVectors); // ��� ������� ������ �����������...
            UnregisterService := True; // ��� ���������� ������� �� ������ �������� ������ ��� ��������
            CloseServiceHandle_(hServiceHandle); // ����������� �����
          end;

          CloseServiceHandle_(hSCMahager); // ����������� �����
        end;
      end;

            // �������� �������� ��������� � ���������
      SetLastError(NO_ERROR);
      hdrv := CreateFile(PChar(DRV_LINK_NAME),
        GENERIC_READ or GENERIC_WRITE,
        FILE_SHARE_READ or FILE_SHARE_WRITE,
        nil,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        0);
    end;

  if Ready() then
  begin
         // ��������� �����, �������������� � �������
    PortPresent[0] := IsPortPresent(LPT1);
    PortPresent[1] := IsPortPresent(LPT2);
    PortPresent[2] := IsPortPresent(LPT3);
  end;
end;

// ����������

destructor TLptPortConnection.Destroy;
var
  hSCMahager                            : SC_HANDLE;
  hServiceHandle                        : SC_HANDLE;
begin
  if hdrv <> INVALID_HANDLE_VALUE then CloseHandle(hdrv);
  if UnregisterService and winnt then
  begin // ����������������� ������
    if hdll <> 0 then
    begin
      hSCMahager := OpenSCManager_(nil, nil, SC_MANAGER_ALL_ACCESS); // ��������� � ���������� ��������
      if 0 <> hSCMahager then
      begin
        hServiceHandle := OpenService_(hSCMahager, PChar(SWC_NAME), SERVICE_ALL_ACCESS); // �������� ����� ������� lptwdmio
        if hServiceHandle <> 0 then
        begin
          DeleteService_(hServiceHandle); // �������� ������ ��� ���������� ��������. ������� ��������� � ������ �� ��������� ������������.
          CloseServiceHandle_(hServiceHandle); // ����������� �����
        end;
        CloseServiceHandle_(hSCMahager); // ����������� ����� ��������� ��������
      end;
      FreeLibrary(hdll); // ����������� ����� ���������� AdvApi32.dll
    end;
  end;
  inherited Destroy;
end;

// ���������� ������� ����������/������������

function TLptPortConnection.Ready: boolean;
begin
  Ready := (hdrv <> INVALID_HANDLE_VALUE) or not winnt; // ���� �������� �������, ���� Windows 9x
end;

// ������� ��� ������ ��������� LPT. ���������� true, ���� ������ ������ �������.

function TLptPortConnection.ReadPorts(PairArray: PADRDATASTRUCT; PairCount: Cardinal): boolean;
var
  cb                                    : Cardinal;
  Pair                                  : PADRDATASTRUCT;
  ct                                    : Cardinal;
  Adr                                   : Word;
begin
  if Ready() then
  begin
    if hdrv <> INVALID_HANDLE_VALUE then
    begin // ������ ����� �������
      cb := 0;
      SetLastError(NO_ERROR);
      DeviceIoControl(hdrv, IOCTL_READ_PORTS, PairArray, PairCount * 2, PairArray, PairCount * 2, cb, nil);
      ReadPorts := (NO_ERROR = getlasterror());
    end
    else
    begin // ������ �������� ����� ��������� � ������ (Windows 9x)
      Pair := PairArray;
      for ct := 0 to PairCount - 1 do
      begin // ���� �� ���������� ����������
        Adr := $278; // LPT3 �� ���������
        case (Pair.Adr shr 4) of
          1: Adr := $3BC; // LPT1
          2: Adr := $378; // LPT2
        end; // case
        Adr := Adr + (7 and Pair.Adr); // ���� + ��������
        Pair.data := Readpk(Adr); // ������ ������
        inc(Pair);
      end; // for
      ReadPorts := True;
    end;
  end else
  begin
    ReadPorts := False;
  end;
end;

// ������� ��� ������ ������ � �������� LPT. ���������� true, ���� ������ ������ �������.

function TLptPortConnection.WritePorts(PairArray: PADRDATASTRUCT; PairCount: Cardinal): boolean;
var
  cb                                    : Cardinal;
  Pair                                  : PADRDATASTRUCT;
  ct                                    : Cardinal;
  Adr                                   : Word;
begin
  if Ready() then
  begin
    if hdrv <> INVALID_HANDLE_VALUE then
    begin // ������ ����� �������
      cb := 0;
      SetLastError(NO_ERROR);
      DeviceIoControl(hdrv, IOCTL_WRITE_PORTS, PairArray, PairCount * 2, PairArray, PairCount * 2, cb, nil);
      WritePorts := (NO_ERROR = getlasterror());
    end else
    begin // ������ ����� ������ ��������� � ������ (Windows 9x)
      Pair := PairArray;
      for ct := 0 to PairCount - 1 do
      begin // ���� �� ���������� ����������
        Adr := $278; // LPT3 �� ���������
        case (Pair.Adr shr 4) of
          1: Adr := $3BC; // LPT1
          2: Adr := $378; // LPT2
        end; // case
        Adr := Adr + (7 and Pair.Adr); // ���� + ��������
        Writepk(Adr, Pair.data); // ������� ������
        inc(Pair);
      end; // for
      WritePorts := True;
    end;
  end else
  begin
    WritePorts := False;
  end;
end;

// ������� ��� ������ ������ �������� ���������� �����

function TLptPortConnection.ReadPort(LptNumber: Byte; RegOffset: Byte): Byte;
var
  Pair                                  : ADRDATASTRUCT;
begin
  Pair.Adr := LptNumber or RegOffset;
  Pair.data := 0;
  ReadPorts(@Pair, 1);
  ReadPort := Pair.data;
end;

// ��������� ��� ������ �������� � ������� �����

procedure TLptPortConnection.WritePort(LptNumber: Byte; RegOffset: Byte; Value: Byte);
var
  Pair                                  : ADRDATASTRUCT;
begin
  Pair.Adr := LptNumber or RegOffset;
  Pair.data := Value;
  WritePorts(@Pair, 1);
end;

function TLptPortConnection.IsNtPlatform: boolean;
begin
  IsNtPlatform := winnt;
end;

// �-� ������������ ������� �����. ��������� true, ���� ���� ������������.

function TLptPortConnection.IsPortPresent(LptNumber: Byte): boolean;
var
  data                                  : Byte;
  present                               : boolean;
begin
  present := True;
  data := ReadPort(LptNumber, LPT_DATA_REG); // ��������� ������� �������� �������� ������
  WritePort(LptNumber, LPT_DATA_REG, $00); // ����� 0
  present := present and ($00 = ReadPort(LptNumber, LPT_DATA_REG)); // �������� -- ��� ��������, �� � ���������?
  WritePort(LptNumber, LPT_DATA_REG, $55); // ����� $55
  present := present and ($55 = ReadPort(LptNumber, LPT_DATA_REG));
  WritePort(LptNumber, LPT_DATA_REG, $AA); // ����� $AA
  present := present and ($AA = ReadPort(LptNumber, LPT_DATA_REG));
  WritePort(LptNumber, LPT_DATA_REG, data); // ��������������� ������� �������� �������� ������
   // �������� ������� ��������� ���������� � ������, ���� ���� �� ��������� (� ������ ����������������� �����)
  if not present then
  begin
    data := ReadPort(LptNumber, LPT_CONTROL_REG); // ������ ������� ����������
    present := (data <> $00) and (data <> $FF); // �� ������ ��������? -- ���� ������������
    if not present then
    begin
      data := ReadPort(LptNumber, LPT_STATE_REG); // ������ ������� ���������
      present := (data <> $00) and (data <> $FF);
    end;
  end;
  IsPortPresent := present;
end;

// �-� ������������ ����� �� �����������������

function TLptPortConnection.IsPortBidirectional(LptNumber: Byte): boolean;
var
  data                                  : Byte;
  bidir                                 : boolean;
begin
  bidir := True;
  data := ReadPort(LptNumber, LPT_CONTROL_REG); // ������ ������� ����������
  WritePort(LptNumber, LPT_CONTROL_REG, data or Direction); // ������������� ��� ����������� (DIR)
  bidir := bidir and (Direction = (Direction and ReadPort(LptNumber, LPT_CONTROL_REG)));
  WritePort(LptNumber, LPT_CONTROL_REG, data and (not Direction)); // ������� ��� ����������� (DIR)
  bidir := bidir and (Direction <> (Direction and ReadPort(LptNumber, LPT_CONTROL_REG)));
  WritePort(LptNumber, LPT_CONTROL_REG, data); // ��������������� ������� �������� �������� ������
  IsPortBidirectional := bidir;
end;

{ ��������� ������ ������ � ���� �� ��� Windows 9x }

procedure TLptPortConnection.Writepk(Addr: Word; data: Byte);
begin
  asm
  push eax
  push edx
  mov dx,Addr
  mov al,Data
  out dx,al
  pop edx
  pop eax
  end;
end;

{ ��������� ����� ������ �� ����� �� ��� Windows 9x }

function TLptPortConnection.Readpk(Addr: Word): Byte;
var
  Value                                 : Byte;
begin
  asm
  push eax
  push edx
  mov dx,Addr
  in al,dx
  mov value,al
  pop edx
  pop eax
  end;
  Readpk := Value;
end;

// ��������� ��� ���������� ��������
// Time -- �������� �������� � ���. ���������� �������� - �� 0 �� 50 ���.

procedure TLptPortConnection.Delay(Time: Cardinal);
var
  ct                                    : Cardinal;
  ADS                                   : ADRDATASTRUCT;
begin
  ct := Time;
  if (ct > 50) then ct := 50;
  ct := (ct + ct + ct) shr 1; // *1.5, ��� ���� ������ �� ����� -- ��� �������� 0.6 .. 1.2 ��� �� ����������� �����,  ���������� �� ������� ��� � ����. ����.
  if (ct = 0) then ct := 1;
  if (PortPresent[0]) then // �������� ����, �� �������� ����� ������
  begin
    ADS.Adr := LPT1 or LPT_DATA_REG;
  end else
  begin
    if (PortPresent[1]) then
    begin
      ADS.Adr := LPT2 or LPT_DATA_REG;
    end else
    begin
      ADS.Adr := LPT3 or LPT_DATA_REG;
    end;
  end;
  while ct <> 0 do
  begin
    ReadPorts(@ADS, 1);
    Dec(ct);
  end;
end;

end.
