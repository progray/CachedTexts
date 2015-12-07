unit SerializeUnit;


// compiler options
{$if CompilerVersion >= 24}
  {$LEGACYIFEND ON}
{$ifend}
{$if CompilerVersion >= 23}
  {$define UNITSCOPENAMES}
{$ifend}
{$U-}{$V+}{$B-}{$X+}{$T+}{$P+}{$H+}{$J-}{$Z1}{$A4}
{$ifndef VER140}
  {$WARN UNSAFE_CODE OFF}
  {$WARN UNSAFE_TYPE OFF}
  {$WARN UNSAFE_CAST OFF}
{$endif}
{$O+}{$R-}{$I-}{$Q-}{$W-}

interface
  uses {$ifdef UNITSCOPENAMES}
         System.SysUtils,
       {$else}
         SysUtils,
       {$endif}
       UniConv, CachedBuffers, CachedTexts,
       IdentifiersUnit;

type
  TOptionParams = record
    Name: UnicodeString;
    Count: NativeUInt;
    O1, O2, O3: UnicodeString;
  end;

{ TSerializeOptions record }

  TSerializeOptions = {$ifdef OPERATORSUPPORT}record{$else}object{$endif}
  private
    FCount: NativeUInt;
    FItems: TUnicodeStrings;
    FOutFileName: UnicodeString;
    FEnumTypeName: UnicodeString;
    FFuncParam: UnicodeString;
    FIgnoreCase: Boolean;
    FFuncName: UnicodeString;
    FLengthParam: UnicodeString;
    FUseFuncHeaders: Boolean;
    FEncoding: Word;
    FPrefix: UnicodeString;
    FCharsParam: UnicodeString;

    procedure FillCharactersParams(const AFuncParam, ACharsParam, ALengthParam: UnicodeString);
    procedure FillFuncParams(const AFuncName, AEnumTypeName, APrefix: UnicodeString);
    function ParseParams(var Params: TOptionParams; const S: UnicodeString): Boolean;
    procedure ParseOptionsLine(const S: UTF16String);
    procedure SetEncoding(const Value: Word);
  public
    function CachedStringType: UnicodeString;
    function ParseOption(const S: UnicodeString): Boolean;
    function Add(const S: UnicodeString): NativeUInt;
    procedure Delete(const AFrom: NativeUInt; const ACount: NativeUInt = 1);
    procedure AddFromFile(const FileName: string; const OptionsLine: Boolean);
    property Count: NativeUInt read FCount;
    property Items: TUnicodeStrings read FItems;

    property Encoding: Word read FEncoding write SetEncoding;
    property FuncParam: UnicodeString read FFuncParam write FFuncParam;
    property CharsParam: UnicodeString read FCharsParam write FCharsParam;
    property LengthParam: UnicodeString read FLengthParam write FLengthParam;
    property FuncName: UnicodeString read FFuncName write FFuncName;
    property EnumTypeName: UnicodeString read FEnumTypeName write FEnumTypeName;
    property Prefix: UnicodeString read FPrefix write FPrefix;
    property UseFuncHeaders: Boolean read FUseFuncHeaders write FUseFuncHeaders;
    property IgnoreCase: Boolean read FIgnoreCase write FIgnoreCase;
    property OutFileName: UnicodeString read FOutFileName write FOutFileName;
  end;


{ TSerializer class }

type
  PCases = ^TCases;
  TCases = record
    Count: NativeUInt;
    Values: array[0..3] of Cardinal;
  end;

  PCasesInfo = ^TCasesInfo;
  TCasesInfo = record
    ByteCount: NativeUInt;
    OrMask: NativeUInt;
    CheckedCount: NativeUInt;
    CaseCount: NativeUInt;
    ChildCount: NativeUInt;
  end;

  PWholeCasesInfo = ^TWholeCasesInfo;
  TWholeCasesInfo = array[1..4] of TCasesInfo;

  TSerializer = class(TObject)
  private
    FLines: PUnicodeStrings;
    FLinesCount: NativeUInt;
    FOptions: ^TSerializeOptions;
    FStringKind: TCachedStringKind;
    FCharSize: NativeUInt;
    FIsFunction: Boolean;
    FIsConsts: Boolean;
    FFunctionValues: TUnicodeStrings;

    procedure InspecOptions;
    function FunctionValue(const Identifier: UnicodeString): UnicodeString;
  private
    FTextBuffer: UnicodeString;

    procedure AddLine; overload;
    procedure AddLine(const S: UnicodeString); overload;
    procedure AddLineFmt(const FmtStr: UnicodeString; const Args: array of const);
    procedure TextBufferClear;
    procedure TextBufferFlush;
    procedure TextBufferInclude(const Level: NativeUInt; const S: UnicodeString);
    procedure TextBufferIncludeFmt(const Level: NativeUInt; const FmtStr: UnicodeString; const Args: array of const);
    procedure TextBufferInit(const Level: NativeUInt; const S: UnicodeString);
    procedure TextBufferInitLength(const Level: NativeUInt; const Value: NativeUInt);
    procedure TextBufferInitFmt(const Level: NativeUInt; const FmtStr: UnicodeString; const Args: array of const);
    procedure TextBufferIncludeIfThenLine(const Level: NativeUInt; const Item: PIdentifier; Offset, ByteCount: NativeUInt);
    procedure TextBufferIncludeComments(const Items: PIdentifierItems; const Count: NativeUInt);
  private
    FCasesBuffer: array of TCases;

    function CheckCases(const Items: PIdentifierItems; const Count, Offset, ByteCount, OrMask: Cardinal; const KnownLength: Boolean; var CheckedCount, CaseCount: NativeUInt): NativeUInt; overload;
    function CheckCases(const Items: PIdentifierItems; const Count, Offset: NativeUInt; const KnownLength: Boolean): TWholeCasesInfo; overload;
    function CalculateBestCases(const Items: PIdentifierItems; const Count, Offset: NativeUInt; const KnownLength: Boolean): TCasesInfo;
    procedure InspectIdentifiers(const Items: PIdentifierItems; const Count, Offset: NativeUInt; const KnownLength: Boolean; var MinDataSize, MaxDataSize, SameDataSize: NativeUInt);
    procedure WriteCaseIdentifiers(const Items: PIdentifierItems; const Count, Offset, Level: NativeUInt; const BestCases: TCasesInfo; const KnownLength: Boolean);
    procedure WriteLengthIdentifiers(const Items: PIdentifierItems; const Count, Offset, Level: NativeUInt);
    procedure WriteIdentifiers(const Items: PIdentifierItems; const Count, Offset, LargeCodeLevel, Level: NativeUInt; KnownLength: Boolean);
  public
    function Process(const Options: TSerializeOptions): TUnicodeStrings;
  end;


