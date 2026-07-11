# Envoy proxy as entry-point for the bazel to get a compressed experience over
# the wire even if we can't use CAS compression.
{ pkgs, ... }:

let
  envoyConfig = {
    admin = {
      address = {
        socketAddress = { address = "0.0.0.0"; portValue = 9901; }; # Envoy admin UI
      };
    };

    staticResources = {
      listeners = [{
        name = "grpc_ingress";
        address = {
          socketAddress = { address = "0.0.0.0"; portValue = 8100; }; # Port Bazel connects to
        };
        filterChains = [{
          filters = [{
            name = "envoy.filters.network.http_connection_manager";
            typedConfig = {
              "@type" = "type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager";
              statPrefix = "grpc_json";
              # Crucial for gRPC: Force HTTP/2 downstream framing
              http2ProtocolOptions = {};
              routeConfig = {
                name = "local_route";
                virtualHosts = [{
                  name = "buildbarn_backend";
                  domains = [ "*" ];
                  routes = [{
                    match = { prefix = "/"; };
                    route = {
                      cluster = "buildbarn_storage";
                      timeout = "0s"; # Essential for long-lived gRPC streams
                    };
                  }];
                }];
              };
              httpFilters = [
                # 1. The Compressor Filter handles on-the-fly transport compression
                {
                  name = "envoy.filters.http.compressor";
                  typedConfig = {
                    "@type" = "type.googleapis.com/envoy.extensions.filters.http.compressor.v3.Compressor";
                    compressorLibrary = {
                      name = "envoy.compressor.gzip.server";
                      typedConfig = {
                        "@type" = "type.googleapis.com/envoy.extensions.compression.gzip.compressor.v3.Gzip";
                        # 1 = Best Speed / Lowest Latency (Optimal for build pipelines)
                        compressionLevel = "BEST_SPEED";
                      };
                    };
                    # Explicitly tell Envoy to compress binary gRPC payload types
                    contentType = [
                      "application/grpc"
                      "application/x-protobuf"
                    ];
                  };
                }
                # 2. Standard router filter
                {
                  name = "envoy.filters.http.router";
                  typedConfig = {
                    "@type" = "type.googleapis.com/envoy.extensions.filters.http.router.v3.Router";
                  };
                }
              ];
            };
          }];
        }];
      }];

      # Point Envoy to where Buildbarn is listening locally
      clusters = [{
        name = "buildbarn_storage";
        connectTimeout = "0.25s";
        type = "STATIC";
        # Crucial: Force Envoy to talk to Buildbarn using HTTP/2
        typedExtensionProtocolOptions = {
          "envoy.extensions.upstreams.http.v3.HttpProtocolOptions" = {
            "@type" = "type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions";
            explicitHttpConfig = {
              http2ProtocolOptions = {};
            };
          };
        };
        loadAssignment = {
          clusterName = "buildbarn_storage";
          endpoints = [{
            lbEndpoints = [{
              endpoint = {
                address = {
                  socketAddress = { address = "127.0.0.1"; portValue = 8980; };
                };
              };
            }];
          }];
        };
      }];
    };
  };

  # Convert the Nix attribute set into a strict JSON file inside the Nix store
  configFile = pkgs.writeText "envoy-config.json" (builtins.toJSON envoyConfig);

in {
  # Define the systemd service to lifecycle manage Envoy
  systemd.services.envoy-buildbarn-proxy = {
    description = "Envoy Edge Proxy for Buildbarn gRPC Compression";
    after = [ "network.target" "bb-storage.service"];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.envoy}/bin/envoy -c ${configFile}";
      Restart = "always";

      # Security & sandboxing primitives standard for NixOS services
      DynamicUser = true;
      CapabilityBoundingSet = "";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };
}
