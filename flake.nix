{
  description = "Home Manager module for the pi coding agent";

  inputs = {
    pi.url = "github:earendil-works/pi/stable";
  };

  outputs =
    { self, pi }:
    {
      homeModules.default = import ./home.nix pi;
      homeModules.pi = self.homeModules.default;
      packages = pi.packages;
    };
}
