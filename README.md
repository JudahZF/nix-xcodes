# nix-xcodes

`nix-xcodes` is a small nix-darwin module for orchestrating Apple Xcode installations with the XcodesOrg `xcodes` CLI packaged by nixpkgs.

It does **not** put Xcode itself in the Nix store. Xcode is a large, Apple-authenticated, mutable `/Applications` install. This flake makes the surrounding workflow declarative: install the `xcodes` CLI, request Xcode versions, select one with `xcode-select`, and optionally accept the license.

## Usage

```nix
{
  inputs.nix-xcodes = {
    url = "git+https://codeberg.org/JudahZF/nix-xcodes.git";
    inputs.nixpkgs.follows = "nixpkgs-darwin";
  };

  outputs = { nix-darwin, nix-xcodes, ... }: {
    darwinConfigurations.my-mac = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        nix-xcodes.darwinModules.default
        {
          programs.xcodes = {
            enable = true;
            versions = [ "27 beta" ];
            selectVersion = "27 beta";
            acceptLicense = true;
          };
        }
      ];
    };
  };
}
```

## Authentication

Do not put Apple ID, password, app-specific passwords, team IDs, or session tokens in Nix.

Authenticate manually before activation needs to install Xcode:

```sh
xcodes auth login
```

`xcodes` will use your Keychain/session after that.

## Options

All options live under `programs.xcodes`:

- `enable`: enable the module.
- `package`: the `xcodes` CLI package, defaulting to `pkgs.xcodes`.
- `versions`: strings passed directly to `xcodes install`, for example `[ "27 beta" ]`.
- `selectVersion`: version/name used to derive an app path under `installDirectory`.
- `selectPath`: explicit `Xcode.app` path to select instead of deriving one from `selectVersion`.
- `installDirectory`: defaults to `/Applications`.
- `acceptLicense`: run `xcodebuild -license accept` after selection.

## Notes

The activation script is intentionally idempotent: it checks `xcodes installed` and skips requested versions that already appear in the installed list. If `xcodes` changes its output format, you may need to use `selectPath` for exact selection behavior.
