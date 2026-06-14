{ config, pkgs, lib, ... }:

let
  # Import the bb-storage flake
  bb-storage-flake = builtins.getFlake "/home/hzeller/buildbarn-3/bb-storage";
  bb-storage-pkg = bb-storage-flake.packages.${pkgs.system}.default;

  blobDir = "/var/lib/buildbarn-storage";

  bb-storage-config = {
    contentAddressableStorage = {
      backend = {
        local = {
          keyLocationMapOnBlockDevice = {
            file = {
              path = "${blobDir}/cas_index";
              sizeBytes = 16 * 1024 * 1024;
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
                path = "${blobDir}/cas_blocks";
                sizeBytes = 10 * 1024 * 1024 * 1024; # 10 GB
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
              path = "${blobDir}/ac_index";
              sizeBytes = 16 * 1024 * 1024;
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
                path = "${blobDir}/ac_blocks";
                sizeBytes = 1 * 1024 * 1024 * 1024; # 1 GB
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
  users.groups.buildbarn-storage = {};
  users.users.buildbarn-storage = {
    isSystemUser = true;
    group = "buildbarn-storage";
    home = blobDir;
    createHome = true;
  };

  systemd.services.bb-storage = {
    description = "Buildbarn Storage Daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      User = "buildbarn-storage";
      Group = "buildbarn-storage";
      # Create sparse files if they do not exist
      ExecStartPre = pkgs.writeShellScript "bb-storage-pre" ''
        mkdir -p ${blobDir}
        
        if [ ! -f ${blobDir}/cas_index ]; then
          truncate -s 16M ${blobDir}/cas_index
        fi
        if [ ! -f ${blobDir}/cas_blocks ]; then
          truncate -s 10G ${blobDir}/cas_blocks
        fi
        
        if [ ! -f ${blobDir}/ac_index ]; then
          truncate -s 16M ${blobDir}/ac_index
        fi
        if [ ! -f ${blobDir}/ac_blocks ]; then
          truncate -s 1G ${blobDir}/ac_blocks
        fi
      '';
      ExecStart = "${bb-storage-pkg}/bin/bb_storage ${configFile}";
      Restart = "on-failure";
      RestartSec = 5;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ blobDir ];
    };
  };
}
