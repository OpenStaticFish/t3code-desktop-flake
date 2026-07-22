# T3 Code Nightly Flake

Installs the Linux x86_64 T3 Code nightly as an AppImage and updates it from
upstream GitHub releases. The AppImage is stored outside `/nix/store` at
`$XDG_DATA_HOME/t3code-nightly` (or `~/.local/share/t3code-nightly`) because
Nix store paths are immutable.

Every update is SHA-256 verified against the digest published in the GitHub
release. The Home Manager module runs a user timer every three hours, matching
T3 Code's nightly release cadence. Launching `t3code` also checks for updates.

## Home Manager

Add this flake as an input and import its Home Manager module:

```nix
{
  inputs.t3code-nightly = {
    url = "github:OpenStaticFish/t3code-desktop-flake";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { home-manager, t3code-nightly, ... }: {
    homeConfigurations.your-user = home-manager.lib.homeManagerConfiguration {
      # ...
      modules = [
        t3code-nightly.homeManagerModules.default
        {
          programs.t3code-nightly.enable = true;
        }
      ];
    };
  };
}
```

To check more or less often, set a systemd duration:

```nix
programs.t3code-nightly.updateInterval = "1h";
```

Set `programs.t3code-nightly.autoUpdate = false` to keep launch-time update
checks while disabling the background timer.

## Direct Use

```bash
nix run github:OpenStaticFish/t3code-desktop-flake
```

The package supports `x86_64-linux`, the only Linux architecture for which T3
Code currently publishes a nightly AppImage.
