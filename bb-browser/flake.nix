{
  description = "buildbarn/bb-browser";

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
          bb-browser = pkgs.buildGoModule {
            pname = "bb-browser";
            version = "unstable";
            src = pkgs.fetchFromGitHub {
              owner = "buildbarn";
              repo = "bb-browser";
              rev = "ee35c54d5cecfc7a763870fe2187c93fa47aaf85";
              hash = "sha256-BIqr0VcqDYp3amA966v1jKCZxpgYxSoeifvbMQZoG7c=";
            };

            subPackages = [ "cmd/..." ];
            doCheck = false;

            vendorHash = "sha256-ZGxagRTVLGIkGMAOZDPo4kolbj6kOlIAW4aedrd0M/0=";
          };
          default = bb-browser;
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
