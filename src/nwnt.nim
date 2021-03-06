# This is just an example to get you started. A typical hybrid package
# uses this file as the main entry point of the application.

import nwntpkg/gffnwnt
export gffnwnt
import os, streams, docopt, strutils, parsecfg
import neverwinter/gff

const GffExtensions* = @[
  "utc", "utd", "ute", "uti", "utm", "utp", "uts", "utt", "utw",
  "git", "are", "gic", "mod", "ifo", "fac", "dlg", "itp", "bic",
  "jrl", "gff", "gui"
]

when isMainModule:
  let args = docopt"""
  Convert gff data to the custom output language 'nwnt'.

  Supports input of either .nwnt or .gff data, and outputs the other.

  Usage:
    nwnt <inputfile> [options]
    nwnt -h | --help
    nwnt --version

  Options:
    -o FILE     optional path to the output file (without extension)
                Will default to input directory

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



  let inputfile = $args["<inputfile>"]
  let informat = inputfile.splitFile.ext[1..^1]
  var outputfile  = $args["-o"]
  if outputfile == "nil":
    outputfile = inputfile #extension added later so these aren't identical

  var state: GffRoot

  if informat in GffExtensions:
    outputfile.add(".nwnt")

    let floatPrecision = parseInt($args["-p"])
    let input  = openFileStream(inputfile)
    let output = openFileStream(outputfile, fmWrite)
    state = input.readGffRoot(false)
    output.toNwnt(state, floatPrecision)

  elif informat == "nwnt":
    if(outputfile[^5..^1] == ".nwnt"):
      outputfile = outputfile.splitFile.dir & outputfile.splitFile.name

    let input  = openFileStream(inputfile)
    let output = openFileStream(outputfile, fmWrite)
    state = input.gffRootFromNwnt()
    output.write(state)

  else:
    quit("This is not a supported format")
