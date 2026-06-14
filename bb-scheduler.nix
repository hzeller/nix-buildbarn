{ config, pkgs, lib, ... }:

let
  bb-remote-execution-flake = builtins.getFlake (toString ./bb-remote-execution);
  bb-re-pkg = bb-remote-execution-flake.packages.${pkgs.system}.default;

  cas-host = "meitner";
  scheduler-host = "meitner";

  sched-dir = "/var/lib/rbe-sched";

  # Configured here, then written to JSON as configuration input.
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
      grpc = { client = { address = "${cas-host}:8980"; }; };
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
    browserUrl = "http://${scheduler-host}:8080/";
    maximumMessageSizeBytes = 16777216;
  };
  schedulerConfigFile = pkgs.writeText "bb_scheduler.json" (builtins.toJSON schedulerConfig);

in
{
  users.groups.rbe-sched = {};
  users.users.rbe-sched = {
    isSystemUser = true;
    group = "rbe-sched";
    home = sched-dir;
    createHome = true;
  };

  systemd.services.bb-scheduler = {
    description = "Buildbarn Scheduler";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "bb-storage.service" ];

    serviceConfig = {
      User = "rbe-sched";
      Group = "rbe-sched";
      ExecStart = "${bb-re-pkg}/bin/bb_scheduler ${schedulerConfigFile}";
      Restart = "always";
      RestartSec = "3s";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
}
