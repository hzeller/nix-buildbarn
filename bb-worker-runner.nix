{ config, pkgs, lib, ... }:

let
  bb-remote-execution-flake = builtins.getFlake (toString ./bb-remote-execution);
  bb-re-pkg = bb-remote-execution-flake.packages.${pkgs.system}.default;

  # Hostnames that run the bb-storage and bb-scheduler
  cas-host = "meitner";
  scheduler-host = "meitner";

  base-dir = "/var/lib/rbe-runner";
  use-cores = 24;   # Can this be queried at eval time ?

  # --- bb_runner ---
  # Generator function for a runner
  mkRunnerConfig = id: {
    buildDirectoryPath = "${base-dir}/worker-${id}/build";
    grpcServers = [{
      listenPaths = ["${base-dir}/worker-${id}/runner.sock"];
      authenticationPolicy = { allow = {}; };
    }];
    global = {};
  };

  # --- bb_worker ---
  # Generator function for a worker
  mkWorkerConfig = id: {
    blobstore = {
      contentAddressableStorage = {
        grpc = { client = { address = "${cas-host}:8980"; }; };
      };
      actionCache = {
        grpc = { client = { address = "${cas-host}:8980"; }; };
      };
    };
    scheduler = { address = "${scheduler-host}:8982"; };
    inputDownloadConcurrency = 4;
    outputUploadConcurrency = 4;
    buildDirectories = [{
      native = {
        buildDirectoryPath = "${base-dir}/worker-${id}/build";
        cacheDirectoryPath = "${base-dir}/worker-${id}/cache";
        maximumCacheFileCount = 10000;
        maximumCacheSizeBytes = 1000000000; # 1 GB
        cacheReplacementPolicy = "LEAST_RECENTLY_USED";
      };
      runners = [
        {
          endpoint = { address = "unix://${base-dir}/worker-${id}/runner.sock"; };
          concurrency = use-cores;
          workerId = { id = "${id}-empty"; };
          platform = {};
        }
        {
          endpoint = { address = "unix://${base-dir}/worker-${id}/runner.sock"; };
          concurrency = use-cores;
          workerId = { id = "${id}-linux"; };
          platform = {
            properties = [
              { name = "OSFamily"; value = "linux"; }
            ];
          };
        }
      ];
    }];
    maximumMessageSizeBytes = 16777216;
  };

  runnerConfigFile = pkgs.writeText "bb_runner.json" (builtins.toJSON (mkRunnerConfig "1"));
  workerConfigFile = pkgs.writeText "bb_worker.json" (builtins.toJSON (mkWorkerConfig "1"));

in
{
  users.groups.rbe-runner = {};
  users.users.rbe-runner = {
    isSystemUser = true;
    group = "rbe-runner";
    home = base-dir;
    createHome = true;
  };

  systemd.services.bb-runner = {
    description = "Buildbarn Runner";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      User = "rbe-runner";
      Group = "rbe-runner";
      ExecStartPre = pkgs.writeShellScript "bb-runner-pre" ''
        mkdir -p ${base-dir}/worker/build
        rm -f ${base-dir}/worker/runner.sock
      '';
      ExecStart = "${bb-re-pkg}/bin/bb_runner ${runnerConfigFile}";
      Restart = "always";
      RestartSec = "3s";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ base-dir ];
      # This is our launcher script that makes nix store paths happen if needed.
      Environment = [ "BB_RUNNER_COMMAND_WRAPPER=${./nix-wrapper.sh}" ];
    };
  };

  systemd.services.bb-worker = {
    description = "Buildbarn Worker";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "bb-runner.service"];
    requires = [ "bb-runner.service" ];

    serviceConfig = {
      User = "rbe-runner";
      Group = "rbe-runner";
      ExecStartPre = pkgs.writeShellScript "bb-worker-pre" ''
        mkdir -p ${base-dir}/worker/build
        mkdir -p ${base-dir}/worker/cache
        # Wait for the runner socket to be available
        while [ ! -S ${base-dir}/worker/runner.sock ]; do
          sleep 0.5
        done
      '';
      ExecStart = "${bb-re-pkg}/bin/bb_worker ${workerConfigFile}";
      Restart = "always";
      RestartSec = "3s";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ base-dir ];
    };
  };
}
