# custom grep language NeverWinterNightsText (nwnt) support for gff reading/writing

import tables, strutils, streams, parseutils, base64, algorithm, sequtils
import neverwinter/gff, neverwinter/util, neverwinter/languages

####### Helper Procs #######

proc manageEscapesToText(str: string): string =
  result = str.multiReplace([("\n","\\n"),("\r","\\r")])

proc manageEscapesToGff(str: string): string =
  result = str.multiReplace([("\\n","\n"),("\\r","\r")])

iterator sortedPairs(s: GffStruct): tuple[key: string, value: GffField] =
  let fields = toSeq(s.fields.pairs).sorted
  for key, value in fields.items:
    yield (key, value)

####### Actual-work Procs #######

proc nwntFromGffStruct*(s: GffStruct, floatPrecision: int, namePrefix: string = ""): seq[array[3, string]] =
  ##Transforms the given GFFStruct into a sequence of nwnt
  if s of GffRoot:
    result.add(["data_type", "", $s.GffRoot.fileType])

  for lable, gffValue in s.sortedPairs:
    let
      name = namePrefix & lable
      kind = '$' & $gffValue.fieldKind
    var
      value: string
      fieldHandled: bool

    case gffValue.fieldKind:
    of GffFieldKind.Byte: value = $gffValue.getValue(GffByte).int
    of GffFieldKind.Char: value = $gffValue.getValue(GffChar).int
    of GffFieldKind.Word: value = $gffValue.getValue(GffWord).int
    of GffFieldKind.Short: value = $gffValue.getValue(GffShort).int
    of GffFieldKind.Dword: value = $gffValue.getValue(GffDword).int
    of GffFieldKind.Int: value = $gffValue.getValue(GffInt).int
    of GffFieldKind.Float: value = $gffValue.getValue(GffFloat).float.formatFloat(ffDecimal, floatPrecision)
    of GffFieldKind.Dword64: value = $gffValue.getValue(GffDword64).int64
    of GffFieldKind.Int64: value = $gffValue.getValue(GffInt64).int64
    of GffFieldKind.Double: value = $gffValue.getValue(GffDouble).float64.formatFloat(ffDecimal, floatPrecision)
    of GffFieldKind.CExoString: value = $gffValue.getValue(GffCExoString)
    of GffFieldKind.ResRef: value = $gffValue.getValue(GffResRef).string
    of GffFieldKind.Void: value = $gffValue.getValue(GffVoid).string.encode()
    of GffFieldKind.CExoLocString:
      let id = gffValue.getValue(GffCExoLocString).strRef
      if id != BadStrRef: value = $id
      else: value = "-1"
      result.add([name, kind, value])
      for subLable, subValue in pairs(gffValue.getValue(GffCExoLocString).entries):
        value = subValue
        result.add([name, '[' & $subLable & ']', value])
      fieldHandled = true
    of GffFieldKind.Struct:
      let struct = gffValue.getValue(GffStruct)
      result.add([name, kind, $struct.id])
      let prefix = name & '.' #Struct Prefix
      let breakdown = nwntFromGffStruct(struct, floatPrecision, prefix)
      result.add(breakdown)
      fieldHandled = true
    of GffFieldKind.List:
      for elem in gffValue.getValue(GffList):
        let nameIndex = name & "[]"
        result.add([nameIndex, kind, $elem.id])
        let prefix = nameIndex & "." #List Prefix
        let breakdown = nwntFromGffStruct(elem, floatPrecision, prefix)
        result.add(breakdown)
      fieldHandled = true

    if fieldHandled == false: result.add([name, kind, value])

proc toNwnt*(file: FileStream, s: GffStruct, floatPrecision: int = 4) =
  ##Passes GFFStruct to receive seq of nwnt, then processes for lines
  let nwnt = nwntFromGffStruct(s, floatPrecision)

  for line in nwnt:
    file.write(line[0] & line[1] & " = " & manageEscapesToText(line[2]) & "\c\L")

