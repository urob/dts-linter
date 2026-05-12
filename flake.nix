{
  description = "dts-linter – DeviceTree linter and formatter CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    dts-lsp-src = {
      url = "github:urob/dts-lsp";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, dts-lsp-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        nodejs = pkgs.nodejs_22;

        dts-linter = pkgs.buildNpmPackage {
          pname = "dts-linter";
          version = (builtins.fromJSON (builtins.readFile ./package.json)).version;
          src = ./.;
          inherit nodejs;

          # Keep in sync with package-lock.json.
          npmDepsHash = "sha256-BXyUrj3Wgd14VjKkBLn/7cPeYfXq5qKDG3bAWvJkS84=";

          # Call esbuild directly instead of via esbuild.js to skip the
          # license-checker step, which requires network access.
          buildPhase = ''
            runHook preBuild
            mkdir -p dist
            ./node_modules/.bin/esbuild src/dts-linter.ts \
              --bundle \
              --format=cjs \
              --minify \
              --platform=node \
              --outfile=dist/dts-linter.js
            runHook postBuild
          '';

          # The bundle relies on require.resolve("devicetree-language-server/...")
          # at runtime, so node_modules must live next to the bundle file.
          installPhase = ''
            runHook preInstall

            local modDir="$out/lib/node_modules/dts-linter"
            mkdir -p "$modDir"
            cp dist/dts-linter.js "$modDir/"
            cp -r node_modules "$modDir/"

            mkdir -p "$out/bin"
            makeWrapper "${nodejs}/bin/node" "$out/bin/dts-linter" \
              --add-flags "$modDir/dts-linter.js"

            runHook postInstall
          '';

          nativeBuildInputs = [ pkgs.makeWrapper ];
        };

        # Build the LSP server from the dts-lsp-src flake input. To use a local
        # checkout instead of the pinned GitHub revision:
        #   nix develop .#dev --override-input dts-lsp-src git+file:///path/to/dts-lsp
        dts-lsp-server = pkgs.buildNpmPackage {
          pname = "devicetree-language-server";
          version =
            (builtins.fromJSON (builtins.readFile "${dts-lsp-src}/server/package.json")).version;
          # Use server/ so npm ci installs server/package-lock.json deps (vscode-languageserver etc.).
          src = "${dts-lsp-src}/server";
          inherit nodejs;

          # Keep in sync with server/package-lock.json in the dts-lsp repo.
          npmDepsHash = "sha256-dYBA3N0/88TdhYtUlacD1PceHWE3sXNcejIzEK2m2V8=";

          nativeBuildInputs = [ pkgs.esbuild ];

          # Skip the license-checker step (requires network access).
          buildPhase = ''
            runHook preBuild
            mkdir -p dist
            esbuild src/server.ts \
              --bundle \
              --format=cjs \
              --minify \
              --platform=node \
              --outfile=dist/server.js
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/dist
            cp dist/server.js $out/dist/
            runHook postInstall
          '';
        };

        # dts-linter using the dts-lsp-src instead of the published LSP server.
        dts-linter-dev = dts-linter.overrideAttrs (_: {
          postInstall = ''
            cp ${dts-lsp-server}/dist/server.js \
               $out/lib/node_modules/dts-linter/node_modules/devicetree-language-server/dist/server.js
          '';
        });
      in
      {
        packages.default = dts-linter;
        packages.dev = dts-linter-dev;

        devShells.default = pkgs.mkShell {
          packages = [ dts-linter ];
        };
        devShells.dev = pkgs.mkShell {
          packages = [ dts-linter-dev ];
        };
      });
}
