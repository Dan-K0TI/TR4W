unit uWSJTX;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs,  IdComponent, IdUDPBase, IdUDPServer, IdTCPServer,IdUDPClient, IdContext,
  IdBaseComponent, IdSocketHandle, IdGlobal, IdStackConsts, StdCtrls,
  NetworkMessageUtils, DateUtils, StrUtils, LOGRADIO, IdThreadSafe, IdThread
  ;

type
   TColorRec = record
      R: byte;
      G: byte;
      B: byte;
   end;
type
  TWSJTXServer = class(TObject)
  private
      udpServ : TIdUDPServer;
      tcpServ: TIdTCPServer;
      UFreq, UModeRX, UModeTX, UDXCall, URSTs, UHeureDeb : string;
      UCall,ULoc : string;
      UIndex:integer;
      peerPort: word;
      FUDPPort: integer;
      FTCPPort: integer;
      SNR: LongInt;
      frequency: Int64;
      firstTime: boolean;
      isConnected: boolean;
      colorsMultFore: TColorRec;
      colorsDupeFore: TColorRec;
      colorsMultBack: TColorRec;
      colorsDupeBack: TColorRec;
      context: TIdContext;
      buffer: TIdBytes;
      sBuffer: string;
      procedure SetUDPPort(nPort: integer);
      procedure SetTCPPort(nPort: integer);
      function GetNextADIFField(var sBuffer: string; var fieldName: string; var fieldValue: string): boolean;
  protected
    procedure OnServerRead(ASender: TIdUDPListenerThread; const AData: TIdBytes; ABinding: TIdSocketHandle);
    procedure OnBeforeBind(AHandle: TIdSocketHandle);
    procedure IdTCPServer1Execute(AContext: TIdContext);
    procedure IdTCPServer1Connect(AContext: TIdContext);
  public
    constructor Create; overload;
    constructor Create(nUDPPort: integer; nTCPPort: integer); overload;
    //constructor Create(radio: radioObject); overload;
    procedure Start;    // May want to add the port number to a constructor - for now use default
    procedure Stop;
    destructor Destroy;
    procedure HighlightCall(sCall: string; color: integer; sId: string);
    procedure ClearColors(sId: string);
    property connected: boolean read isConnected;
    procedure SetDupeBackgroundColor(bRed: byte; bGreen: byte; bBlue: byte);
    procedure SetMultBackgroundColor(bRed: byte; bGreen: byte; bBlue: byte);
    procedure SetDupeForegroundColor(bRed: byte; bGreen: byte; bBlue: byte);
    procedure SetMultForegroundColor(bRed: byte; bGreen: byte; bBlue: byte);
    procedure Display(p_sender : String; p_message : string);
    Property UDPPort: integer read FUDPPort write SetUDPPort;
    Property TCPPort: integer read FTCPPort write SetTCPPort;

  end;

implementation

uses
    VC            // For ContestExchange
   ,MainUnit      // For ParseADIFRecord
   ,LogDupe       // For ClearContestExchange - Stuff is all over the place in this code! de NY4I
   ,uCTYDAT       // For ctyLocateCall
   ,utils_file    // For tWriteFile
   ,LOGSUBS2      // For LogContact
   ,LogStuff      // For CalculateQSOPoints
   ,LogEdit       // For ShowStationInformation and DetermineIfNewMult
   ,LOGWIND       // for GetBandMapBandModeFromFrequency
   ,TF            // for SetMainWindowText
   ,utils_text
   ;
// {$R *.dfm}

constructor TWSJTXServer.Create;
begin
   firstTime := true;
   udpServ := TIdUDPServer.Create(nil);
   udpServ.ThreadedEvent := true;
   if FUDPPort = 0 then
      begin
      FUDPPort := 2237;
   end;

   if FTCPPort = 0 then
      begin
      FTCPPort := 52002;
      end;

   udpServ.DefaultPort := FUDPPort;
   udpServ.Bindings.Add.IP := '';
   udpServ.OnUDPRead := Self.OnServerRead;
   udpServ.OnBeforeBind := Self.OnBeforeBind;
   colorsDupeBack.R := $FF;
   colorsDupeBack.G := $00;
   colorsDupeBack.B := $00;

   colorsMultBack.R := $FF;
   colorsMultBack.G := $FF;
   colorsMultBack.B := $00;

   colorsDupeFore.R := $00;
   colorsDupeFore.G := $00;
   colorsDupeFore.B := $00;

   colorsMultFore.R := $00;
   colorsMultFore.G := $00;
   colorsMultFore.B := $00;

   tcpServ := TIdTCPServer.Create(nil);
   tcpServ.OnExecute := Self.IdTCPServer1Execute;
   tcpServ.OnConnect := Self.IdTCPServer1Connect;
