{
  description = "Dependencies for development purposes";

  inputs.callFlake.url = "github:divnix/call-flake";
  inputs.flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  # inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.flake-parts.url = "github:bb010g/flake-parts/debug";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.systems.flake = false;
  inputs.systems.url = "github:nix-systems/default";

  outputs = inputs:
    let
      baseInputs = baseResult.inputs;
      baseOutPath = ../.;
      baseResult = getFlake (toString baseOutPath);
      baseSourceInfo = baseResult.sourceInfo;
      getFlake = if builtins ? currentSystem then builtins.getFlake else inputs.callFlake;
      virtualInputs = inputs // baseInputs // { base = baseResult; self = virtualResult; };
      virtualOutputs =
        inputs.flake-parts.lib.mkFlake { inputs = virtualInputs; } ./flake-module.nix;
      virtualResult = virtualOutputs // baseSourceInfo // {
        _type = "flake";
        inputs = virtualInputs;
        outPath = baseOutPath;
        outputs = virtualOutputs;
        sourceInfo = baseSourceInfo;
      };
    in
    virtualOutputs;
}
