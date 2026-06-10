{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.programs.xcodes;
  xcodes = lib.getExe' cfg.package "xcodes";
  installDirectory = toString cfg.installDirectory;
  versionInstalledChecks = lib.concatMapStringsSep "\n" (version: ''
    if ! printf '%s\n' "$available_xcodes" | grep -F -- ${lib.escapeShellArg version} >/dev/null; then
      echo "error: requested Xcode version was not found by xcodes: ${version}" >&2
      echo "Run '${xcodes} list' to see valid version strings." >&2
      exit 1
    fi

    if ! printf '%s\n' "$installed_xcodes" | grep -F -- ${lib.escapeShellArg version} >/dev/null; then
      echo "Installing Xcode ${version} with xcodes"
      ${xcodes} install ${lib.escapeShellArg version} --experimental-unxip --directory ${lib.escapeShellArg installDirectory} || {
        echo "error: failed to install Xcode ${version}" >&2
        exit 1
      }
    else
      echo "Xcode ${version} already appears to be installed; skipping"
    fi
  '') cfg.versions;
  removalChecks = lib.concatMapStringsSep "\n" (version: ''
    if printf '%s\n' "$installed_xcodes" | grep -F -- ${lib.escapeShellArg version} >/dev/null; then
      echo "Uninstalling Xcode ${version} with xcodes"
      ${xcodes} uninstall ${lib.escapeShellArg version} --directory ${lib.escapeShellArg installDirectory} --empty-trash || {
        echo "error: failed to uninstall Xcode ${version}" >&2
        exit 1
      }
    else
      echo "Xcode ${version} is not installed; skipping uninstall"
    fi
  '') cfg.removeVersions;
  explicitSelectTarget = if cfg.selectPath != null then toString cfg.selectPath else null;
  managedVersions = lib.concatStringsSep "\n" cfg.versions;
in
{
  options.programs.xcodes = {
    enable = lib.mkEnableOption "XcodesOrg xcodes-based Xcode management";

    package = lib.mkPackageOption pkgs "xcodes" { };

    versions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "27 beta" ];
      description = ''
        Xcode versions or names to pass directly to `xcodes install`.
        Beta strings are supported when the xcodes CLI supports them.
      '';
    };

    selectVersion = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "27 beta";
      description = "Version/name to select after installation.";
    };

    removeVersions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "26.5" ];
      description = "Additional installed Xcode versions to uninstall after requested versions are installed.";
    };

    pruneUnmanaged = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Uninstall installed Xcode versions that are not listed in programs.xcodes.versions.";
    };

    selectPath = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
      default = null;
      example = "/Applications/Xcode-27 beta.app";
      description = "Explicit Xcode.app path to select instead of deriving one from selectVersion.";
    };

    installDirectory = lib.mkOption {
      type = lib.types.either lib.types.path lib.types.str;
      default = "/Applications";
      description = "Directory where xcodes installs Xcode.app bundles.";
    };

    acceptLicense = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run `xcodebuild -license accept` after selecting Xcode.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    assertions = [
      {
        assertion = cfg.selectPath == null || cfg.selectVersion == null;
        message = "programs.xcodes.selectPath and programs.xcodes.selectVersion are mutually exclusive.";
      }
      {
        assertion = pkgs.stdenv.isDarwin;
        message = "programs.xcodes can only be enabled on Darwin.";
      }
    ];

    system.activationScripts.extraActivation.text = lib.mkAfter ''
      echo "Managing Xcode installations with xcodes"

      available_xcodes="$(${xcodes} list 2>/dev/null)" || {
        echo "error: failed to list available Xcode versions with xcodes" >&2
        exit 1
      }

      installed_xcodes="$(${xcodes} installed 2>/dev/null || true)"
      ${versionInstalledChecks}

      installed_xcodes="$(${xcodes} installed 2>/dev/null || true)"
      ${removalChecks}

      ${lib.optionalString (cfg.pruneUnmanaged && cfg.versions != [ ]) ''
        managed_versions=${lib.escapeShellArg managedVersions}
        while IFS= read -r installed_line; do
          [ -n "$installed_line" ] || continue
          installed_version="$(printf '%s\n' "$installed_line" | sed -E 's#[[:space:]]+/.*$##; s#[[:space:]]*\([^)]*\)$##')"
          if [ -z "$installed_version" ]; then
            echo "error: failed to parse installed Xcode version from: $installed_line" >&2
            exit 1
          fi
          if ! printf '%s\n' "$managed_versions" | grep -Fx -- "$installed_version" >/dev/null; then
            echo "Uninstalling unmanaged Xcode $installed_version with xcodes"
            ${xcodes} uninstall "$installed_version" --directory ${lib.escapeShellArg installDirectory} --empty-trash || {
              echo "error: failed to uninstall unmanaged Xcode $installed_version" >&2
              exit 1
            }
          fi
        done <<EOF
$installed_xcodes
EOF
      ''}

      installed_xcodes="$(${xcodes} installed 2>/dev/null || true)"

      ${lib.optionalString (cfg.selectPath != null || cfg.selectVersion != null) ''
        ${lib.optionalString (cfg.selectPath != null) ''
          select_target=${lib.escapeShellArg explicitSelectTarget}
        ''}
        ${lib.optionalString (cfg.selectPath == null && cfg.selectVersion != null) ''
          select_target="$(printf '%s\n' "$installed_xcodes" | grep -F -- ${lib.escapeShellArg cfg.selectVersion} | head -n 1 | sed -E 's#^.*[[:space:]](/.*\.app)$#\1#')"
          if [ -z "$select_target" ]; then
            echo "error: requested Xcode selection version is not installed: ${cfg.selectVersion}" >&2
            exit 1
          fi
          if [ "$select_target" = "$(printf '%s\n' "$installed_xcodes" | grep -F -- ${lib.escapeShellArg cfg.selectVersion} | head -n 1)" ]; then
            echo "error: failed to determine installed Xcode app path for version: ${cfg.selectVersion}" >&2
            echo "Matching xcodes installed line: $select_target" >&2
            exit 1
          fi
        ''}

        if [ -d "$select_target" ]; then
          echo "Selecting $select_target"
          /usr/bin/xcode-select -s "$select_target/Contents/Developer" || {
            echo "error: failed to select Xcode at $select_target" >&2
            exit 1
          }
        else
          echo "error: requested Xcode selection path does not exist: $select_target" >&2
          exit 1
        fi
      ''}

      ${lib.optionalString cfg.acceptLicense ''
        if command -v /usr/bin/xcodebuild >/dev/null 2>&1; then
          /usr/bin/xcodebuild -license accept || true
        fi
      ''}
    '';
  };
}
