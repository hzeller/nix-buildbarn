{ config, pkgs, lib, ... }:

let
  bb-remote-execution-flake = builtins.getFlake (toString ./bb-remote-execution);
  bb-re-pkg = bb-remote-execution-flake.packages.${pkgs.system}.default;

  # Hostnames that run the bb-storage and bb-scheduler
  cas-host = "feynman";
  scheduler-host = "feynman";

  base-dir = "/var/lib/rbe-runner";
  default-use-cores = 24;

  # --- bb_runner ---
  # TODO: maybe not needed anymore with id. Initially I planned to have multiple
  # runners, but turns out a single one is sufficient with concurrency.
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
        maximumCacheSizeBytes = 20 * 1024 * 1024 * 1024; # 20 GB
        cacheReplacementPolicy = "LEAST_RECENTLY_USED";
      };
      runners = [
        {
          endpoint = { address = "unix://${base-dir}/worker-${id}/runner.sock"; };
          concurrency = default-use-cores;
          workerId = { id = "empty-${id}-${config.networking.hostName}"; };
          platform = {};
        }
        {
          endpoint = { address = "unix://${base-dir}/worker-${id}/runner.sock"; };
          concurrency = default-use-cores;
          workerId = { id = "linux-${id}-${config.networking.hostName}"; };
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

  runner-fhs = pkgs.buildFHSEnv {
    name = "bb-runner-fhs";
    targetPkgs = pkgs: with pkgs; [
      coreutils bash gawk gnused gnutar
      gzip bzip2 xz zstd unzip
      file findutils git python3
      glibc glibc.dev gcc zlib zlib.dev linuxHeaders
    ];
    runScript = "${bb-re-pkg}/bin/bb_runner";
  };

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

    # To inspect e.g. the /tmp directory, use nsenter
    # See README.md
    serviceConfig = {
      User = "rbe-runner";
      Group = "rbe-runner";
      ExecStartPre = pkgs.writeShellScript "bb-runner-pre" ''
        mkdir -p ${base-dir}/worker-1/build
        rm -f ${base-dir}/worker-1/runner.sock
      '';
      ExecStart = "${runner-fhs}/bin/bb-runner-fhs ${runnerConfigFile}";
      Restart = "always";
      RestartSec = "3s";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ base-dir ];
      # This is our launcher script that makes nix store paths happen if needed.
      Environment = [ "BB_RUNNER_COMMAND_WRAPPER=${./nix-runner-wrapper.sh}" ];
    };
  };

  systemd.services.bb-worker = {
    description = "Buildbarn Worker";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "bb-runner.service" "nix-daemon.service"];
    requires = [ "bb-runner.service" "nix-daemon.service" ];

    serviceConfig = {
      User = "rbe-runner";
      Group = "rbe-runner";
      ExecStartPre = pkgs.writeShellScript "bb-worker-pre" ''
        mkdir -p ${base-dir}/worker-1/build
        mkdir -p ${base-dir}/worker-1/cache

        # Use 1.2x physical cores for concurrency. We use the fixed worker
        # config file as template and patch it up at start-up.
        CORES=$(($(nproc) * 12 / 10))
        ${pkgs.jq}/bin/jq --argjson cores "$CORES" '.buildDirectories[].runners[].concurrency = $cores' ${workerConfigFile} > ${base-dir}/worker-1/bb_worker.json
        # Wait for the runner socket to be available
        while [ ! -S ${base-dir}/worker-1/runner.sock ]; do
          sleep 0.5
        done
      '';
      ExecStart = "${bb-re-pkg}/bin/bb_worker ${base-dir}/worker-1/bb_worker.json";
      Restart = "always";
      RestartSec = "3s";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;

      # Since we're about to call nix-store -realise, make sure we see
      # the outer system daemon and talk to it.
      BindPaths = [ "/nix/var/nix/daemon-socket" ];
      BindReadOnlyPaths = [ "/etc/ssl/certs" ];  # validate HTTPS downloads
      Environment = [ "NIX_REMOTE=daemon" ];

      ReadWritePaths = [ base-dir ];
    };
  };
}
