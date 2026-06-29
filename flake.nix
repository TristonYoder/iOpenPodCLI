{
  description = "iOpenPodCLI — headless iPod sync (music playlists, podcasts, ratings)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem
      [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ]
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          python = pkgs.python312;

          wasmtime-py = python.pkgs.callPackage ./nix/wasmtime-py.nix { };

          # Headless CLI — no Qt; works on servers and desktops alike
          iopenpod-sync = python.pkgs.callPackage ./nix/package.nix {
            wasmtime = wasmtime-py;
            src = self;
            headless = true;
          };

          # Full GUI — requires Qt; only useful on a desktop host
          iopenpod = python.pkgs.callPackage ./nix/package.nix {
            wasmtime = wasmtime-py;
            src = self;
            wrapQtAppsHook = pkgs.qt6Packages.wrapQtAppsHook;
            qt6 = pkgs.qt6;
            pyqt6 = python.pkgs.pyqt6;
          };
        in
        {
          packages = {
            inherit iopenpod-sync iopenpod wasmtime-py;
            # Default: headless CLI, suitable for both server and desktop
            default = iopenpod-sync;
          };

          apps = {
            default = flake-utils.lib.mkApp { drv = iopenpod-sync; name = "iopenpod-sync"; };
            iopenpod = flake-utils.lib.mkApp { drv = iopenpod; name = "iopenpod"; };
          };

          devShells.default = pkgs.mkShell {
            packages = [
              (python.withPackages (ps: with ps; [
                ps.pyqt6
                ps.numpy
                ps.pillow
                ps.pycryptodome
                ps.mutagen
                ps.pyusb
                wasmtime-py
                ps.certifi
                ps.feedparser
                ps.requests
                ps.packaging
                ps.tqdm
                ps.python-dateutil
                ps.pyyaml
              ]))
            ];
          };
        }
      )

    //

    {
      # Overlay — consume from another flake (e.g. nix-config):
      #   inputs.iopenpodcli.url = "github:TristonYoder/iOpenPodCLI";
      #   nixpkgs.overlays = [ inputs.iopenpodcli.overlays.default ];
      #   environment.systemPackages = [ pkgs.iopenpod-sync ];
      overlays.default = final: prev:
        let
          wasmtime-py = prev.python312Packages.callPackage ./nix/wasmtime-py.nix { };
        in
        {
          iopenpod-sync = prev.python312Packages.callPackage ./nix/package.nix {
            wasmtime = wasmtime-py;
            src = self;
            headless = true;
          };

          iopenpod = prev.python312Packages.callPackage ./nix/package.nix {
            wasmtime = wasmtime-py;
            src = self;
            wrapQtAppsHook = prev.qt6Packages.wrapQtAppsHook;
            qt6 = prev.qt6;
            pyqt6 = prev.python312Packages.pyqt6;
          };
        };
    };
}
