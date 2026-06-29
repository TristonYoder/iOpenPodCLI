{ lib
, buildPythonPackage
, fetchurl
, autoPatchelfHook
, stdenv
}:

# wasmtime Python bindings — fetched as pre-built wheels because the package
# bundles a compiled Rust/C WebAssembly runtime. autoPatchelfHook rewrites
# ELF rpath entries on Linux so the bundled .so files resolve correctly.
let
  version = "45.0.0";
  wheels = {
    "x86_64-linux" = {
      url = "https://files.pythonhosted.org/packages/d7/8c/e9019a28e908214031310aefd78e4755221d02303190b54b2c85cb69573e/wasmtime-45.0.0-py3-none-manylinux1_x86_64.whl";
      hash = "sha256-XRQW7G2ozYfCni6esHQ1jJGDnC//lx/kKMiSHqrmjnM=";
    };
    "aarch64-linux" = {
      url = "https://files.pythonhosted.org/packages/42/56/ed5f492bd553a31c8e28d621f8256f2c7b1a133b28f73525d96ca355891a/wasmtime-45.0.0-py3-none-manylinux2014_aarch64.whl";
      hash = "sha256-pJn2qw7rtw3Kg9akkEt0PNEi8yKvOr6GrwitdTUz2UY=";
    };
    "x86_64-darwin" = {
      url = "https://files.pythonhosted.org/packages/75/76/7d0e440ca03a717a97889dbb7b68f952c20ed4ffd3f59addf9553579e1d5/wasmtime-45.0.0-py3-none-macosx_10_13_x86_64.whl";
      hash = "sha256-NXmw7G0AF1DWbscImq7uLASPiDKMgnQ+FfCZrwGwz4Q=";
    };
    "aarch64-darwin" = {
      url = "https://files.pythonhosted.org/packages/5b/0b/a81b5daf5adea482ecb68d9615f6a348486ab4d8e980a915d4420e57ee4d/wasmtime-45.0.0-py3-none-macosx_11_0_arm64.whl";
      hash = "sha256-MdEPJcMwzrz7Nk6aNXEj3u7JbEFyX/K7qRtwVYfzipM=";
    };
  };
  wheel = wheels.${stdenv.hostPlatform.system} or (throw "wasmtime-py: unsupported platform ${stdenv.hostPlatform.system}");
in

buildPythonPackage {
  pname = "wasmtime";
  inherit version;
  format = "wheel";

  src = fetchurl {
    inherit (wheel) url hash;
  };

  # Fix ELF binaries on Linux; macOS wheels use @rpath so no patching needed
  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  # The wheel bundles its own libwasmtime.so — no external runtime dep needed
  pythonImportsCheck = [ "wasmtime" ];

  meta = with lib; {
    description = "Python bindings for the wasmtime WebAssembly runtime";
    homepage = "https://github.com/bytecodealliance/wasmtime-py";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
  };
}