implementation

const
  AND_VALUES: array[1..4] of Cardinal = ($ff, $ffff, $ffffff, $ffffffff);
  MEMORYDATA_POSTFIXES: array[0..3] of string = ('', '1', '2', '3');

type
  T4Bytes = array[0..3] of Byte;
  P4Bytes = ^T4Bytes;
  TUseDataProc = function(const Item: PIdentifier; const Offset: NativeUInt): UnicodeString;

function UnicodeFormat(const FmtStr: UnicodeString; const Args: array of const): UnicodeString;
begin
  Result := {$ifdef UNICODE}Format{$else}WideFormat{$endif}(FmtStr, Args);
end;

function InternalException: Exception;
begin
  Result := Exception.Create('Internal exception.'#13+
    'Please, send your file to developers at softforyou@inbox.ru');
end;

function UseByte(const Item: PIdentifier; const Offset: NativeUInt): UnicodeString;
begin
  Result := UnicodeFormat('Bytes[%d]', [Offset]);
end;

function UseWord(const Item: PIdentifier; const Offset: NativeUInt): UnicodeString;
begin
  Result := UnicodeFormat('Word%s[%d]', [MEMORYDATA_POSTFIXES[Offset and 1], Offset shr 1]);
end;

function UseCardinal(const Item: PIdentifier; const Offset: NativeUInt): UnicodeString;
begin
  Result := UnicodeFormat('Cardinals%s[%d]', [MEMORYDATA_POSTFIXES[Offset and 3], Offset shr 2]);
end;

function UseThree(const Item: PIdentifier; const Offset: NativeUInt): UnicodeString;
begin
  if (Offset = 0) then
  begin
    if (Item.DataSize >= 4) then
    begin
      Result := UseCardinal(Item, 0) + ' and $ffffff';
    end else
    begin
      Result := UseWord(Item, Offset) + ' + ' + UseByte(Item, Offset + SizeOf(Word)) + ' shl 16';
    end;
  end else
  begin
    Result := UseCardinal(Item, Offset - 1) + ' shr 8';
  end;
end;

var
  USE_DATA_PROCS: array[1..4] of TUseDataProc = (
    UseByte,
    UseWord,
    UseThree,
    UseCardinal
  );

function HexConst(const Value, ByteCount: NativeUInt): UnicodeString;
var
  i: NativeUInt;
