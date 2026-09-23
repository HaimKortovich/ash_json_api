{
  description = "AshJsonApi development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  nixConfig = {
    netrc-file = "/etc/nix/netrc";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        beamPackages = pkgs.beam27Packages;
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            beamPackages.elixir
            elixir-ls
            git
            nodejs
          ];
        };
      });
}
