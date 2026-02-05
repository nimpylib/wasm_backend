# Package

version       = "0.1.0"
author        = "litlighilit"
description   = "To support WASM backend for nim"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"

namedBin["wasm_backend"] = "nim-wasm-build-flags"


# Dependencies

requires "nim >= 2.0.8"