begin
  Result := UnicodeFormat('$%*x', [ByteCount * 2, Value]);
  for i := 1 to Length(Result) do
  if (Result[i] = #32) then Result[i] := '0';
end;

function UseDataMasked(const Item: PIdentifier; const Offset, ByteCount: NativeUInt): UnicodeString;
var
  OrMask: Cardinal;
begin
  Result := USE_DATA_PROCS[ByteCount](Item, Offset);
  OrMask := PCardinal(@Item.DataOr[Offset])^ and AND_VALUES[ByteCount];
  if (OrMask <> 0) then Result := Result + ' or ' + HexConst(OrMask, ByteCount);
end;


{ TSerializeOptions }

function TSerializeOptions.Add(const S: UnicodeString): NativeUInt;
begin
  Result := FCount;
  Inc(FCount);
  SetLength(FItems, FCount);
  FItems[Result] := S;
end;

procedure TSerializeOptions.Delete(const AFrom, ACount: NativeUInt);
var
  L, i: NativeUInt;
begin
  L := FCount;
  if (AFrom < L) and (ACount <> 0) then
  begin
    Dec(L, AFrom);
    if (L <= ACount) then
    begin
      L := AFrom;
    end else
    begin
      Inc(L, AFrom);
      Dec(L, ACount);

      for i := 0 to (L - AFrom - 1) do
        FItems[AFrom + i] := FItems[AFrom + ACount + i];
    end;

    FCount := L;
    SetLength(FItems, L);
  end;
end;

procedure TSerializeOptions.SetEncoding(const Value: Word);
begin
  if (Value <> CODEPAGE_UTF8) and (Value <> CODEPAGE_UTF16) and
    (Value <> CODEPAGE_UTF32) then
  begin
    if (not UniConvIsSBCS(Value)) then
      raise Exception.CreateFmt('Unsupported encoding "%d"', [Value]);
  end;

  FEncoding := Value;
end;

function TSerializeOptions.CachedStringType: UnicodeString;
begin
  case FEncoding of
    CODEPAGE_UTF16: Result := 'UTF16String';
    CODEPAGE_UTF32: Result := 'UTF32String';
  else
    Result := 'ByteString';
  end;
end;

procedure TSerializeOptions.FillCharactersParams(const AFuncParam,
  ACharsParam, ALengthParam: UnicodeString);
begin
  FuncParam := AFuncParam;
  CharsParam := ACharsParam;
  LengthParam := ALengthParam;
end;

procedure TSerializeOptions.FillFuncParams(const AFuncName, AEnumTypeName,
  APrefix: UnicodeString);
begin
  FuncName := AFuncName;
  EnumTypeName := AEnumTypeName;
  Prefix := APrefix;
end;

function TSerializeOptions.ParseParams(var Params: TOptionParams;
  const S: UnicodeString): Boolean;
var
  P: NativeInt;
  Str: UTF16String;

  function ParseParam(var O: UnicodeString): Boolean;
  begin
    Result := True;

    P := Str.CharPos(':');
    if (P = 0) then
    begin
      Result := False;
      Exit;
    end;

    Inc(Params.Count);
    if (P < 0) then
    begin
      O := Str.ToUnicodeString;
      Str.Length := 0;
      Exit;
    end;

    O := Str.SubString(P).ToUnicodeString;
    Str.Offset(P + 1);
  end;
begin
  Result := False;
  Params.Count := 0;
  Str.Assign(S);

  P := Str.CharPos('"');
  if (P < 0) then
  begin
    Params.Name := Str.ToUnicodeString;
    Result := True;
    Exit;
  end else
  begin
    if (P = 0) then Exit;
    Params.Name := Str.SubString(0, P).ToUnicodeString;

    Str.Offset(P);
    P := Str.CharPos('"');
    if (P < 0) or (NativeUInt(P) <> Str.Length - 1) then Exit;
    Str.Length := Str.Length - 1;

    if (not ParseParam(Params.O1)) then Exit;
    if (Str.Length <> 0) then
    begin
      if (not ParseParam(Params.O2)) then Exit;

      if (Str.Length <> 0) then
      begin
        if (not ParseParam(Params.O3)) then Exit;
        if (Str.Length <> 0) then Exit;
      end;
    end;

    Result := True;
  end;
end;

function TSerializeOptions.ParseOption(const S: UnicodeString): Boolean;
label
  func_params;
var
  Params: TOptionParams;
  A: AnsiString;
  Enc: Integer;
begin
  Result := False;
  if (not ParseParams(Params, S)) then Exit;

  with TMemoryItems(Pointer(S)^) do
  case Length(S) of
   2: case (Cardinals[0] or $00200000) of
        $0066002D:
        begin
          // "-f"
          UseFuncHeaders := True;
          goto func_params;
        end;
        $0069002D: IgnoreCase := True; // "-i"
        $006F002D:
        begin
          // "-o"
          case Params.Count of
            1: OutFileName := Params.O1;
            2: OutFileName := Params.O1 + Params.O2;
          else
            Exit;
          end;
        end;
        $0070002D:
        begin
          // "-p"
          case Params.Count of
            1: FillCharactersParams('const ' + Params.O1 + ': ' + CachedStringType, Params.O1 + '.Chars', Params.O1 + '.Length');
            2: FillCharactersParams('const Unknown', Params.O1, Params.O2);
          else
            Exit;
          end;
        end;
      end;
   3: if (Cardinals[0] or $00200000 = $0066002D) and (Words[2] or $0020 = $006E) then
      begin
        // "-fn"
        UseFuncHeaders := False;
        func_params:
        case Params.Count of
          2: FillFuncParams(Params.O1, '', Params.O2);
          3: FillFuncParams(Params.O1, Params.O2, Params.O3);
        else
          Exit;
        end;
      end;
  else
    A := AnsiString(S);
    Enc := -1;

    with TMemoryItems(Pointer(A)^) do
    case Length(A) of
     4: case (Cardinals[0] and $ffffff) of
          $36382D: if (Bytes[3] = $36) then Enc := 866; // "-866"
          $37382D: if (Bytes[3] = $34) then Enc := 874; // "-874"
          $61722D,$61522D,$41722D,$41522D: if (Bytes[3] or $20 = $77) then Enc := CODEPAGE_RAWDATA; // "-raw"
        end;
     5: case (Cardinals[0] and $ffffff) of
          $32312D: // "-1250","-1251","-1252","-1253","-1254","-1255","-1256","-1257","-1258"
          case (Cardinals1[1]) of
            $3035: Enc := 1250; // "-1250"
            $3135: Enc := 1251; // "-1251"
            $3235: Enc := 1252; // "-1252"
            $3335: Enc := 1253; // "-1253"
            $3435: Enc := 1254; // "-1254"
            $3535: Enc := 1255; // "-1255"
            $3635: Enc := 1256; // "-1256"
            $3735: Enc := 1257; // "-1257"
            $3835: Enc := 1258; // "-1258"
          end;
          $6E612D,$6E412D,$4E612D,$4E412D: if (Words1[1] or $2020 = $6973) then Enc := 0; // "-ansi"
          $73752D,$73552D,$53752D,$53552D: if (Words1[1] or $2020 = $7265) then Enc := CODEPAGE_USERDEFINED; // "-user"
          $74752D,$74552D,$54752D,$54552D: if (Words1[1] or $0020 = $3866) then Enc := CODEPAGE_UTF8; // "-utf8"
        end;
     6: case (Cardinals[0] and $ffffff) of
          $30312D: // "-10000","-10007"
          case (Cardinals2[0] shr 8) of
            $303030: Enc := 10000; // "-10000"
            $373030: Enc := 10007; // "-10007"
          end;
          $30322D: if (Cardinals2[0] shr 8 = $363638) then Enc := 20866; // "-20866"
          $31322D: if (Cardinals2[0] shr 8 = $363638) then Enc := 21866; // "-21866"
          $38322D: // "-28592","-28593","-28594","-28595","-28596","-28597","-28598","-28600","-28603","-28604","-28605","-28606"
          case (Cardinals2[0] shr 8) of
            $323935: Enc := 28592; // "-28592"
            $333935: Enc := 28593; // "-28593"
            $343935: Enc := 28594; // "-28594"
            $353935: Enc := 28595; // "-28595"
            $363935: Enc := 28596; // "-28596"
            $373935: Enc := 28597; // "-28597"
            $383935: Enc := 28598; // "-28598"
            $303036: Enc := 28600; // "-28600"
            $333036: Enc := 28603; // "-28603"
            $343036: Enc := 28604; // "-28604"
            $353036: Enc := 28605; // "-28605"
            $363036: Enc := 28606; // "-28606"
          end;
          $74752D,$74552D,$54752D,$54552D: // "-utf16","-utf32"
          case (Cardinals2[0] shr 8 or $000020) of
            $363166: Enc := CODEPAGE_UTF16; // "-utf16"
            $323366: Enc := CODEPAGE_UTF32; // "-utf32"
          end;
        end;
    end;

    if (Enc < 0) then Exit;
    Encoding := Enc;
  end;

  Result := True;
end;

procedure TSerializeOptions.ParseOptionsLine(const S: UTF16String);
var
  Str: UTF16String;
  Buf: UnicodeString;
  L: NativeUInt;
begin
  Str := S;
  while (not Str.Trim) do
  begin
    L := 0;
    while (L < Str.Length) and (Str.Chars[L] <= ' ') do
    begin
      Inc(L);
    end;

    Buf := Str.SubString(L).ToUnicodeString;
    if (not ParseOption(Buf)) then
      raise Exception.CreateFmt('Unknown file parameter "%s"', [Buf]);

    Str.Offset(L);
  end;
end;

procedure TSerializeOptions.AddFromFile(const FileName: string;
  const OptionsLine: Boolean);
var
  Text: TUTF16TextReader;
  S: UTF16String;
begin
  Text := TUTF16TextReader.CreateFromFile(FileName);
  try
    if (OptionsLine) and (Text.Readln(S)) then
      ParseOptionsLine(S);

    while (Text.Readln(S)) do
      Add(S.ToUnicodeString);
  finally
    Text.Free;
  end;
end;


{ TSerializer }

procedure TSerializer.InspecOptions;
begin
  FStringKind := csByte;
  case FOptions.Encoding of
    CODEPAGE_UTF16: FStringKind := csUTF16;
    CODEPAGE_UTF32: FStringKind := csUTF32;
  end;
  FCharSize := 1 shl SHIFT_VALUES[FStringKind];
  FIsFunction := (FOptions.FuncName <> '');
  FIsConsts := (FIsFunction) and (FOptions.EnumTypeName = '');

  if (FOptions.FCharsParam = '') then
    raise Exception.Create('CharsParam not defined');

  if (FOptions.FLengthParam = '') then
    raise Exception.Create('LengthParam not defined');

  if (FOptions.Count = 0) then
    raise Exception.Create('Identifier list not defined');
end;

function TSerializer.FunctionValue(const Identifier: UnicodeString): UnicodeString;
var
  i, Number: NativeUInt;
  Base: UnicodeString;
  Found: Boolean;
begin
  if (Identifier = '') then
  begin
    Result := 'None';
  end else
  begin
    case Identifier[1] of
      '0'..'9': Result := '_';
    else
      Result := '';
    end;

    for i := 1 to Length(Identifier) do
    case Identifier[i] of
      'a'..'z', 'A'..'Z', '0'..'9', '_':
      begin
        // Ok
        Result := Result + Identifier[i];
      end;
      (*
         Cyrillic characters conversion
      *)
      #$430: Result := Result + 'a';
      #$431: Result := Result + 'b';
      #$432: Result := Result + 'v';
      #$433: Result := Result + 'g';
      #$434: Result := Result + 'd';
      #$435: Result := Result + 'e';
      #$451: Result := Result + 'yo';
      #$436: Result := Result + 'zh';
      #$437: Result := Result + 'z';
      #$438: Result := Result + 'i';
      #$439: Result := Result + 'j';
      #$43A: Result := Result + 'k';
      #$43B: Result := Result + 'l';
      #$43C: Result := Result + 'm';
      #$43D: Result := Result + 'n';
      #$43E: Result := Result + 'o';
      #$43F: Result := Result + 'p';
      #$440: Result := Result + 'r';
      #$441: Result := Result + 's';
      #$442: Result := Result + 't';
      #$443: Result := Result + 'u';
      #$444: Result := Result + 'f';
      #$445: Result := Result + 'h';
      #$446: Result := Result + 'c';
      #$447: Result := Result + 'ch';
      #$448: Result := Result + 'sh';
      #$449: Result := Result + 'sch';
      #$44A: Result := Result + 'j';
      #$44B: Result := Result + 'i';
      #$44C: Result := Result + 'j';
      #$44D: Result := Result + 'e';
      #$44E: Result := Result + 'yu';
      #$44F: Result := Result + 'ya';
      #$410: Result := Result + 'A';
      #$411: Result := Result + 'B';
      #$412: Result := Result + 'V';
      #$413: Result := Result + 'G';
      #$414: Result := Result + 'D';
      #$415: Result := Result + 'E';
      #$401: Result := Result + 'Yo';
      #$416: Result := Result + 'Zh';
      #$417: Result := Result + 'Z';
      #$418: Result := Result + 'I';
      #$419: Result := Result + 'J';
      #$41A: Result := Result + 'K';
      #$41B: Result := Result + 'L';
      #$41C: Result := Result + 'M';
      #$41D: Result := Result + 'N';
      #$41E: Result := Result + 'O';
      #$41F: Result := Result + 'P';
      #$420: Result := Result + 'R';
      #$421: Result := Result + 'S';
      #$422: Result := Result + 'T';
      #$423: Result := Result + 'U';
      #$424: Result := Result + 'F';
      #$425: Result := Result + 'H';
      #$426: Result := Result + 'C';
      #$427: Result := Result + 'Ch';
      #$428: Result := Result + 'Sh';
      #$429: Result := Result + 'Sch';
      #$42A: Result := Result + 'J';
      #$42B: Result := Result + 'I';
      #$42C: Result := Result + 'J';
      #$42D: Result := Result + 'E';
      #$42E: Result := Result + 'Yu';
      #$42F: Result := Result + 'Ya';
    else
      Result := Result + '_';
    end;
  end;

  // include prefix, char case
  if (FIsConsts) then
  begin
    Result := utf16_from_utf16_upper(FOptions.Prefix + Result);
  end else
  begin
    Result[1] := UNICONV_CHARCASE.UPPER[Result[1]];
    Result := FOptions.Prefix + Result;
  end;

  // duplicates, enumerate
  if (FFunctionValues <> nil) then
  begin
    Base := Result;
    Number := 0;

    repeat
      Found := False;

      for i := 0 to Length(FFunctionValues) - 1 do
      if (utf16_equal_utf16_ignorecase(Base, FFunctionValues[i])) then
      begin
        Found := True;
        Inc(Number);
        Base := Result + IntToStr(Number);
        Break;
      end;
    until (not Found);

    Result := Base;
  end;

  // add
  i := Length(FFunctionValues);
  SetLength(FFunctionValues, i + 1);
  FFunctionValues[i] := Result;
end;

procedure TSerializer.AddLine;
begin
  AddLine('');
end;

procedure TSerializer.AddLine(const S: UnicodeString);
var
  Index: NativeUInt;
begin
  Index := FLinesCount;
  Inc(FLinesCount);
  SetLength(FLines^, FLinesCount);
  FLines^[Index] := S;
end;

procedure TSerializer.AddLineFmt(const FmtStr: UnicodeString;
  const Args: array of const);
begin
  AddLine(UnicodeFormat(FmtStr, Args));
end;

procedure TSerializer.TextBufferClear;
begin
  FTextBuffer := '';
end;

procedure TSerializer.TextBufferFlush;
begin
  if (FTextBuffer <> '') then
  begin
    AddLine(FTextBuffer);
    TextBufferClear;
  end;
end;

procedure TSerializer.TextBufferInclude(const Level: NativeUInt;
  const S: UnicodeString);
var
  L1, L2: NativeUInt;
begin
  L1 := Length(FTextBuffer);
  L2 := Length(S);
  if (L2 = 0) then Exit;

  if (L1 <> 0) and (L1 - Level + L2 >= 90) then
  begin
    TextBufferFlush;
    TextBufferInit(Level, S);
  end else
  begin
    FTextBuffer := FTextBuffer + S;
  end;
end;

procedure TSerializer.TextBufferIncludeFmt(const Level: NativeUInt;
  const FmtStr: UnicodeString; const Args: array of const);
begin
  TextBufferInclude(Level, UnicodeFormat(FmtStr, Args));
end;

procedure TSerializer.TextBufferInit(const Level: NativeUInt;
  const S: UnicodeString);
var
  i: NativeUInt;
begin
  TextBufferClear;

  if (Level <> 0) then
  begin
    SetLength(FTextBuffer, Level * 2);
    for i := 1 to Level * 2 do
      FTextBuffer[i] := #32;
  end;

  FTextBuffer := FTextBuffer + S;
end;

procedure TSerializer.TextBufferInitLength(const Level: NativeUInt;
  const Value: NativeUInt);
begin
  TextBufferClear;
  FTextBuffer := UnicodeFormat('%*d: ', [Level * 2 - 2, Value]);
end;

procedure TSerializer.TextBufferInitFmt(const Level: NativeUInt;
  const FmtStr: UnicodeString; const Args: array of const);
begin
  TextBufferInit(Level, UnicodeFormat(FmtStr, Args));
end;

procedure TSerializer.TextBufferIncludeIfThenLine(const Level: NativeUInt;
  const Item: PIdentifier; Offset, ByteCount: NativeUInt);
const
  NONE_IF: array[Boolean] of string = ('', 'if ');
  AND_THEN: array[Boolean] of string = ('and', 'then');
var
  NeedIf: Boolean;
  Buf: UnicodeString;
  Count: NativeUInt;
  OrMask: Cardinal;
begin
  NeedIf := True;
  while (ByteCount <> 0) do
  begin
    Count := ByteCount;
    if (Count > SizeOf(Cardinal)) then Count := SizeOf(Cardinal);
    Buf := UseDataMasked(Item, Offset, Count);

    OrMask := PCardinal(@Item.DataOr[Offset])^ and AND_VALUES[Count];
    Buf := Buf + ' = ' + HexConst(PCardinal(@Item.Data1[Offset])^ or OrMask, Count);
    Inc(Offset, Count);
    Dec(ByteCount, Count);

    TextBufferIncludeFmt(Level, '%s(%s) %s ',
    [
      NONE_IF[NeedIf], Buf, AND_THEN[ByteCount = 0]
    ]);
    NeedIf := False;
  end;
end;

procedure TSerializer.TextBufferIncludeComments(const Items: PIdentifierItems;
  const Count: NativeUInt);
var
  i: NativeUInt;
  Item: PIdentifier;
  BufferLength, L: NativeUInt;
begin
  FTextBuffer := FTextBuffer + '// ';
  BufferLength := Length(FTextBuffer);

  for i := 1 to Count do
  begin
    Item := @Items[i - 1];
    L := Length(Item.Info.Comment);
    if (i <> 1) then
    begin
      FTextBuffer := FTextBuffer + ', ';
      Inc(BufferLength, 2);
    end;

    if (i = 1) or (i = Count) or (BufferLength + L < 90) then
    begin
      FTextBuffer := FTextBuffer + Item.Info.Comment;
      Inc(BufferLength, L);
    end else
    begin
      FTextBuffer := FTextBuffer + '...';
      Break;
    end;
  end;
end;

function TSerializer.Process(const Options: TSerializeOptions): TUnicodeStrings;
var
  i: NativeUInt;
  Info: TIdentifierInfo;
  List: TIdentifierList;
  Buf: UnicodeString;
  Ascii: Boolean;

  Text: TUTF16TextWriter;
  DefaultByteEncoding: Word;
begin
  Result := nil;
  FLines := @Result;
  FLinesCount := 0;
  FOptions := @Options;
  InspecOptions;

  // function values
  FFunctionValues := nil;
  if (FIsFunction) then
  begin
    FunctionValue('Unknown');
  end;

  // parse each identifier line
  for i := 0 to Options.Count - 1 do
  begin
    if (not Info.Parse(Options.Items[i])) then Continue;

    Buf := '';
    if (not Info.MarkerReference) and (FIsConsts) then
      Buf := FunctionValue(Info.Value);

    AddIdentifier(List, Info, Options.Encoding, Options.IgnoreCase, Buf);
  end;
  if (List = nil) then
    raise Exception.Create('Identifier list not defined');

  // type header
  if (FIsFunction) and (Options.UseFuncHeaders) then
  begin
    if (FIsConsts) then
    begin
      Self.AddLine('const');
    end else
    begin
      Self.AddLine('type');
    end;

    if (FIsConsts) then
    begin
      for i := 0 to Length(FFunctionValues) - 1 do
        Self.AddLineFmt('  %s = %d;', [FFunctionValues[i], i]);
    end else
    begin
      TextBufferInit(1, Options.EnumTypeName + ' = (');
      for i := 0 to Length(FFunctionValues) - 1 do
        TextBufferIncludeFmt(1, '%s, ', [FFunctionValues[i]]);

      FTextBuffer[Length(FTextBuffer) - 1] := ')';
      FTextBuffer[Length(FTextBuffer)] := ';';
      TextBufferFlush;
    end;
  end;

  // function Header
  if (FIsFunction) and (Options.UseFuncHeaders) then
  begin
    Buf := Options.EnumTypeName;
    if (FIsConsts) then Buf := 'Cardinal';

    Self.AddLine('function ' + Options.FuncName + '(' + Options.FuncParam + '): ' + Buf + ';');
    Self.AddLine('begin');
  end;

  // default value
  if (FIsFunction) then
  begin
    Self.AddLine('  // default value');
    Self.AddLineFmt('  Result := %s;', [FFunctionValues[0]]);
    Self.AddLine;
  end;

  // serialize comment
  begin
    case Options.Encoding of
       CODEPAGE_UTF8: Buf := 'utf8';
      CODEPAGE_UTF16: Buf := 'utf16';
      CODEPAGE_UTF32: Buf := 'utf32';
    CODEPAGE_RAWDATA: Buf := 'raw';
CODEPAGE_USERDEFINED: Buf := 'user';
                   0: Buf := 'ansi';
    else
      Buf := UnicodeFormat('cp%d', [Options.Encoding]);
    end;

    Ascii := True;
    for i := 0 to Length(List) - 1 do
    if (not List[i].Info.IsAscii) then
    begin
      Ascii := False;
      Break;
    end;

    if (Ascii) then
    begin
      if (FStringKind = csByte) then
      begin
        Buf := 'byte ascii';
      end else
      begin
        Buf := Buf + ' ascii';
      end;
    end;

    if (Options.IgnoreCase) then
      Buf := Buf + ', ignore case';

    Self.AddLineFmt('  // %s', [Buf]);
  end;

  // case start
  Self.AddLineFmt('  with PMemoryItems(%s)^ do', [Options.CharsParam]);

  // recursion
  SetLength(FCasesBuffer, Length(List));
  SortIdentifiers(List, 0, DefaultIdentifierComparator);
  Self.WriteIdentifiers(Pointer(List), Length(List), 0, 1, 1, False);

  // case finish
  Self.AddLine('  end;');
  if (FIsFunction) and (Options.UseFuncHeaders) then
    Self.AddLine('end;');

  // save lines to file
  if (Options.OutFileName <> '') then
  begin
    DefaultByteEncoding := 0;
    if (FStringKind = csByte) then DefaultByteEncoding := Options.Encoding;
    Text := TUTF16TextWriter.CreateFromFile(Options.OutFileName, bomUTF8, DefaultByteEncoding);
    try
      for i := 1 to FLinesCount do
      begin
        if (i <> 1) then Text.CRLF;
        Text.WriteData(Pointer(Result[i - 1])^, Length(Result[i - 1]) * SizeOf(UnicodeChar));
      end;
    finally
      Text.Free;
    end;
  end;
end;

function TSerializer.CheckCases(const Items: PIdentifierItems;
  const Count, Offset, ByteCount, OrMask: Cardinal;
  const KnownLength: Boolean; var CheckedCount, CaseCount: NativeUInt): NativeUInt;
label
  fail;
var
  i, j: NativeUInt;
  Item: PIdentifier;
  AndConst: Cardinal;

  v1, v2: Cardinal;
  LocalCases: array[0..3] of Cardinal;
  LocalCaseCount: NativeUInt;
  LocalCaseIndexes: array[0..3] of NativeInt;

  ChildsCount: NativeUInt;
  n: NativeInt;

  function ChildIndex(const Value: Cardinal): NativeInt;
  var
    k: NativeUInt;
  begin
    for Result := 0 to ChildsCount - 1 do
    with FCasesBuffer[Result] do
    begin
      for k := 0 to Count - 1 do
      if (Values[k] = Value) then Exit;
    end;

    Result := -1;
  end;

begin
  ChildsCount := 0;
  CheckedCount := 0;
  CaseCount := 0;
  AndConst := AND_VALUES[ByteCount];

  for i := 0 to NativeUInt(Count) - 1 do
  begin
    Item := @Items[i];
    if (Item.DataSize < Offset + ByteCount) then
    begin
      if (KnownLength) then goto fail;
      Continue;
    end;
    Inc(CheckedCount);

    // basic alternatives
    v1 := (PCardinal(@Item.Data1[Offset])^ or OrMask) and AndConst;
    v2 := (PCardinal(@Item.Data2[Offset])^ or OrMask) and AndConst;

    // case alternatives for Item/ByteCount (max = 4)
    LocalCaseCount := 1;
    LocalCases[0] := v1;
    if (v1 <> v2) then
    for j := 0 to 3 do
    if (T4Bytes(v1)[j] <> T4Bytes(v2)[j]) then
    begin
      if (LocalCaseCount = 1) then
      begin
        LocalCaseCount := 2;
        LocalCases[1] := LocalCases[0];
        T4Bytes(LocalCases[1])[j] := T4Bytes(v2)[j];
      end else
      if (LocalCaseCount = 2) then
      begin
        LocalCaseCount := 4;
        LocalCases[2] := LocalCases[0];
        LocalCases[3] := LocalCases[1];
        T4Bytes(LocalCases[2])[j] := T4Bytes(v2)[j];
        T4Bytes(LocalCases[3])[j] := T4Bytes(v2)[j];
      end else
      goto fail;
    end;

    // find child group
    for j := 0 to LocalCaseCount - 1 do
    begin
      n := ChildIndex(LocalCases[j]);
      LocalCaseIndexes[j] := n;

      if (n >= 0) and (n <> NativeInt(ChildsCount) - 1) then goto fail;
      if (j <> 0) and (LocalCaseIndexes[j - 1] <> n) then goto fail;
    end;

    // add if not found
    n := LocalCaseIndexes[0];
    if (n < 0) then
    begin
      n := ChildsCount;
      Inc(ChildsCount);

      Inc(CaseCount, LocalCaseCount);
      FCasesBuffer[n].Count := LocalCaseCount;
      Move(LocalCases, FCasesBuffer[n].Values, SizeOf(LocalCases));
    end;

    // child number
    Item.CasesIndex := n;
  end;

// done
  Result := ChildsCount;
  Exit;
fail:
  CheckedCount := 0;
  CaseCount := 0;
  Result := 0;
end;

function TSerializer.CheckCases(const Items: PIdentifierItems;
  const Count, Offset: NativeUInt; const KnownLength: Boolean): TWholeCasesInfo;
var
  i: NativeUInt;
  OrMask: Cardinal;
begin
  // detect or mask
  OrMask := 0;
  if (FOptions.IgnoreCase) then
  begin
    OrMask := PCardinal(Items[0].DataOr[Offset])^;
    for i := 1 to Count - 1 do
    begin
      OrMask := OrMask and PCardinal(@Items[i].DataOr[Offset])^;
      if (OrMask = 0) then Break;
    end;
  end;

  // best case bytes/or mask
  FillChar(Result, SizeOf(Result), #0);
  for i := 1 to 4 do
  begin
    Result[i].ChildCount := CheckCases(Items, Count, Offset, i, OrMask,
      KnownLength, Result[i].CheckedCount, Result[i].CaseCount);

    if (Result[i].ChildCount <> 0) then
    begin
      Result[i].ByteCount := i;
      Result[i].OrMask := OrMask and AND_VALUES[i];
    end;
  end;
  if (Result[1].CaseCount = 0) then
  raise InternalException;
end;

function TSerializer.CalculateBestCases(const Items: PIdentifierItems;
  const Count, Offset: NativeUInt; const KnownLength: Boolean): TCasesInfo;
const
  COST_MUL: array[2..4] of Double = (1 + 0.20, 1 + 0.40, 1 + 0.50);

type
  TBuffer = array[1..SizeOf(TIdentifier)] of Byte;

  function CasesCost(const Cases: TCasesInfo): NativeUInt;
  begin
    Result := Cases.CaseCount + (Count - Cases.CheckedCount);
  end;

var
  i, j: NativeUInt;
  BestCases, BestValue, Value: NativeUInt;
  WholeCases: TWholeCasesInfo;
  MovedCount: NativeUInt;
  Temp: TBuffer;
begin
  WholeCases := CheckCases(Items, Count, Offset, KnownLength);

  BestCases := 1;
  BestValue := CasesCost(WholeCases[1]);
  for i := 2 to 4 do
  begin
    Value := Round(CasesCost(WholeCases[i]) / COST_MUL[i]);

    if (Value <= BestValue) then
    begin
      if (not KnownLength) and (i >= FCharSize) and
        (i mod FCharSize <> 0) then Continue;

      BestCases := i;
      BestValue := Value;
    end;
  end;

  // best cases
  Result := WholeCases[BestCases];

  // initialize case indexes
  CheckCases(Items, Count, Offset, BestCases, Result.OrMask, KnownLength, {Buffers}BestValue, Value);

  // move and sort unchecked identifiers
  if (Result.CheckedCount = Count) then Exit;
  MovedCount := 0;
  for i := 0 to Count - 1 do
  if (Items[i].DataSize < Result.ByteCount) then
  begin
    if (i <> 0) then
    begin
      Temp := TBuffer(Items[i]);
        for j := i - 1 downto MovedCount do
        TBuffer(Items[j + 1]) := TBuffer(Items[j]);
      TBuffer(Items[MovedCount]) := Temp;
    end;
    Inc(MovedCount);
  end;
  if (MovedCount <> (Count - Result.CheckedCount)) then
    raise InternalException;
end;

procedure TSerializer.InspectIdentifiers(const Items: PIdentifierItems;
  const Count, Offset: NativeUInt; const KnownLength: Boolean;
  var MinDataSize, MaxDataSize, SameDataSize: NativeUInt);
label
  next;
var
  i, Offs: NativeUInt;
  Item: PIdentifier;
  WholeCases: TWholeCasesInfo;
begin
  MinDataSize := High(NativeUInt);
  MaxDataSize := 0;
  for i := 0 to Count - 1 do
  begin
    Item := @Items[i];
    if (Item.DataSize > MaxDataSize) then MaxDataSize := Item.DataSize;
    if (Item.DataSize < MinDataSize) then MinDataSize := Item.DataSize;
  end;
  Dec(MinDataSize, Offset);
  Dec(MaxDataSize, Offset);

  if (Count = 1) then
  begin
    SameDataSize := MinDataSize{=MaxDataSize};
    Exit;
  end;

  // same data size
  Offs := Offset;
  while (Offs <> Offset + MinDataSize) do
  begin
    WholeCases := CheckCases(Items, Count, Offs, True);
    for i := 4 downto 1 do
    if (WholeCases[i].CaseCount = 1) then
    begin
      Inc(Offs, i);
      goto next;
    end;
    Break;

  next:
  end;
  SameDataSize := Offset - Offs;
  if (not KnownLength) and (SameDataSize > FCharSize) then
    SameDataSize := SameDataSize and -FCharSize;
end;

// identifiers recursion
procedure TSerializer.WriteCaseIdentifiers(const Items: PIdentifierItems;
  const Count, Offset, Level: NativeUInt; const BestCases: TCasesInfo;
  const KnownLength: Boolean);
var
  i, ChildCount: NativeUInt;
  Value: Cardinal;
begin
  TextBufferIncludeFmt(Level, 'case (%s) of', [UseDataMasked(@Items[0], Offset, BestCases.ByteCount)]);
  TextBufferIncludeComments(Items, Count);
  TextBufferFlush;
  begin
    i := 0;
    while (i < Count) do
    begin
      ChildCount := 1;
      while (i + ChildCount < Count) and
        (Items[i].DataSize = Items[i + ChildCount].DataSize) do Inc(ChildCount);

      // value
      Value := PCardinal(@Items[i].Data1[Offset])^ and AND_VALUES[BestCases.ByteCount];
      Value := Value or BestCases.OrMask;
      TextBufferFlush;
      TextBufferInitFmt(Level + 1 + BestCases.ByteCount,
        '%s: ', [HexConst(Value, BestCases.ByteCount)]);

      // childs
      WriteIdentifiers(PIdentifierItems(@Items[i]), ChildCount, Offset + BestCases.ByteCount,
        Level + 1, Level + 1 + BestCases.ByteCount, KnownLength);
      Inc(i, ChildCount);
    end;
  end;
  TextBufferFlush;
  TextBufferInit(Level, 'end;');
  TextBufferFlush;
end;

procedure TSerializer.WriteLengthIdentifiers(const Items: PIdentifierItems;
  const Count, Offset, Level: NativeUInt);
var
  i, ChildCount: NativeUInt;
begin
  // sort
  SortIdentifiers(Items, Count, Offset, DataSizeIdentifierComparator);

  // items
  TextBufferFlush;
  TextBufferInitFmt(Level, 'case %s of', [FOptions.FLengthParam]);
  if (Level <> 1) then TextBufferIncludeComments(Items, Count);
  TextBufferFlush;
  i := 0;
  while (i < Count) do
  begin
    ChildCount := 1;
    while (i + ChildCount < Count) and
      (Items[i].DataSize = Items[i + ChildCount].DataSize) do Inc(ChildCount);

    // length:
    TextBufferInitLength(Level + 1, Items[i].DataSize div FCharSize);

    // childs
    WriteIdentifiers(PIdentifierItems(@Items[i]), ChildCount, Offset,
      Level + 1, Level + 1, True);
    Inc(i, ChildCount);
  end;
  TextBufferFlush;
  TextBufferInit(Level, 'end;');
  TextBufferFlush;
end;

// identifiers recursion
procedure TSerializer.WriteIdentifiers(const Items: PIdentifierItems;
  const Count, Offset, LargeCodeLevel, Level: NativeUInt; KnownLength: Boolean);
var
  i, UncheckedCount: NativeUInt;
  Item: PIdentifier;
  MinDataSize, MaxDataSize, SameDataSize: NativeUInt;
  CodeLines: NativeUInt;
  BestCases: TCasesInfo;
begin
  InspectIdentifiers(Items, Count, Offset, KnownLength, MinDataSize, MaxDataSize, SameDataSize);

  // same (one) length --> known length
  if (MinDataSize = MaxDataSize) and (not KnownLength) then
  begin
    TextBufferIncludeFmt(Level, 'if (%s = %d) then',
    [
      FOptions.FLengthParam,
      Items[0].DataSize div FCharSize
    ]);
    TextBufferFlush;
    KnownLength := True;
  end;

  // final identifier
  if (Count = 1) then
  begin
    Item := @Items[0];
    TextBufferIncludeIfThenLine(Level, Item, Offset, SameDataSize);

    CodeLines := Length(Item.Info.Code);
    if (CodeLines = 1) then
    begin
      // single line
      TextBufferIncludeFmt(Level, '%s // %s', [Item.Info.Code[0], Item.Info.Comment]);
      TextBufferFlush;
    end else
    begin
      // multi lines
      TextBufferFlush;
      TextBufferInit(LargeCodeLevel, 'begin');
      TextBufferFlush;
      TextBufferIncludeFmt(LargeCodeLevel, '  // %s', [Item.Info.Comment]);
      TextBufferFlush;

      if (CodeLines = 0) then
      begin
        AddLine;
      end else
      begin
        for i := 0 to CodeLines - 1 do
        begin
          TextBufferInclude(LargeCodeLevel + 1, Item.Info.Code[i]);
          TextBufferFlush;
        end;
      end;

      TextBufferInit(LargeCodeLevel, 'end;');
      TextBufferFlush;
    end;

    Exit;
  end;

  // emmit childs
  BestCases := CalculateBestCases(Items, Count, Offset, KnownLength);
  if (BestCases.ByteCount >= FCharSize) then
  begin
    if ({usually 0}SameDataSize < FCharSize) then
    begin
      // check bytes count
      if (not KnownLength) then
      begin
        TextBufferIncludeFmt(Level, 'if (%s >= %d) then',
        [
          FOptions.FLengthParam,
          (Offset + BestCases.ByteCount) div FCharSize
        ]);
        TextBufferFlush;
      end;

      // cases and unchecked lengths
      UncheckedCount := Count - BestCases.CheckedCount;
      if (UncheckedCount <> 0) then
      begin
        TextBufferInit(Level, 'begin');
        TextBufferFlush;
          WriteCaseIdentifiers(PIdentifierItems(@Items[UncheckedCount]),
            Count - UncheckedCount, Offset, Level + 1, BestCases, KnownLength);
        TextBufferInit(Level, 'end else');
        TextBufferFlush;
        WriteLengthIdentifiers(Items, UncheckedCount, Offset, Level);
      end else
      begin
        WriteCaseIdentifiers(Items, Count, Offset, Level, BestCases, KnownLength);
      end;
    end else
    begin
      // same data size
      if (not KnownLength) then
      begin
        TextBufferIncludeFmt(Level, 'if (%s >= %d) then',
        [
          FOptions.FLengthParam,
          (Offset + SameDataSize) div FCharSize
        ]);
        TextBufferFlush;
      end;

      // same data
      Item := @Items[0];
      TextBufferIncludeIfThenLine(Level, Item, Offset, SameDataSize);
      TextBufferFlush;

      // childs
      WriteIdentifiers(Items, Count, Offset + SameDataSize, LargeCodeLevel, Level, KnownLength);
    end;
  end else
  if (KnownLength) then
  begin
    // cases
    WriteCaseIdentifiers(Items, Count, Offset, Level, BestCases, True);
  end else
  begin
    // length and cases
    WriteLengthIdentifiers(Items, Count, Offset, Level);
  end;
end;


end.
