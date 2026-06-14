# Running buildbarn on Nix machines

WIP

## Configurations to distribute builds to various nix machines

The repo contains flakes to build the storage, scheduler and worker binaries
to run buildbarn. Also, configuration and service definitions to make everything
a simple change in the configuration.nix.

Since the runner calls will receive command lines that reference /nix/store/
paths that might not necessarily exist on the target machine there is a simple
`nix-wrapper.sh` script that calls `nix store --realise` to make it happen.

For that to work, we needed to convince the runner to prepend this script
to the command line; since were was no such option yet, a quick hack
to get it from an environment variable [has been added](./bb-remote-execution/patches/runner-command-wrapper.patch) (TODO: think about upstreaming something
like that, but possibly should be put in the configuration file).

## Setting up buildbarn

There are three components: bb-storage, bb-scheduler and bb-worker-runner.

Choose one machine to run the bb-storage and bb-scheduler.

Change the `cas-host` and `scheduler-host` names in the *.nix files to
point to this chosen machine (in my network, that is "feynman", change to
your hostname). (it is probably also a good idea to put an alias in your
nameserver or `/etc/hosts` calling it `rbe` or something).

On the scheduler machine, in your `/etc/nixos/configuration.nix`, put the
full path to the storage and the scheduler; also to the bb-worker-runner.nix
if you want to also run workers on it.

Put it in the `imports` part, typically this is near the top where also your
`./hardware-configuration.nix` is imported:

```nix
  imports =
    [
      ./hardware-configuration.nix
      /path/to/nix-buildbarn/bb-storage.nix
      /path/to/nix-buildbarn/bb-scheduler.nix
      /path/to/nix-buildbarn/bb-worker-runner.nix
    ];
```

... on all other machines, just add the `bb-worker-runner.nix` (double check
that the hostnames point to to your scheduler machine):

```nix
  imports =
    [
      ./hardware-configuration.nix
      /path/to/nix-buildbarn/bb-worker-runner.nix
    ];
```

## Using buildbarn from bazel


Let's assume the hostname is `rbe`, this is how you then invoke bazel:

```
bazel build --remote_cache=grpc://rbe:8980 --remote_executor=grpc://rbe:8981 ...
```

The machine you're running `bazel` on also needs to be a nix machine, as the
various paths to compilers and tools must be /nix/store references that can
be resolved by the `nix-wrapper.sh`.

Of course, adding this to the command line every time is tedious, so you can
also put it in your `~/.bazelrc`, but remember to comment out when
you're not on that network :)

```
build --remote_cache=grpc://rbe:8980
build --remote_executor=grpc://rbe:8981
```
)
