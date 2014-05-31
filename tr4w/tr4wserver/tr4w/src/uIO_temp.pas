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
unit uIO;

interface
uses TF, VC, WinSvc, Windows {, SysUtils, Forms};

{$IMPORTEDDATA OFF}

{
READ_PORT_UCHAR
The READ_PORT_UCHAR macro reads a byte from the specified port address.

UCHAR
  READ_PORT_UCHAR(
    IN PUCHAR  Port
    );
Parameters

Port
Specifies the port address, which must be a mapped memory range in I/O space.
Return Value

READ_PORT_UCHAR returns the byte that is read from the specified port address.

Comments

Callers of READ_PORT_UCHAR can be running at any IRQL, assuming the Port is resident, mapped device memory.
}

{
WRITE_PORT_UCHAR
The WRITE_PORT_UCHAR macro writes a byte to the specified port address.

VOID
  WRITE_PORT_UCHAR(
    IN PUCHAR  Port,
    IN UCHAR  Value
    );
Parameters

Port
Pointer to the port, which must be a mapped memory range in I/O space.
Value
Specifies a byte to be written to the port.
Return Value

None

Comments

Callers of WRITE_PORT_UCHAR can be running at any IRQL, assuming the Port is resident, mapped device memory.
}

type
  TOffsetType = (otData, otState, otControl);
  TBitOperation = (boSet0, boSet1);
  TBitSet = (bsBIT0, bsBIT1, bsBIT2, bsBIT3, bsBIT4, bsBIT5, bsBIT6, bsBIT7);
//control = 1,14,16,17
const
  DRV_BINARY_PATH_NAME                  : PChar = 'SYSTEM32\DRIVERS\TR4WIO.SYS';
  DRV_LINK_NAME                         : PChar = '\\.\TR4WIOAccess';

  STROBE_SIGNAL                         = bsBIT0; //PIN 01 INVERTED
  PTT_SIGNAL                            = bsBIT2; //PIN 16
  CW_SIGNAL                             = bsBIT3; //PIN 17 INVERTED
  RELAY_SIGNAL                          = bsBIT1; //PIN 14

 { ���� ��������� �������� }
  IOCTL_READ_PORTS                      : Cardinal = $00220050; // ������ ��������� LPT
  IOCTL_WRITE_PORTS                     : Cardinal = $00220060; // ������ � �������� LPT

  BIT0                                  : Byte = $01;
  BIT1                                  : Byte = $02;
  BIT2                                  : Byte = $04;
  BIT3                                  : Byte = $08;
  BIT4                                  : Byte = $10;
  BIT5                                  : Byte = $20;
  BIT6                                  : Byte = $40;
  BIT7                                  : Byte = $80;

  // Printer Port pin numbers
  ACK_PIN                               : Byte = 10;
  BUSY_PIN                              : Byte = 11;
  PAPEREND_PIN                          : Byte = 12;
  SELECTOUT_PIN                         : Byte = 13;
  ERROR_PIN                             : Byte = 15;
  STROBE_PIN                            : Byte = 1;
  AUTOFD_PIN                            : Byte = 14;
  INIT_PIN                              : Byte = 16;
  SELECTIN_PIN                          : Byte = 17;

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
//  SC_MANAGER_ALL_ACCESS                 : Cardinal = $000F003F;
//  SERVICE_ALL_ACCESS                    : Cardinal = $000F01FF;

  SWC_NAME                              : PChar = 'TR4WIO'; //'lptwdmio'; { ��������� ��� ������� }
  SWC_DISPLAY_NAME                      : PChar = 'TR4W IO Access'; //'LPT port direct access service'; { �������� �������, ����� �������� ������������ :) }

var
 { ����� ��� ��������� � �������� LPTWDMIO.sys }
//  TDriverConnection = class
//  private
  DriverFailedToLoad                    : boolean;
  DriverHandle                          : Cardinal = INVALID_HANDLE_VALUE; // ����� ������������ ��������
  DriverWinNT                           : boolean = True; // ������� ��������� NT

  { ������, ����������� � ������ ��������� �������� �� ���������� NT }
//  UnregisterService                     : boolean; // ����, ������������ ������������� �������� ������� lptwdmio �� �������� ���������� � Win NT

  ServiceArgVectors                     : PChar; // ��������������� ���������� ��� ������ StartService

