# Running buildbarn on Nix machines

WIP

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

(you can also put it in your `~/.bazelrc`, but remember to comment out when
you're not on that network

```
build --remote_cache=grpc://rbe:8980
build --remote_executor=grpc://rbe:8981
```
)
