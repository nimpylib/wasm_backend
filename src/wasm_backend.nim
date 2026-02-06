# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

import std/strutils
import std/os

proc get_clang_major_version(ver_file_path: string): string =
  #result = "21"
  for line in ver_file_path.readFile.splitLines:
    if line.startsWith "llvm-version: ":
      result = ""
      var i = 14
      while true:
        let c = line[i]
        if c == '.':
          break
        result.add c
        i.inc
      return
  raise newException(ValueError, "cannot parse clang version from " & ver_file_path)

proc get_wasm_build_flags*(nimVersion: string, linkFlags: openArray[string] = []): string =
  var cmd = " --threads:off -d:wasm -d:wasi --cpu:wasm32 --os:linux"
  
  # XXX:NIM-BUG: if using orc/arc/refc
  # npython.wasm!addToSharedFreeListBigChunks...
  # with msg: 2: memory fault at wasm address 0x6e7583ec in linear memory of size 0xe0000
  #           3: wasm trap: out of bounds memory access
  cmd.add " --mm:" &
    #"arc"
    "markAndSweep"
  cmd.add " --exceptions:goto"
  if off: # will causes `env::memory`,etc not defined
    cmd.add " --app:lib"
  else:
    #cmd.add " --passL:--entry=main"
    discard
  var sdk = getEnv"WASI_SDK_PATH"
  if sdk == "": sdk = getEnv"WASI_SDK_PREFIX"
  template c(v) =
    cmd.add " --passC:" & v
  template l(v) =
    cmd.add " --passL:" & v
  for i in linkFlags:
    assert not i.startsWith "--"
    l "--" & i
  if sdk == "":
    let wasm_ld = findExe("wasm-ld")
    if wasm_ld != "":
      sdk = wasm_ld.parentDir.parentDir
      if not dirExists sdk:
        raise newException(OSError, "wasm-ld not in of typical structure (a.k.a. WASI_SDK_PATH/bin")
    else:
      raise newException(OSError, "please set WASI_SDK_PATH or WASI_SDK_PREFIX envvar")
  else:
    const target = "wasm32-wasip1"
    #XXX:wasmtime-BUG: if using wasm32-wasip2
    #  1: unknown import: `wasi:io/error@0.2.0::[resource-drop]error` has not been defined
    cmd.add " --cc:clang"
    cmd.add " --passC:--target=" & target
    #cmd.add " --passL:-lstatic=c++ --passL:-lstatic=c++abi"
    l"-lc"

    # cmd.add " --passC:-fapple-link-rtlib"  # Force linking the clang builtins runtime library
    # otherwise it won't, as Nim calls c compiler and linker seperately

    #c"-fno-builtin"

    proc unknown(s: string): string =
      let arr = s.split('-', 1)
      arr[0] & "-unknown-" & arr[1]
    let clang_version = get_clang_major_version(sdk & "/VERSION")
    cmd.add " --passL:" & sdk & "/lib/clang/" & clang_version & "/lib/" & target.unknown &
      "/libclang_rt.builtins.a"

    #l "--allow-undefined"
    cmd.add " --passC:-D_WASI_EMULATED_MMAN --passL:-lwasi-emulated-mman"
    cmd.add " --passC:-D_WASI_EMULATED_SIGNAL --passL:-lwasi-emulated-signal"
    let sysroot = sdk & "/share/wasi-sysroot"
    c "--sysroot=" & sysroot
    # We've passed --sysroot, so no need to:
    #c "-I" & sysroot & "/include"

    let sysroot_lib = sysroot & "/lib/"
    l "-L" & sysroot_lib & target
    l sysroot_lib & "wasm32-wasi/crt1-command.o"  # this define `_start` that load `main`

    cmd.add " --clang.exe=" & sdk & "/bin/clang "
    cmd.add " --clang.linkerexe=" & sdk & "/bin/wasm-ld"
    cmd.add " -d:nimPreviewSlimSystem"
  cmd

when isMainModule:
  import std/parseopt
  import std/sets
  let falses = toHashSet ["no", "false", "off"]
  var
    dstNimVersion = ""
    linkFlags: seq[string]
  for (kind, k, val) in getopt():
    case kind
    of cmdEnd: doAssert false
    of cmdLongOption:
      # pass --export-all, --export=a,b,... to linker
      if k.startsWith "export":
        var exports = ""
        exports.add k
        if val.len > 0:
          if k == "export-all" and val in falses:
            exports = ""
            continue
          exports.add '='
          exports.add val
        linkFlags.add exports
    # ignore more, reversed for further usage
    of cmdShortOption: discard
    of cmdArgument:
      if dstNimVersion.len == 0:
        dstNimVersion = k
  echo get_wasm_build_flags(dstNimVersion, linkFlags)

 
