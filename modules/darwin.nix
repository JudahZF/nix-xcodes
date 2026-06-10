{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.programs.xcodes;
  xcodes = lib.getExe cfg.package;
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
  selectTarget =
    if cfg.selectPath != null then
      toString cfg.selectPath
    else if cfg.selectVersion != null then
      "${installDirectory}/Xcode-${cfg.selectVersion}.app"
    else
      null;
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
      description = "Installed Xcode versions to uninstall after requested versions are installed.";
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

      ${lib.optionalString (selectTarget != null) ''
        if [ -d ${lib.escapeShellArg selectTarget} ]; then
          echo "Selecting ${selectTarget}"
          /usr/bin/xcode-select -s ${lib.escapeShellArg selectTarget}/Contents/Developer || {
            echo "error: failed to select Xcode at ${selectTarget}" >&2
            exit 1
          }
        else
          echo "error: requested Xcode selection path does not exist: ${selectTarget}" >&2
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
