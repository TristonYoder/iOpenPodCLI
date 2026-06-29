{ lib
, buildPythonApplication
, hatchling
, pyqt6 ? null
, numpy
, pillow
, pycryptodome
, mutagen
, pyusb
, wasmtime  # provided by nix/wasmtime-py.nix
, certifi
, feedparser
, requests
, packaging
, tqdm
, python-dateutil
, pyyaml
# GUI-only; pass null to build the headless CLI without Qt
, wrapQtAppsHook ? null
, qt6 ? null
, headless ? false  # when true: skip Qt, install only iopod CLI
, src
}:

let
  withGui = !headless && pyqt6 != null && wrapQtAppsHook != null && qt6 != null;
in

buildPythonApplication {
  pname = if headless then "iopod" else "iopenpod";
  version = (builtins.fromTOML (builtins.readFile ../pyproject.toml)).project.version;
  pyproject = true;

  inherit src;

  # Relax version constraints that are slightly ahead of nixpkgs-unstable at
  # the time of packaging. These are minor semver bumps with no API changes.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'pyqt6>=6.9.1,<7.0.0'   'pyqt6>=6.9.0,<7.0.0' \
      --replace-fail 'numpy>=2.3.0,<3.0.0'    'numpy>=2.2.0,<3.0.0' \
      --replace-fail 'pillow>=11.2.1,<12.0.0' 'pillow>=11.0.0' \
      --replace-fail 'tqdm>=4.67.3'            'tqdm>=4.67.1'
  '';

  nativeBuildInputs = lib.optionals withGui [
    wrapQtAppsHook
  ] ++ [ hatchling ];

  buildInputs = lib.optionals withGui [ qt6.qtbase ];

  propagatedBuildInputs = [
    numpy
    pillow
    pycryptodome
    mutagen
    pyusb
    wasmtime
    certifi
    feedparser
    requests
    packaging
    tqdm
    python-dateutil
    pyyaml
  ] ++ lib.optionals withGui [ pyqt6 ];

  postInstall = lib.optionalString withGui ''
    install -Dm644 flatpak/io.github.therealsavi.iOpenPod.desktop \
      $out/share/applications/io.github.therealsavi.iOpenPod.desktop
    substituteInPlace $out/share/applications/io.github.therealsavi.iOpenPod.desktop \
      --replace-fail 'Exec=iOpenPod' 'Exec=iopenpod'

    for size in 16 24 32 48 64 128 256; do
      install -Dm644 assets/icons/icon-''${size}.png \
        $out/share/icons/hicolor/''${size}x''${size}/apps/io.github.therealsavi.iOpenPod.png
    done
  '';

  dontWrapQtApps = withGui;
  preFixup = lib.optionalString withGui ''
    makeWrapperArgs+=("''${qtWrapperArgs[@]}")
  '';

  meta = with lib; {
    description =
      if headless
      then "Headless iPod sync CLI — music playlists, podcasts, and ratings without iTunes or a GUI"
      else "Open-source iPod sync tool — manage your iPod without iTunes";
    homepage = "https://github.com/TristonYoder/iOpenPodCLI";
    license = licenses.mit;
    mainProgram = if headless then "iopod" else "iopenpod";
    platforms = platforms.linux ++ platforms.darwin;
    maintainers = [ ];
  };
}