proc gffStructFromNwnt*(file: FileStream, result: GffStruct, listDepth: int = 0) =
  var line: string
  var pos: int
  while(true):
    pos = getPosition(file)
    if not file.readLine(line):
      return

    var
      name, kind, lable, value: string

    try:
      let
        valSplit = line.split('=', 1)
        nameKindSplit = valSplit[0].split('$', 1)
      name = nameKindSplit[0]

      let prefixLableSplit = name.rsplit('.')
      if prefixLableSplit.len-1 != listDepth:
        setPosition(file, pos)
        return

      let lableandIndex = prefixLableSplit[listDepth]

      kind = toLowerAscii(nameKindSplit[1][0..^2])
      lable = lableandIndex.rsplit('[', 1)[0]
      value = valSplit[1][1..^1]
    except:
      raise newException(ValueError, "Syntax error parsing: " & line)

    if lable.len > 16:
      raise newException(ValueError, "Syntax error near: " & line)

    case kind:
    of "byte": result[lable, GffByte] = parseInt(value).GffByte
    of "char": result[lable, GffChar] = parseInt(value).GffChar
    of "word": result[lable, GffWord] = parseInt(value).GffWord
    of "short": result[lable, GffShort] = parseInt(value).GffShort
    of "dword": result[lable, GffDword] = parseInt(value).GffDword
    of "int": result[lable, GffInt] = parseInt(value).GffInt
    of "float": result[lable, GffFloat] = parseFloat(value).GffFloat
    of "dword64": result[lable, GffDword64] = parseBiggestInt(value).GffDword64
    of "int64": result[lable, GffInt64] = parseBiggestInt(value).GffInt64
    of "double":
      var f64: float64
      discard value.parseBiggestFloat(f64)
      result[lable, GffDouble] = f64.GffDouble
    of "cexostring": result[lable, GffCExoString] = manageEscapesToGff(value).GffCExoString
    of "resref": result[lable, GffResRef] = value.GffResRef
    of "void": result[lable, GffVoid] = value.decode().GffVoid
    of "cexolocstring":
      let exo = newCExoLocString()
      if value != "-1":
        exo.strRef = parseBiggestInt(value).StrRef
      while(true):
        pos = getPosition(file)
        if not file.readLine(line):
          break

        let subSplit = line.split('=', 1)
        let indexSplit = subSplit[0].rsplit('[', 1)

        if indexSplit[0] != name:
          setPosition(file, pos)
          break

        let
          subValue = subSplit[1][1..^1]
          subLable = indexSplit[1][0..^3]

        exo.entries[parseInt(subLable)] = manageEscapesToGff(subValue)

      result[lable, GffCExoLocString] = exo
    of "struct":
      let st = newGffStruct()
      st.id = parseInt(value).int32
      gffStructFromNwnt(file, st, listDepth+1)
      result[lable, GffStruct] = st
    of "list":
      var
        list = newGffList()
        listStructID = parseInt(value).int32

      while(true):
        let st = newGffStruct()
        st.id = listStructID
        gffStructFromNwnt(file, st, listDepth+1)
        list.add(st)

        pos = getPosition(file)
        if not file.readLine(line):
          break

        let listTest = line.split('$', 1)[0]
        if  listTest != name:
          if listTest.split(']').len > name.split(']').len:
            raise newException(ValueError, "Syntax error near: " & line)
          setPosition(file, pos)
          break

        let
          newListIDSplit = line.split('=', 1)
          newListID = newListIDSplit[1][1..^1]

        listStructID = parseInt(newListID).int32

      result[lable, GffList] = list
    else: raise newException(ValueError, "unknown field type " & kind)

proc gffRootFromNwnt*(file: FileStream): GffRoot =
  ## Attempts to read a GffRoot from nwnt file. Will raise ValueError on any issues.
  result = newGffRoot()
  let dataType = readline(file).split('=', 1)
  expect(dataType[0] == "data_type ")
  result.fileType = dataType[1][1..3] & ' '

  file.gffStructFromNwnt(result)
