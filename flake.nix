{
  description = "NixOS module which provides NVIDIA vGPU functionality";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }: {
    nixosModules.nvidia-vgpu = ./module.nix;
    packages."x86_64-linux".default = import ./windows.nix { inherit nixpkgs; };
  };
}