procedure DriverCreateFile;
procedure DriverCreate;
procedure DriverDestroy;
procedure DriverDirectWrite(Addr: Word; data: Byte);
procedure DriverBitOperation(var TempByte: Byte; BitToSet: TBitSet; Operation: TBitOperation);
procedure SetPortByte(PortAddress: Word; Offset: TOffsetType; data: Byte);

function DriverDirectRead(Addr: Word): Byte;
function DriverIsLoaded: boolean;
function GetPortByte(PortAddress: Word; Offset: TOffsetType): Byte;

function IsPortPresent(LptNumber: Word): boolean;

implementation

procedure DriverCreate;
var
  hSCMahager                            : SC_HANDLE; // ����� ��������� ��������
  hServiceHandle                        : SC_HANDLE; // ����� ������� lptwdmio
  osv                                   : OSVERSIONINFO; // ��������� ��� ��������� ������ ���������

begin

  DriverHandle := INVALID_HANDLE_VALUE;
//  UnregisterService := False;

  if DriverFailedToLoad then Exit;

  osv.dwOSVersionInfoSize := SizeOf(osv);
  GetVersionEx(osv);
  DriverWinNT := (osv.dwPlatformId = VER_PLATFORM_WIN32_NT);

 // ������� ��������� � ���������
  DriverCreateFile;

  if DriverHandle = INVALID_HANDLE_VALUE then
    if DriverWinNT then
    begin
      hSCMahager := OpenSCManager(nil, nil, SC_MANAGER_ALL_ACCESS);
      if 0 <> hSCMahager then
      begin

        hServiceHandle := CreateService(hSCMahager,
          SWC_NAME, // ��� �������
          SWC_DISPLAY_NAME, // ������������ ���
          SERVICE_ALL_ACCESS, // ����� �������
          SERVICE_KERNEL_DRIVER,
          SERVICE_AUTO_START,
          //SERVICE_DEMAND_START,
          SERVICE_ERROR_NORMAL,
          DRV_BINARY_PATH_NAME,
          nil,
          nil,
          nil,
          nil,
          nil);
        if 0 = hServiceHandle then
        begin // ��������, ������ ��� ������ �����
          hServiceHandle := OpenService(hSCMahager, SWC_NAME, SERVICE_ALL_ACCESS); // ������� ���
        end;

        if 0 <> hServiceHandle then
        begin // ��, ��������� ������
          if not StartService(hServiceHandle, 0, ServiceArgVectors) then // ��� ������� ������ �����������...
//            if GetLastError <> ERROR_SERVICE_ALREADY_RUNNING then
          begin
            DriverFailedToLoad := True;

            ShowSysErrorMessage(DRV_BINARY_PATH_NAME);

//            if GetLastError in [ERROR_FILE_NOT_FOUND] then
//              showwarning('To use the parallel port select "tr4wio.sys" component during installation');
          end;

//          UnregisterService := True; // ��� ���������� ������� �� ������ �������� ������ ��� ��������
          CloseServiceHandle(hServiceHandle); // ����������� �����
        end;

        CloseServiceHandle(hSCMahager); // ����������� �����
      end;

   // �������� �������� ��������� � ���������
      DriverCreateFile;
    end;

end;

