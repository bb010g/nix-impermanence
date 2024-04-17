flakeArgs@{ config, inputs, lib, ... }:

let
  flakeConfig = config;
in
{
  config.debug = true;
  config.flake.debug = lib.mkIf config.debug { args = flakeArgs; };
  config.flake.homeManagerModules = inputs.base.homeManagerModules // { };
  config.flake.nixosModules = inputs.base.nixosModules // {
    check-nixosManual = { config, lib, ... }: {
      config = {
        documentation.nixos.includeAllModules = true;
      };
    };
  };
  config.perSystem = { config, pkgs, system, ... }: {
    checks = {
      inherit (config.legacyPackages.check-nixosManual)
        nixos-configuration-reference-manpage
        ;
    };
    legacyPackages.check-nixosManual = (inputs.nixpkgs.lib.nixosSystem {
      inherit pkgs system;
      modules = [
        flakeConfig.flake.nixosModules.impermanence
        flakeConfig.flake.nixosModules.check-nixosManual
      ];
    }).config.system.build.manual;
  };
  config.systems = import inputs.systems;
}
