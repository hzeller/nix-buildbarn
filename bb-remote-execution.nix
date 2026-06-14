{ config, pkgs, lib, ... }:

let
  bb-remote-execution-flake = builtins.getFlake "/home/hzeller/buildbarn-3/bb-remote-execution";
  bb-re-pkg = bb-remote-execution-flake.packages.${pkgs.system}.default;

  baseDir = "/var/lib/bazel-runner";
  
  # --- bb_scheduler ---
  schedulerConfig = {
    clientGrpcServers = [{
      listenAddresses = [":8981"];
      authenticationPolicy = { allow = {}; };
    }];
    workerGrpcServers = [{
      listenAddresses = [":8982"];
      authenticationPolicy = { allow = {}; };
    }];
    contentAddressableStorage = {
      grpc = { client = { address = "localhost:8980"; }; };
    };
    actionRouter = {
      simple = {
        platformKeyExtractor = { action = {}; };
        invocationKeyExtractors = [{ toolInvocationId = {}; }];
        initialSizeClassAnalyzer = {
          defaultExecutionTimeout = "1800s";
          maximumExecutionTimeout = "7200s";
        };
      };
    };
    executeAuthorizer = { allow = {}; };
    modifyDrainsAuthorizer = { allow = {}; };
    killOperationsAuthorizer = { allow = {}; };
    synchronizeAuthorizer = { allow = {}; };
    platformQueueWithNoWorkersTimeout = "900s";
    browserUrl = "http://localhost:8080/";
    maximumMessageSizeBytes = 16777216;
  };
  schedulerConfigFile = pkgs.writeText "bb_scheduler.json" (builtins.toJSON schedulerConfig);

  # --- bb_runner ---
  # Generator function for a runner
  mkRunnerConfig = id: {
    buildDirectoryPath = "${baseDir}/worker-${id}/build";
    grpcServers = [{
      listenPaths = ["${baseDir}/worker-${id}/runner.sock"];
      authenticationPolicy = { allow = {}; };
    }];
    global = {};
  };

  # --- bb_worker ---
  # Generator function for a worker
  mkWorkerConfig = id: {
    blobstore = {
      contentAddressableStorage = {
        grpc = { client = { address = "localhost:8980"; }; };
      };
      actionCache = {
        grpc = { client = { address = "localhost:8980"; }; };
      };
    };
    scheduler = { address = "localhost:8982"; };
    inputDownloadConcurrency = 4;
    outputUploadConcurrency = 4;
    buildDirectories = [{
      native = {
        buildDirectoryPath = "${baseDir}/worker-${id}/build";
        cacheDirectoryPath = "${baseDir}/worker-${id}/cache";
        maximumCacheFileCount = 10000;
        maximumCacheSizeBytes = 1000000000; # 1 GB
        cacheReplacementPolicy = "LEAST_RECENTLY_USED";
      };
      runners = [
        {
          endpoint = { address = "unix://${baseDir}/worker-${id}/runner.sock"; };
          concurrency = 24;
          workerId = { id = "${id}-empty"; };
          platform = {};
        }
        {
          endpoint = { address = "unix://${baseDir}/worker-${id}/runner.sock"; };
          concurrency = 24;
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

  runner1ConfigFile = pkgs.writeText "bb_runner_1.json" (builtins.toJSON (mkRunnerConfig "1"));
  worker1ConfigFile = pkgs.writeText "bb_worker_1.json" (builtins.toJSON (mkWorkerConfig "1"));

in
{
  users.groups.bazel-runner = {};
  users.users.bazel-runner = {
    isSystemUser = true;
    group = "bazel-runner";
    home = baseDir;
    createHome = true;
  };

  systemd.services.bb-scheduler = {
    description = "Buildbarn Scheduler";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "bb-storage.service" ];

    serviceConfig = {
      User = "bazel-runner";
      Group = "bazel-runner";
      ExecStart = "${bb-re-pkg}/bin/bb_scheduler ${schedulerConfigFile}";
      Restart = "always";
      RestartSec = "3s";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };

  systemd.services.bb-runner-1 = {
    description = "Buildbarn Runner 1";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      User = "bazel-runner";
      Group = "bazel-runner";
      ExecStartPre = pkgs.writeShellScript "bb-runner-1-pre" ''
        mkdir -p ${baseDir}/worker-1/build
        rm -f ${baseDir}/worker-1/runner.sock
      '';
      ExecStart = "${bb-re-pkg}/bin/bb_runner ${runner1ConfigFile}";
      Restart = "always";
      RestartSec = "3s";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ baseDir ];
      Environment = [ "BB_RUNNER_COMMAND_WRAPPER=${./nix-wrapper.sh}" ];
    };
  };

  systemd.services.bb-worker-1 = {
    description = "Buildbarn Worker 1";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "bb-scheduler.service" "bb-runner-1.service" ];
    requires = [ "bb-runner-1.service" ];

    serviceConfig = {
      User = "bazel-runner";
      Group = "bazel-runner";
      ExecStartPre = pkgs.writeShellScript "bb-worker-1-pre" ''
        mkdir -p ${baseDir}/worker-1/build
        mkdir -p ${baseDir}/worker-1/cache
        # Wait for the runner socket to be available
        while [ ! -S ${baseDir}/worker-1/runner.sock ]; do
          sleep 0.5
        done
      '';
      ExecStart = "${bb-re-pkg}/bin/bb_worker ${worker1ConfigFile}";
      Restart = "always";
      RestartSec = "3s";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ baseDir ];
    };
  };
}
