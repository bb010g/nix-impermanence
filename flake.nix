{
  description = "Modules to help you handle persistent state on systems with ephemeral root storage";

  outputs = { self, ... }: {
    homeManagerModules.default = self.homeManagerModules.impermanence;
    homeManagerModules.impermanence = import ./home-manager.nix;
    nixosModules.default = self.nixosModules.impermanence;
    nixosModules.impermanence = import ./nixos.nix;
  };
}
