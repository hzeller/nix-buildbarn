{ config, pkgs, lib, ... }:

let
  # Import the bb-storage flake
  bb-storage-flake = builtins.getFlake (toString ./bb-storage);
  bb-storage-pkg = bb-storage-flake.packages.${pkgs.system}.default;

  blob-dir = "/var/lib/rbe-storage";

  casBlocksSizeBytes = 100 * 1024 * 1024 * 1024;  // 100 G
  casIndexSizeBytes = 256 * 1024 * 1024;

  acBlocksSizeBytes = 8 * 1024 * 1024 * 1024;   // 8G action cache
  acIndexSizeBytes = 64 * 1024 * 1024;

  bb-storage-config = {
    contentAddressableStorage = {
      backend = {
        local = {
          keyLocationMapOnBlockDevice = {
            file = {
              path = "${blob-dir}/cas_index";
              sizeBytes = casIndexSizeBytes;
            };
          };
          keyLocationMapMaximumGetAttempts = 16;
          keyLocationMapMaximumPutAttempts = 64;
          oldBlocks = 8;
          currentBlocks = 24;
          newBlocks = 1;
          blocksOnBlockDevice = {
            source = {
              file = {
                path = "${blob-dir}/cas_blocks";
                sizeBytes = casBlocksSizeBytes;
              };
            };
            spareBlocks = 3;
          };
        };
      };
      getAuthorizer = { allow = {}; };
      putAuthorizer = { allow = {}; };
      findMissingAuthorizer = { allow = {}; };
    };
    actionCache = {
      backend = {
        local = {
          keyLocationMapOnBlockDevice = {
            file = {
              path = "${blob-dir}/ac_index";
              sizeBytes = acIndexSizeBytes;
            };
          };
          keyLocationMapMaximumGetAttempts = 16;
          keyLocationMapMaximumPutAttempts = 64;
          oldBlocks = 8;
          currentBlocks = 24;
          newBlocks = 1;
          blocksOnBlockDevice = {
            source = {
              file = {
                path = "${blob-dir}/ac_blocks";
                sizeBytes = acBlocksSizeBytes;
              };
            };
            spareBlocks = 3;
          };
        };
      };
      getAuthorizer = { allow = {}; };
      putAuthorizer = { allow = {}; };
    };
    grpcServers = [{
      listenAddresses = [":8980"];
      authenticationPolicy = { allow = {}; };
    }];
    global = {
      diagnosticsHttpServer = {
        httpServers = [{
          listenAddresses = [":9980"];
          authenticationPolicy = { allow = {}; };
        }];
        enablePrometheus = true;
        enablePprof = true;
      };
    };
    maximumMessageSizeBytes = 16777216;
  };

  configFile = pkgs.writeText "bb_storage.json" (builtins.toJSON bb-storage-config);

in
{
  users.groups.rbe-storage = {};
  users.users.rbe-storage = {
    isSystemUser = true;
    group = "rbe-storage";
    home = blob-dir;
    createHome = true;
  };

  systemd.services.bb-storage = {
    description = "Buildbarn Storage Daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      User = "rbe-storage";
      Group = "rbe-storage";
      # Create sparse files if they do not exist
      ExecStartPre = pkgs.writeShellScript "bb-storage-pre" ''
        mkdir -p ${blob-dir}

        if [ ! -f ${blob-dir}/cas_index ]; then
          truncate -s ${toString casIndexSizeBytes} ${blob-dir}/cas_index
        fi
        if [ ! -f ${blob-dir}/cas_blocks ]; then
          truncate -s ${toString casBlocksSizeBytes} ${blob-dir}/cas_blocks
        fi

        if [ ! -f ${blob-dir}/ac_index ]; then
          truncate -s ${toString acIndexSizeBytes} ${blob-dir}/ac_index
        fi
        if [ ! -f ${blob-dir}/ac_blocks ]; then
          truncate -s ${toString acBlocksSizeBytes} ${blob-dir}/ac_blocks
        fi
      '';
      ExecStart = "${bb-storage-pkg}/bin/bb_storage ${configFile}";
      Restart = "on-failure";
      RestartSec = 5;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ blob-dir ];
    };
  };
}
