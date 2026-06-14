{
  description = "buildbarn/bb-storage";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        rec {
          bb-storage = pkgs.buildGoModule {
            pname = "bb-storage";
            version = "unstable";
            src = pkgs.fetchFromGitHub {
              owner = "buildbarn";
              repo = "bb-storage";
              rev = "10acc76a8295d86f64baa8485c8e616bce0d53ca";
              hash = "sha256-+HdS1SOQDnyAjXP2L+73hiaYnsLpfFJ5jIiugZro3bM=";
            };

            patches = [ ./patches/grpc.patch ];

            postPatch = ''
              sed -i 's/go 1.26.4/go 1.26.3/g' go.mod
            '';

            subPackages = [ "cmd/..." ];
            doCheck = false;

            vendorHash = "sha256-ZgI0rbQ8NsC2nevYpEdSrwH9d3T4rjTZwgoliU2ueP0=";
          };
          default = bb-storage;
        }
      );

      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              go
            ];
          };
        }
      );
    };
}
