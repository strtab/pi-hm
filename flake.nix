{
  description = "Home Manager module for the pi coding agent";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    pi.url = "github:earendil-works/pi/stable";
    pi.inputs.nixpkgs.follows = "nixpkgs";
    pi.inputs.nixpkgs-darwin-x64.follows = "";
  };

  outputs =
    { self, pi, ... }:
    {
      homeModules.default = import ./home.nix pi;
      homeModules.pi = self.homeModules.default;

      # Linux only
      packages = removeAttrs pi.packages [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
    };
}