end;

constructor TWSJTXServer.Create(nUDPPort: integer; nTCPPort: integer);
begin
   FUDPPort := nUDPPort;
   FTCPPort := nTCPPort;
   inherited Create;
end;

{constructor TWSJTXServer.Create(radio: radioObject);
begin
   inherited Create;
   Self.radio := radio;
end;
}
procedure TWSJTXServer.Start;
begin
   udpServ.Active := true;

   // ... START SERVER:

    // ... clear the Bindings property ( ... Socket Handles )
   tcpServ.Bindings.Clear;
    // ... Bindings is a property of class: TIdSocketHandles;

    // ... add listening ports:

    // ... add a port for connections from guest clients.
   tcpServ.Bindings.Add.Port := 52002;
   tcpServ.Active := true;
end;

procedure TWSJTXServer.Stop;
begin
   udpServ.Active := false;
   tcpServ.Active := false;
end;

destructor TWSJTXServer.Destroy;
begin
   udpServ.Active := false;
   FreeAndNil(udpServ);

   tcpServ.Active := false;
   FreeAndNil(tcpServ);


end;

procedure TWSJTXServer.SetUDPPort(nPort: integer);
begin
   Self.FUDPPort := nPort;
   if Self.udpServ.Active then
      begin
      Self.udpServ.active := false;
      udpServ.DefaultPort := Self.FUDPPort;
      udpServ.Active := true;
      end;
end;

procedure TWSJTXServer.SetTCPPort(nPort: integer);
begin
   Self.FTCPPort := nPort;
end;

procedure TWSJTXServer.OnBeforeBind(AHandle: TIdSocketHandle);
begin
  AHandle.SetSockOpt( Id_SOL_SOCKET, Id_SO_REUSEADDR, Id_SO_True);
end;

procedure TWSJTXServer.OnServerRead(ASender: TIdUDPListenerThread; const AData: TIdBytes; ABinding: TIdSocketHandle);
var
  index: Integer;
  magic, schema, messageType: LongInt;
  id, mode, DXCall, report, TXMode, message, DXGrid, DEGrid, DECall, reportReceived: string;
  call : CallString;
  TXPower, comments, DXName, adif: string;

  isNew, TXEnabled, transmitting, Decoding: Boolean;
  tm: Longword;
  ztime: TDateTime;
  DT: Double;
  DF: Cardinal;
  date: TDateTime;
  {Ajout ici}
  slCQMessage: TStringList;
  Memomessage,locator: string;
  rst, RXDF, TXDF: integer;
  TempRXData: ContestExchange;
  lpNumberOfBytesWritten: Cardinal;
  inx: integer;
  TempMode: ModeType;
  TempBand: BandType;
  grid: string;

