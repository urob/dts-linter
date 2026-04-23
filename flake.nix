{
  description = "dts-linter – DeviceTree linter and formatter CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
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
      in
      {
        packages.default = dts-linter;

        devShells.default = pkgs.mkShell {
          packages = [ dts-linter ];
        };
      });
}
