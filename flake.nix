{
  description = "NixOS module which provides NVIDIA vGPU functionality";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
  };

  outputs = { nixpkgs, ... }: let
    pkgs = import nixpkgs { system = "x86_64-linux"; };
    gnrl-version = "535.161.07";
    vgpu-version = "535.161.05";
    grid-version = "535.161.08";
    wdys-version = "538.46";
    release-version = "16.5";
    minimum-kernel-version = "6.1"; # Unsure of the actual minimum. 6.1 LTS should do.
    maximum-kernel-version = "6.9";
  in {
    nixosModules.nvidia-vgpu = import ./module.nix { inherit pkgs gnrl-version vgpu-version grid-version wdys-version minimum-kernel-version maximum-kernel-version; };
    packages."x86_64-linux".default = import ./windows.nix { inherit pkgs wdys-version release-version; };
  };
}
