{
  description = "Auto-updating T3 Code nightly AppImage for Home Manager";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSupportedSystems = nixpkgs.lib.genAttrs supportedSystems;

      mkT3Code =
        pkgs:
        let
          icon = pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/pingdotgg/t3code/9a0a07167f06/apps/desktop/resources/icon.png";
            hash = "sha256-rXMAXnje7dOKxoqQ/G16Ohub9A54IPhhlv9x1/aKcvw=";
          };

          launcher = pkgs.writeShellApplication {
            name = "t3code";
            runtimeInputs = with pkgs; [
              appimage-run
              coreutils
              curl
              jq
              util-linux
            ];
            text = ''
              data_root="''${XDG_DATA_HOME:-$HOME/.local/share}"
              data_dir="$data_root/t3code-nightly"
              appimage="$data_dir/T3-Code.AppImage"
              version_file="$data_dir/version"
              lock_file="$data_dir/update.lock"
              releases_url="https://api.github.com/repos/pingdotgg/t3code/releases?per_page=100"

              update_only=false
              if [ "''${1:-}" = "--update-only" ]; then
                update_only=true
                shift
              fi

              update() {
                local release_json download_path tag asset url digest expected actual

                mkdir -p -- "$data_dir"
                exec 9>"$lock_file"
                flock --exclusive 9

                release_json="$(mktemp --tmpdir="$data_dir" release.XXXXXX.json)"
                download_path="$appimage.new"
                rm -f -- "$download_path"

                if ! curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
                  --retry 3 --retry-all-errors --output "$release_json" "$releases_url"; then
                  rm -f -- "$release_json"
                  return 1
                fi

                if ! tag="$(jq --raw-output --exit-status '[.[] | select(.prerelease and (.draft | not))] | first | .tag_name' "$release_json")"; then
                  rm -f -- "$release_json"
                  return 1
                fi

                if [ -x "$appimage" ] && [ -r "$version_file" ] && [ "$(<"$version_file")" = "$tag" ]; then
                  rm -f -- "$release_json"
                  return 0
                fi

                if ! asset="$(jq --compact-output --exit-status --arg tag "$tag" '[.[] | select(.tag_name == $tag) | .assets[] | select(.name | endswith("-x86_64.AppImage"))] | first' "$release_json")"; then
                  rm -f -- "$release_json"
                  return 1
                fi
                rm -f -- "$release_json"

                if ! url="$(jq --raw-output --exit-status '.browser_download_url' <<<"$asset")" ||
                  ! digest="$(jq --raw-output --exit-status '.digest' <<<"$asset")"; then
                  return 1
                fi
                expected="$(printf '%s' "$digest" | cut --delimiter=: --fields=2)"
                if [ -z "$expected" ]; then
                  return 1
                fi

                if ! curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
                  --retry 3 --retry-all-errors --output "$download_path" "$url"; then
                  rm -f -- "$download_path"
                  return 1
                fi

                actual="$(sha256sum "$download_path")"
                actual="''${actual%% *}"
                if [ "$actual" != "$expected" ]; then
                  printf 'T3 Code nightly checksum verification failed.\n' >&2
                  rm -f -- "$download_path"
                  return 1
                fi

                chmod 0755 "$download_path"
                mv -- "$download_path" "$appimage"
                printf '%s\n' "$tag" > "$version_file.new"
                mv -- "$version_file.new" "$version_file"
              }

              if ! update; then
                if [ ! -x "$appimage" ]; then
                  printf 'Unable to download T3 Code nightly and no cached AppImage is available.\n' >&2
                  exit 1
                fi
                printf 'Unable to check for a T3 Code nightly update; using the cached AppImage.\n' >&2
              fi

              if [ "$update_only" = true ]; then
                exit 0
              fi

              # This launcher owns updates, avoiding concurrent writes by Electron's updater.
              export T3CODE_DISABLE_AUTO_UPDATE=1
              exec appimage-run "$appimage" "$@"
            '';
          };

          desktopItem = pkgs.makeDesktopItem {
            name = "t3code";
            desktopName = "T3 Code (Nightly)";
            comment = "A GUI for coding agents";
            exec = "t3code %U";
            icon = icon;
            categories = [
              "Development"
              "IDE"
            ];
            startupWMClass = "t3code";
            terminal = false;
          };
        in
        pkgs.symlinkJoin {
          name = "t3code-nightly";
          paths = [
            launcher
            desktopItem
          ];
          meta = {
            description = "T3 Code nightly, updated from upstream GitHub releases";
            homepage = "https://github.com/pingdotgg/t3code";
            mainProgram = "t3code";
            platforms = [ "x86_64-linux" ];
          };
        };
    in
    {
      packages = forAllSupportedSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          package = mkT3Code pkgs;
        in
        {
          default = package;
          t3code-nightly = package;
        }
      );

      apps = forAllSupportedSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/t3code";
        };
      });

      homeManagerModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.t3code-nightly;
        in
        {
          options.programs.t3code-nightly = {
            enable = lib.mkEnableOption "the auto-updating T3 Code nightly AppImage";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.default;
              defaultText = lib.literalExpression "inputs.t3code-nightly.packages.\${pkgs.system}.default";
              description = "The T3 Code nightly package to install.";
            };

            autoUpdate = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to check for a new nightly with a systemd user timer.";
            };

            updateInterval = lib.mkOption {
              type = lib.types.str;
              default = "3h";
              example = "1h";
              description = "The systemd duration between nightly update checks.";
            };
          };

          config = lib.mkIf cfg.enable {
            assertions = [
              {
                assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
                message = "T3 Code nightly currently publishes Linux AppImages only for x86_64-linux.";
              }
            ];

            home.packages = [ cfg.package ];

            systemd.user.services.t3code-nightly-update = lib.mkIf cfg.autoUpdate {
              Unit.Description = "Download the newest T3 Code nightly";
              Service = {
                Type = "oneshot";
                ExecStart = "${cfg.package}/bin/t3code --update-only";
              };
            };

            systemd.user.timers.t3code-nightly-update = lib.mkIf cfg.autoUpdate {
              Unit.Description = "Check for a new T3 Code nightly";
              Timer = {
                OnBootSec = "5m";
                OnUnitActiveSec = cfg.updateInterval;
                Persistent = true;
              };
              Install.WantedBy = [ "timers.target" ];
            };
          };
        };
    };
}
