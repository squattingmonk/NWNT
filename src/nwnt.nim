# This is just an example to get you started. A typical hybrid package
# uses this file as the main entry point of the application.

import nwntpkg/gffnwnt
export gffnwnt
import os, streams, docopt, strutils, parsecfg
import neverwinter/gff

const
  GffExtensions* = @[
  "utc", "utd", "ute", "uti", "utm", "utp", "uts", "utt", "utw",
  "git", "are", "gic", "mod", "ifo", "fac", "dlg", "itp", "bic",
  "jrl", "gff", "gui" ]
  SupportedFormats = GffExtensions & @["nwnt"] 

proc getFileFormat(file: string): string =
  file.splitFile.ext.strip(leading = true, trailing = false, {'.'})

when isMainModule:
  let args = docopt"""
  Convert gff data to the custom output language 'nwnt'.

  Supports input of either .nwnt or .gff data, and outputs the other.

  Usage:
    nwnt [options]
    nwnt -h | --help
    nwnt --version

  Options:
    -i FILE     Path to input file (required)
    -o FILE     Path to output file. This parameter is optional; if not set, it
                will default to the input file's path, adding ".nwnt" if it is a
                GFF file or removing it if not.

    -p places   float precision for nwnt output [default: 4]

    -h          Show this screen
  """

  #Adapted from nwsync --version handling
  if args["--version"]:
    const nimble: string   = slurp(currentSourcePath().splitFile().dir & "/../nwnt.nimble")
    const gitBranch: string = staticExec("git symbolic-ref -q --short HEAD").strip
    const gitRev: string    = staticExec("git rev-parse HEAD").strip

    let nimbleConfig        = loadConfig(newStringStream(nimble))
    let packageVersion     = nimbleConfig.getSectionValue("", "version")
    let versionString  = "NWNT " & packageVersion & " (" & gitBranch & "/" & gitRev[0..5] & ", nim " & NimVersion & ")"

    echo versionString
    quit(0)

  if not args["-i"]:
    quit("Error: input file required")

  let
    inFile = $args["-i"]
    inFormat = inFile.getFileFormat
    outFile =
      if args["-o"]:
        let outFile = $args["-o"]
        if outFile.getFileFormat notin SupportedFormats:
          quit("Error: output file format not supported")
        outFile
      elif inFormat in GffExtensions:
        inFile & ".nwnt"
      elif inFormat == "nwnt":
        inFile[0..^4]
      else:
        quit("Error: input file format not supported")
  try:
    let
      input = openFileStream(inFile)
      output = openFileStream(outFile, fmWrite)

    var state: GffRoot

    if informat in GffExtensions:
      let floatPrecision = parseInt($args["-p"])
      state = input.readGffRoot(false)
      output.toNwnt(state, floatPrecision)
    elif informat == "nwnt":
      state = input.gffRootFromNwnt()
      output.write(state)

    input.close
    output.close
  except IOError as e:
    quit("Error: " & e.msg)
