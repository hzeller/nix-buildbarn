{
  description = "Buildbarn Remote Execution";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.buildGoModule {
          pname = "bb-remote-execution";
          version = "0.0.0";

          src = pkgs.fetchFromGitHub {
            owner = "buildbarn";
            repo = "bb-remote-execution";
            rev = "3afb89222c2dd68a6f8f71b83a6b59d48e21046a";
            hash = "sha256-Fd9G6BWXcKP80uDhHHoVnhrW56TQLz1CmbWRyHuKoLM=";
          };

          patches = [
            ./patches/runner-command-wrapper.patch
          ];

          postPatch = ''
            sed -i 's/go 1.26.4/go 1.26.3/g' go.mod
          '';

          vendorHash = "sha256-u90Yf0iR0FHa4gDba8G2gKJFLrUogUcM9+7d8Qz9SaE=";

          modPostBuild = ''
            patch -p0 -d vendor/github.com/hanwen/go-fuse/v2 < patches/com_github_hanwen_go_fuse_v2/direntrylist-offsets-and-testability.diff || true
            patch -p0 -d vendor/github.com/hanwen/go-fuse/v2 < patches/com_github_hanwen_go_fuse_v2/writeback-cache.diff || true
            patch -p0 -d vendor/github.com/hanwen/go-fuse/v2 < patches/com_github_hanwen_go_fuse_v2/notify-testability.diff || true
          '';

          subPackages = [
            "cmd/bb_noop_worker"
            "cmd/bb_runner"
            "cmd/bb_scheduler"
            "cmd/bb_virtual_tmp"
            "cmd/bb_worker"
            "cmd/fake_python"
            "cmd/fake_xcrun"
          ];

          doCheck = false;
        };
      }
    );
}
