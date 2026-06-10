{
  description = "Declarative nix-darwin orchestration for XcodesOrg xcodes";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.xcodes;
          xcodes = pkgs.xcodes;
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          module-loads = pkgs.runCommand "nix-xcodes-module-loads" { } ''
            test -f ${./modules/darwin.nix}
            touch $out
          '';
        }
      );

      darwinModules.default = ./modules/darwin.nix;
      darwinModules.xcodes = ./modules/darwin.nix;
    };
}