procedure DriverCreateFile;
begin
  SetLastError(NO_ERROR);
  DriverHandle := CreateFile(DRV_LINK_NAME, GENERIC_READ or GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
end;

procedure DriverDestroy;
var
  hSCMahager                            : SC_HANDLE;
  hServiceHandle                        : SC_HANDLE;
begin

  if DriverHandle <> INVALID_HANDLE_VALUE then CloseHandle(DriverHandle);
{
  if UnregisterService and DriverWinNT then
  begin // ����������������� ������
    begin
      hSCMahager := OpenSCManager(nil, nil, SC_MANAGER_ALL_ACCESS); // ��������� � ���������� ��������
      if 0 <> hSCMahager then
      begin
        hServiceHandle := OpenService(hSCMahager, SWC_NAME, SERVICE_ALL_ACCESS); // �������� ����� ������� lptwdmio
        if hServiceHandle <> 0 then
        begin
          DeleteService(hServiceHandle); // �������� ������ ��� ���������� ��������. ������� ��������� � ������ �� ��������� ������������.
          CloseServiceHandle(hServiceHandle); // ����������� �����
        end;
        CloseServiceHandle(hSCMahager); // ����������� ����� ��������� ��������
      end;
    end;
  end;
}
end;

// ���������� ������� ����������/������������

function DriverIsLoaded: boolean;
begin
  Result := (DriverHandle <> INVALID_HANDLE_VALUE) or not DriverWinNT; // ���� �������� �������, ���� Windows 9x
end;

function GetPortByte(PortAddress: Word; Offset: TOffsetType): Byte;
var
  lpBytesReturned                       : DWORD;
  lpOutBuffer                           : Byte;
  TempAddress                           : Word;
begin
  if not DriverIsLoaded() then Exit;
  if DriverHandle <> INVALID_HANDLE_VALUE then
  begin // ������ ����� �������

    TempAddress := PortAddress + Word(Offset);
    lpBytesReturned := 0;
    DeviceIoControl(DriverHandle,
      IOCTL_READ_PORTS,
      @TempAddress, 2, //InBuffer
      @lpOutBuffer, 1, //OutBuffer
      lpBytesReturned,
      nil);
    Result := lpOutBuffer;
  end
  else
    Result := DriverDirectRead(PortAddress + Word(Offset));
end;

procedure SetPortByte(PortAddress: Word; Offset: TOffsetType; data: Byte);
var
  lpBytesReturned                       : DWORD;
  lpInBuffer                            : Cardinal;
begin
  if Offset = otState then Exit;
  if not DriverIsLoaded() then Exit;
  if DriverHandle <> INVALID_HANDLE_VALUE then
  begin
    lpInBuffer := MakeLong(PortAddress + Word(Offset), data);
    lpBytesReturned := 0;

    DeviceIoControl(DriverHandle,
      IOCTL_WRITE_PORTS,
      @lpInBuffer, 4, //InBuffer
      nil, 0, //OutBuffer
      lpBytesReturned,
      nil);
  end

  else
    DriverDirectWrite(PortAddress + Word(Offset), data);
end;

// �-� ������������ ������� �����. ��������� true, ���� ���� ������������.

function IsPortPresent(LptNumber: Word): boolean;
var
  data                                  : Byte;
  present                               : boolean;
begin
  present := True;
  data := GetPortByte(LptNumber, otData); // ��������� ������� �������� �������� ������
  SetPortByte(LptNumber, otData, $00); // ����� 0
  present := present and ($00 = GetPortByte(LptNumber, otData)); // �������� -- ��� ��������, �� � ���������?
  SetPortByte(LptNumber, otData, $55); // ����� $55
  present := present and ($55 = GetPortByte(LptNumber, otData));
  SetPortByte(LptNumber, otData, $AA); // ����� $AA
  present := present and ($AA = GetPortByte(LptNumber, otData));
  SetPortByte(LptNumber, otData, data); // ��������������� ������� �������� �������� ������
 // �������� ������� ��������� ���������� � ������, ���� ���� �� ��������� (� ������ ����������������� �����)
  if not present then
  begin
    data := GetPortByte(LptNumber, otControl); // ������ ������� ����������
    present := (data <> $00) and (data <> $FF); // �� ������ ��������? -- ���� ������������
    if not present then
    begin
      data := GetPortByte(LptNumber, otState); // ������ ������� ���������
      present := (data <> $00) and (data <> $FF);
    end;
  end;
  IsPortPresent := present;
end;

// �-� ������������ ����� �� �����������������
{
function IsPortBidirectional(LptNumber: Byte): boolean;
var
  data                             : Byte;
  bidir                            : boolean;
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
}
{ ��������� ������ ������ � ���� �� ��� Windows 9x }

procedure DriverDirectWrite(Addr: Word; data: Byte);
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

function DriverDirectRead(Addr: Word): Byte;
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
  Result := Value;
end;

procedure DriverBitOperation(var TempByte: Byte; BitToSet: TBitSet; Operation: TBitOperation);
type
  TByteSet = set of 0..SizeOf(Byte) * 8 - 1;
begin
  if Operation = boSet0
    then
//    Exclude(TByteSet(TempByte), integer(BitToSet))
    TempByte := TempByte and not (1 shl Byte(BitToSet))
  else
    TempByte := TempByte or (1 shl Byte(BitToSet));
//    Include(TByteSet(TempByte), integer(BitToSet));
end;

end.

