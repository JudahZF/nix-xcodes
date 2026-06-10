{ inputs, ... }:
{
  imports = [ inputs.nix-xcodes.darwinModules.default ];

  programs.xcodes = {
    enable = true;
    versions = [ "27 beta" ];
    selectVersion = "27 beta";
    acceptLicense = true;
  };
}