begin
     //FUDP.IdUDPServer1.Bindings := '127.0.0.1:2237,[::]:2237';
  index := 0;
  peerPort := ABinding.PeerPort;     {............................................récupération du port d'écoute}

//  peerPort := 2237;

  //DEBUGMSG('WSJTX >>> Datagram received - length: ' + IntToStr(Length(AData))); { DO NOT DELETE THIS }
   while index < Length(AData) do
   begin
      Unpack(AData, index, magic);
      //DEBUGMSG('WSJTX >>> index:' + IntToStr(index) + ' magic:$' + IntToHex(magic,8)); { DO NOT DELETE THIS }
      if (magic = LongInt($ADBCCBDA)) and (index < Length(AData)) then
         begin
         Unpack(AData, index, schema);
         if (schema = 2) and (index < Length(AData)) then
            begin
            Unpack(AData,index,messageType);
            Unpack(AData,index,id);
            //DEBUGMSG('Message type:' + IntToStr(messageType) + ' from:[' + id + ']');   { DO NOT DELETE THIS }

            case messageType of
            0: begin
               //DEBUGMSG('WSJTX >>> Heartbeat!');  { DO NOT DELETE THIS }
               DEBUGMSG('Radio frequency = ' + IntToStr(radio1.CurrentStatus.Freq));
               SetMainWindowText(mweWSJTX,'WSJTX');
               Windows.ShowWindow(wh[mweWSJTX], SW_SHOW);
               isConnected := true;
               if firstTime then
                  begin
                  ClearColors(id);
                  firstTime := false;
                  end;
               end;
            1:         {............................................................Status}
               begin
               Unpack(AData,index,frequency);
               Unpack(AData,index,mode);
               Unpack(AData,index,DXCall);
               Unpack(AData,index,report);
               Unpack(AData,index,TXMode);
               Unpack(AData,index,TXEnabled);
               Unpack(AData,index,transmitting);

               Unpack(AData,index,Decoding);
               Unpack(AData,index,RXDF);
               Unpack(AData,index,TXDF);
               Unpack(AData,index,DECall);
               Unpack(AData,index,DEGrid);
               Unpack(AData,index,DXGrid);
              // Memomessage := IntToStr(frequency.Hi);
               {DEBUGMSG('WSJTX >>> Status: Frequency: ' + IntToStr(frequency) + ' Mode: ' + mode + ' DX Call: ' + DXCall
                                    + ' Report: ' + report + ' TX Mode: ' + TXMode + ' TX Enabled: ' + BoolToStr(TXEnabled)
                                    + ' Transmitting: ' + BoolToStr(transmitting) + ' Decoding: ' + BoolToStr(Decoding)
                                    + ' RXDF: ' + intToStr(RXDF) + ' TXDF: ' + intToStr(TXDF) + ' DECall: ' + DECall + ' DEGrid: ' + DEGrid
                                    + ' DXGrid: ' + DXGrid);
               }

               // if transmitting then
               //    FalarmeJT.SLedTransmit.Brush.Color:=clRed
               // else
               //   FalarmeJT.SLedTransmit.Brush.Color:=clGreen;
               end;

            2: begin        {............................................................Decode}
                           // This is where we need to look for CQ decodes and highlight the call by sending back
                           // a message to the UDP receiver in WSJT-X.
               Unpack(AData,index,isNew);
               Unpack(AData,index,tm);
               ztime := IncMilliSecond(0,tm);
               Unpack(AData,index,SNR);
               Unpack(AData,index,DT);
               Unpack(AData,index,DF);
               Unpack(AData,index,mode);
               Unpack(AData,index,message);

              { Memomessage :='Decode:'+' '+BoolToStr(isNew)+' '+FormatDateTime('hhmm',ztime)+' '+IntToStr(SNR)
                                   +' '+ FloatToStrF(DT, ffGeneral,4,1)+' '+IntToStr(DF)
                                   +' '+ mode +' '+ message +' '+ timeToStr(ztime) +' '+ FloatToStr(DT) +' '+ intToStr(tm);
               DEBUGMSG('WSJTX >>> ' + Memomessage);  }
               if MidStr(message,1,2) = 'CQ' then
                  begin
                  slCQMessage := TStringList.Create;
                  try
                     slCQMessage.Delimiter := ' ';              // cq ny4i el87     a1   OR cq fd ny4i el87  a1
                     slCQMessage.DelimitedText := message;
                     try
                        if slCQMessage[0] = 'CQ' then
                           begin
                           if slCQMessage.Count = 2 then
                              begin
                              DXCall := slCQMessage[1];
                              end
                           else if slCQMessage.Count > 2 then
                              begin
                              if length(slCQMessage[1]) = 2 then // most likely directed or contest
                                 begin
                                 DXCall := slCQMessage[2];
                                 grid := slCQMessage[3];
                                 end
                              else if slCQMessage.Count = 3 then
                                 begin  // standard CQ CALL GRID
                                 DXCall := slCQMessage[1];
                                 grid := slCQMessage[2];
                              end;
                           call := DXCall;

                           // Here we cheat a little bit on Frequency. The idea is that the status command is send enough that it gives
                           // us the frequency. SO turn the frequency into the band.
                           // We could also use the radio object to check
                           GetBandMapBandModeFromFrequency(frequency, TempBand, TempMode);
                           TempMode := Digital;   // override TempMode since we know it is digital. Until a contest differentiates between FT8 and FT4 that is ok

                           if  VisibleLog.CallIsADupe(call, TempBand, TempMode) then
                              begin
                              DEBUGMSG(DXCall + ' is a DUPE');
                              HighLightCall(message,1,id);
                              end
                           else if VisibleLog.DetermineIfNewMult(call, TempBand, TempMode) then
                              begin
                              DEBUGMSG(DXCall + ' is a MULT');
                              HighLightCall(message,2, id); // Pass back id as given to us
                              end;
                          end;
                        end;
                     except
                        DEBUGMSG('*** Error in stringList access - sl.Count = ' + IntToStr(slCQMessage.Count));
                        DEBUGMSG('*** Message = ' + message);
                     end;
                  finally
                     slCQMessage.Free;
                  end;


                  end;
               end;

            3: begin        {............................................................Clear}
               DEBUGMSG('WSJTX >>> Clear');
               end;

            5: begin        {..........I may grab this from the ADIF record so this would not be needed   QSO logged}
            {
               Unpack(AData,index,date);
               Unpack(AData,index,DXCall);
               Unpack(AData,index,DXGrid);
               Unpack(AData,index,frequency);
               Unpack(AData,index,mode);
               Unpack(AData,index,report);
               Unpack(AData,index,reportReceived);
               Unpack(AData,index,TXPower);
               Unpack(AData,index,comments);
               Unpack(AData,index,DXName);

               DEBUGMSG('QSO logged: Date:' + FormatDateTime('dd-mmm-yyyy hh:mm:ss',date)
                               + ' DX Call:' + DXCall + ' DX Grid:' + DXGrid
                               + ' Frequency:' + IntToStr(frequency.Hi) + ' Mode:' + mode + ' Report sent: ' + report
                               + ' Report received:' + reportReceived + ' TX Power:' + TXPower
                               + ' Comments:' + comments + ' Name:' + DXName);
            }  end;
            6:
               begin
               DEBUGMSG('WSJT-X close message received'); // We may want to indicate it somehow on main screen
               SetMainWindowText(mweWSJTX,'');
               Windows.ShowWindow(wh[mweWSJTX], SW_HIDE);
               isConnected := false;
               end;
            10: begin
                DEBUGMSG('Received message 10');
                end;
            12: begin
               Unpack(AData,index,adif);
               DEBUGMSG('WSJTX >>> ADIF Record to log: ' + adif);
               ClearContestExchange(TempRXData);
               if ParseADIFRecord(adif, TempRXData) then // processed a record if true
                  begin
                  ctyLocateCall(TempRXData.Callsign, TempRXData.QTH);
                  CalculateQSOPoints(TempRXData);
                  LogContact(TempRXData, true);

                  ShowStationInformation(@TempRXData.Callsign);
                  UpdateWindows;
                  end;
               end;
            else
               begin
               DEBUGMSG('WSJTX >>> Unrecognized message type:' + IntToStr(messageType));
               end;
         end;
      end;
    end;
  end;
end;

{
Highlight Callsign In   13                     quint32    Integer
                           Id (unique key)        utf8
                           Callsign               utf8
                           Background Color       QColor
                           Foreground Color       QColor
                           Highlight last         bool
}
procedure TWSJTXServer.HighlightCall(sCall: string; color: integer; sId: string);
var
   sBuffer: string;
   AData: TIdBytes;
   messageType, magic, schema: LongInt;
   id, Ip, message: String;
   colorType: byte;
begin
// Build a header for a message
   magic := $ADBCCBDA;
   schema := 2;
   messageType := 13;
   id := sID;
   colorType := 1; // RGB
   pack(AData, magic);            {.............................................Magic number}
   pack(AData, schema);          {..............................................Schema}
   Pack(AData,messageType);        {............................................MessageType}
   pack(AData,id);                   {..........................................ID}
   Pack(AData,Trim(sCall));

   if color = 1 then // DUPE  defaults to red - Add code to pull from config if there
      begin
      // Background QColor first
      Pack(AData,colorType); // RGB
      PackFF00(AData);    // Alpha
      Pack(AData,Byte(colorsDupeBack.R)); Pack(AData,Byte(0)); // Red
      Pack(AData,Byte(colorsDupeBack.G)); Pack(AData,Byte(0)); // Green
      Pack(AData,Byte(colorsDupeBack.B)); Pack(AData,Byte(0)); // Blue
      PackFF00(AData); //Pack(AData,Word(65280));   // R
      Pack(AData,Word(0));     // Padding

      // foreground
      Pack(AData,colorType); // RGB
      PackFF00(AData);    // Alpha
      Pack(AData,Byte(colorsDupeFore.R)); Pack(AData,Byte(0)); // Red
      Pack(AData,Byte(colorsDupeFore.G)); Pack(AData,Byte(0)); // Green
      Pack(AData,Byte(colorsDupeFore.B)); Pack(AData,Byte(0)); // Blue
      PackFF00(AData); //Pack(AData,Word(65280));   // R
      Pack(AData,Word(0));     // Padding
      end
   else if color = 2 then // multiplier
      begin
      // Background QColor first

      Pack(AData,colorType);
      PackFF00(AData);   //Pack(AData,Word(65280));     // Alpha
      Pack(AData,Byte(colorsMultBack.R)); Pack(AData,Byte(0)); // Red
      Pack(AData,Byte(colorsMultBack.G)); Pack(AData,Byte(0)); // Green
      Pack(AData,Byte(colorsMultBack.B)); Pack(AData,Byte(0)); // Blue
      Pack(AData,Word(0));     // Padding

      Pack(AData,colorType);
      PackFF00(AData);   //Pack(AData,Word(65280));     // Alpha
      Pack(AData,Byte(colorsMultFore.R)); Pack(AData,Byte(0)); // Red
      Pack(AData,Byte(colorsMultFore.G)); Pack(AData,Byte(0)); // Green
      Pack(AData,Byte(colorsMultFore.B)); Pack(AData,Byte(0)); // Blue
      Pack(AData,Word(0));     // Padding
      end;

   Pack(AData,true);        // Highlight last only

   DEBUGMSG('Sending command to highlight ' + Trim(sCall));
   udpServ.SendBuffer('127.0.0.1', PeerPort, AData);

end;

procedure TWSJTXServer.ClearColors(sId: string);
var
   sBuffer: string;
   AData: TIdBytes;
   messageType, magic, schema: LongInt;
   id, Ip, message: String;
   colorType: byte;
begin
// Build a header for a message
   magic := $ADBCCBDA;
   schema := 2;
   messageType := 13;
   id := sID;
   colorType := 0; // RGB
   pack(AData, magic);            {.............................................Magic number}
   pack(AData, schema);          {..............................................Schema}
   Pack(AData,messageType);        {............................................MessageType}
   pack(AData,id);                   {..........................................ID}
   Pack(AData,' ');                // blank call?


   // Background QColor first
   //
   Pack(AData,Byte(0));
   Pack(AData,Word(0));
   Pack(AData,Word(0));
   Pack(AData,Word(0));
   Pack(AData,Word(0));

   Pack(AData,Byte(0));
   Pack(AData,Word(0));
   Pack(AData,Word(0));
   Pack(AData,Word(0));
   Pack(AData,Word(0));


   Pack(AData,true);        // Highlight last only

   DEBUGMSG('Sending Reset Colors');
   udpServ.SendBuffer('127.0.0.1', PeerPort, AData);

end;

procedure TWSJTXServer.SetDupeBackgroundColor(bRed: byte; bGreen: byte; bBlue: byte);
begin
   Self.colorsDupeBack.R := bRed;
   Self.colorsDupeBack.G := bGreen;
   Self.colorsDupeBack.B := bBlue;
end;

procedure TWSJTXServer.SetMultBackgroundColor(bRed: byte; bGreen: byte; bBlue: byte);
begin
   Self.colorsMultBack.R := bRed;
   Self.colorsMultBack.G := bGreen;
   Self.colorsMultBack.B := bBlue;
end;

procedure TWSJTXServer.SetDupeForegroundColor(bRed: byte; bGreen: byte; bBlue: byte);
begin
   Self.colorsDupeFore.R := bRed;
   Self.colorsDupeFore.G := bGreen;
   Self.colorsDupeFore.B := bBlue;
end;

procedure TWSJTXServer.SetMultForegroundColor(bRed: byte; bGreen: byte; bBlue: byte);
begin
   Self.colorsMultFore.R := bRed;
   Self.colorsMultFore.G := bGreen;
   Self.colorsMultFore.B := bBlue;
end;




procedure TWSJTXServer.IdTCPServer1Execute(AContext: TIdContext);
var
    Port          : Integer;
    PeerPort      : Integer;
    PeerIP        : string;

    msgFromClient : string;
    msgToClient   : string;
    bytesWritten: integer;
    sFreq: string;
    sLen: string;
    nPos, len, n0, n1, newEnd: integer;
    freq: extended;
    fieldName, fieldValue: string;
    //buffer: TIdBytes;
    //sBuffer : string;
    const GETFREQ = '<command:10>CmdGetFreq<parameters:0>';
    const SENDTX = '<command:9>CmdSendTx<parameters:0>';
    const SETFREQ = '<command:10>CmdSetFreq'; //<parameters:23><xcvrfreq:10> 7,074.000';
    const SETFREQ2= '<command:10>CmdSetFreq<parameters:23><xcvrfreq:10> 7,040.000';
    const SENDSPLIT = '<command:12>CmdSendSplit<parameters:0>';
    const SENDMODE = '<command:11>CmdSendMode<parameters:0>';
    const SETRX = '<command:5>CmdRX<parameters:0>';
    const SETTX = '<command:5>CmdTX<parameters:0>';
    const GETTXFREQ = '<command:12>CmdGetTXFreq<parameters:0>';

begin
    // ... get message from client
    AContext.Connection.IOHandler.ReadBytes(buffer,-1,true);
    sBuffer := BytesToString(buffer);
    RemoveBytes(buffer,length(sBuffer));


    // ... getting IP address, Port and PeerPort from Client that connected
    peerIP    := AContext.Binding.PeerIP;
    peerPort  := AContext.Binding.PeerPort;

    // ... message log
    Display('CLIENT', '(Peer=' + PeerIP + ':' + IntToStr(PeerPort) + ') ' + sBuffer);
    // ...
   while Self.GetNextADIFField(sBuffer,fieldName, fieldValue) do
      begin
      if fieldValue = 'CmdGetFreq' then
         begin
         sFreq := SysUtils.FormatFloat(',0.000',radio1.CurrentStatus.Freq/1000);
         Display('client','Sending frequency as ' + sFreq);
         AContext.Connection.IOHandler.Write(SysUtils.Format('<CmdFreq:%u>%s',[length(sFreq),sFreq]));
         end
      else if fieldName = 'xcvrfreq' then
         begin
         freq := SafeFloat(fieldValue);
         radio1.SetRadioFreq(Trunc(freq * 1000),Digital,'A');  // A is for VFO A
         DEBUGMSG('Setting radio to frequency ' + IntToStr(Trunc(freq)));
         end
      else if fieldValue = 'CmdSendSplit' then
         begin
         if radio1.CurrentStatus.Split then
            begin
            AContext.Connection.IOHandler.Write('<CmdSplit:2>ON');
            DEBUGMSG('Sending ' + '<CmdSplit:2>ON');
            end
         else
            begin
            AContext.Connection.IOHandler.Write('<CmdSplit:3>OFF');
            DEBUGMSG('Sending ' + '<CmdSplit:3>OFF');
            end;
         end
      else if fieldValue = 'CmdRX' then
         begin
         tPTTVIACAT(false);
         end
      else if fieldValue = 'CmdTX' then
         begin
         tPTTVIACAT(true);
         end
      else if fieldValue = 'CmdSendMode' then
         begin
         DEBUGMSG('Sending ' + '<CmdMode:6>Data-U');
         AContext.Connection.IOHandler.Write('<CmdMode:6>Data-U');
         end;
      end;

   while Length(sBuffer) > 0  do
      begin
      Display ('SERVER','Processing message ' + sBuffer);

      if AnsiStartsStr('<command', sBuffer) then
         begin
         // ProcessCommand(sBuffer,slFields);
         if AnsiStartsStr(GETFREQ, sBuffer) then
            begin
            sBuffer := RightStr(sBuffer,length(sBuffer) - length(GETFREQ));
            sFreq := SysUtils.FormatFloat(',0.000',radio1.CurrentStatus.Freq/1000);
            Display('client','Sending frequency as ' + sFreq);
            AContext.Connection.IOHandler.Write(SysUtils.Format('<CmdFreq:%u>%s',[length(sFreq),sFreq]));
            end
         else if AnsiStartsStr(SETRX, sBuffer) then
            begin
            sBuffer := RightStr(sBuffer,length(sBuffer) - length(SETRX));
            tPTTVIACAT(false);
            //AContext.Connection.IOHandler.Write('<CmdSendRX:3>OFF')
            end
         else if AnsiStartsStr(SETFREQ, sBuffer) then  // Parse out frequency    // <command:10>CmdSetFreq<parameters:23><xcvrfreq:10> 7,074.000';
            begin
            // find xcvrfreq
            nPos := AnsiPos('xcvrfreq',sBuffer);
            if nPos > 0 then
               begin
               if AnsiMidStr(sBuffer,nPos+8,1) = ':' then
                  begin
                  n0 := nPos + 9;
                  newEnd := n0;
                  n1 := AnsiPos('>',AnsiMidStr(sBuffer,nPos+9,length(sBuffer)));
                  if n1 > 0 then //n1 points to the > n0 to the number
                     begin
                     newEnd := newEnd + n1;
                     sLen := AnsiMidStr(sBuffer,n0,n1-1);
                     if length(sLen) > 0 then
                        begin
                        len := StrToIntDef(sLen,-1);
                        if len > -1 then
                           begin    // len is length of count for frequency frequency starts at n1+1
                           sFreq := AnsiMidStr(sBuffer,n0+n1+0,len);
                           newEnd := newEnd + len;
                           sFreq := Trim(sFreq);
                           freq := SafeFloat(sFreq);
                           radio1.SetRadioFreq(Trunc(freq * 1000),Digital,'A');  // A is for VFO A
                           DEBUGMSG('Setting radio to frequency ' + IntToStr(Trunc(freq)));
                           end
                        else
                           begin
                           DEBUGMSG('Could not convert len of frequency to a number');
                           end;
                        end;
                     end
                  else
                     begin
                     DEBUGMSG('Count not find > before frequency');
                     end;
                  end;
               end;
            if newEnd > 0 then
               begin
               sBuffer := RightStr(sBuffer,length(sBuffer) - newEnd);
               newEnd := 0;
               end
            else
               begin
               sBuffer := RightStr(sBuffer,length(sBuffer) - length(SETFREQ));
               end;
            end
         else if AnsiStartsStr(SETTX, sBuffer) then
            begin
            sBuffer := RightStr(sBuffer,length(sBuffer) - length(SETTX));
            tPTTVIACAT(true);
            end
         else if AnsiStartsStr(SENDSPLIT, sBuffer) then
            begin
            sBuffer := RightStr(sBuffer,length(sBuffer) - length(SENDSPLIT));
            if radio1.CurrentStatus.Split then
               begin
               AContext.Connection.IOHandler.Write('<CmdSplit:2>ON');
               DEBUGMSG('Sending ' + '<CmdSplit:2>ON');
               end
            else
               begin
               AContext.Connection.IOHandler.Write('<CmdSplit:3>OFF');
               DEBUGMSG('Sending ' + '<CmdSplit:3>OFF');
               end;
            end
         else if AnsiStartsStr(SENDMODE, sBuffer) then
            begin
            sBuffer := RightStr(sBuffer,length(sBuffer) - length(SENDMODE));
            DEBUGMSG('Sending ' + '<CmdMode:6>Data-U');
            AContext.Connection.IOHandler.Write('<CmdMode:6>Data-U');
            end
         else if AnsiStartsStr(SENDTX, sBuffer) then
            begin
            sBuffer := RightStr(sBuffer,length(sBuffer) - length(SENDTX));
            if radio1.CurrentStatus.TXOn then
               begin
               AContext.Connection.IOHandler.Write('<CmdTX:2>ON');
               DebugMsg('Sending ' + '<CmdTX:2>ON');
               end
            else
               begin
               AContext.Connection.IOHandler.Write('<CmdTX:3>OFF');
               DebugMsg('Sending ' + '<CmdTX:3>OFF');
               end;
            end
         else if AnsiStartsStr(GETTXFREQ, sBuffer) then
            begin
            sBuffer := RightStr(sBuffer,length(sBuffer) - length(GETTXFREQ));
            sFreq := SysUtils.FormatFloat(',0.000',radio1.CurrentStatus.Freq/1000);
            Display('CLIENT','Sending frequency as ' + sFreq);
            AContext.Connection.IOHandler.Write(SysUtils.Format('<CmdTXFreq:%u>%s',[length(sFreq),sFreq]));
            end
         else
            begin
            Display('CLIENT','Undefined message ' + sBuffer);
            sBuffer := '';
            end;
         end;
      end;

       Display('CLIENT','length(sBuffer) = ' + IntToStr(length(sBuffer)));
    // ... process message from Client

    // ...

    // ... send response to Client

    //AContext.Connection.IOHandler.WriteLn('... message sent from server :)');
end;

procedure TWSJTXServer.IdTCPServer1Connect(AContext: TIdContext);
begin
//DEBUGMSG('TCP client Connected');
end;

(*aaa:=copy(vstup,z+1,length(vstup));
    z:=pos(':',aaa);
    x:=pos('>',aaa);
    if (x=0) then exit; //  the record was not terminated ... disappearing

    //detect length of ADIF Data
    for i:=z+1 to x do
    begin
      if (aaa[i] in ['0'..'9']) then
        slen := slen + aaa[i]
    end;
    if slen = '' then
      DataLen := 0
    else
      DataLen := StrToInt(slen);
    //if dmData.DebugLevel >=1 then Write('Got length:',DataLen);

    if z<>0 then
      prik:=trim(copy(aaa,1,z-1))
    else
      prik:=trim(copy(aaa,1,x-1));

    aaa:=copy(aaa,x+1,length(aaa));

    z:=pos('<',aaa);
    i:= pos('_INTL',upcase(prik));
    *)

function TWSJTXServer.GetNextADIFField(var sBuffer: string; var fieldName: string; var fieldValue: string): boolean;
var
   i, z, n, x, dataLen: integer;
   aaa, sLen: string;
begin
   Result := false;
// Assumes we are pointing at the < in the next field
   z := AnsiPos('<',sBuffer);
   if z = 0 then
      begin
      DEBUGMSG('sBuffer does not start with < ' + sBuffer);
      sBuffer := '';
      exit;//  there is no other record - disappearing.
      end;


   aaa := copy(sBuffer,z+1,length(sBuffer));
   z := AnsiPos(':',aaa);
   x := AnsiPos('>',aaa);
   if x = 0 then
      begin
      exit; //  the record was not terminated ... disappearing
      end;
   for i := z + 1 to x do
      begin
      if aaa[i] in ['0'..'9'] then
         begin
         slen := slen + aaa[i];
         end;
      end;

    if slen = '' then
      begin
      DataLen := 0;
      end
    else
      begin
      DataLen := StrToInt(slen);
      end;
    DEBUGMSG('Got length:' + IntToStr(DataLen));

    if z<>0 then
      begin
      fieldName := trim(copy(aaa,1,z-1));
      end
    else
      begin
      fieldName := trim(copy(aaa,1,x-1));
      end;

    aaa := copy(aaa,x+1,length(aaa));

    z := AnsiPos('<',aaa);
    i := AnsiPos('_INTL',AnsiUppercase(fieldName));
    //if dmData.DebugLevel >=1 then Write(' pos INTL:',i);
    if z = 0 then
      begin
      fieldValue := copy(aaa,1,DataLen);
      sBuffer := copy(aaa,z,length(aaa)); // Was vstup:=''
      end
    else
      begin
      fieldValue := copy(aaa,1,DataLen);
      sBuffer := copy(aaa,z,length(aaa))
      end;
    fieldValue := Trim(fieldValue);
    Result := true;
    DEBUGMSG(fieldName + '=' + fieldValue);
end;
(*--------------------------------------------------------------------------------------------------------------------------------*)

procedure TWSJTXServer.Display(p_sender : String; p_message : string);
begin
   DEBUGMSG(p_message);
{    // ... DISPLAY MESSAGE
    TThread.Queue(nil, procedure
                       begin
                           DEBUGMSG('[' + p_sender + '] - '
                           + getNow() + ': ' + p_message);
                       end
                 );

    // ... see doc..
    // ... TThread.Queue() causes the call specified by AMethod to
    //     be asynchronously executed using the main thread, thereby avoiding
    //     multi-thread conflicts.
}
end;

end.




