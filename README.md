# NixOS NVIDIA vGPU Module

This module unlocks vGPU functionality on your consumer NVIDIA card.

This module is for host machines, it installs a merged driver, meaning the host can use the GPU at the same time as guests.

> [!WARNING]  
> Activating this module may make some games stop working on the host, check [Known Issues](#known-issues).

## Installation:

1. Add Module to NixOS

   1. In a non-flake configuration you'll have to [add flake support](https://nixos.wiki/wiki/Flakes#:~:text=nix%2Dcommand%20flakes%27-,Enable%20flakes%20permanently%20in%20NixOS,-Add%20the%20following) to your system, with this method you'll also have to build with the additional '--impure' flag. Add this to your nixOS configuration:
   ```nix
   # configuration.nix
     imports = [
       (builtins.getFlake "https://github.com/CollinDewey/nixos-nvidia-vgpu/archive/refs/heads/main.zip").nixosModules.nvidia-vgpu
     ];

     hardware.nvidia.vgpu = #...module config...

   ```

   2. In a flake configuration you'll have to add the following.
   ```nix
   # flake.nix
   {
     inputs = {
       nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

       nixos-nvidia-vgpu = {
         url = "github:CollinDewey/nixos-nvidia-vgpu";
         inputs.nixpkgs.follows = "nixpkgs";
       };
     };

     outputs = {self, nixpkgs, nixos-nvidia-vgpu, ...}: {
       nixosConfigurations.HOSTNAME = nixpkgs.lib.nixosSystem {
         # ...
         modules = [
           nixos-nvidia-vgpu.nixosModules.default
           {
             hardware.nvidia.vgpu = #...module config...
           }
           # ...
         ];
       };
     };
   ```
2. Then add the module configuration to activate vGPU, example:
```nix
  hardware.nvidia.vgpu = {
    enable = true; # Install NVIDIA KVM vGPU + GRID driver + Activates required systemd services
    #vgpu_driver_src.sha256 = "sha256-uXBzzFcDfim1z9SOrZ4hz0iGCElEdN7l+rmXDbZ6ugs="; # use if you're getting the `Unfortunately, we cannot download file...` error # find hash with `nix hash file foo.txt`  
    #copyVGPUProfiles = { # Use if your graphics driver isn't supported yet
    #  "1f11:0000" = "1E30:12BA"; # RTX 2060 Mobile 6GB (is already supported in the repo)
    #};
    fastapi-dls = { # License server for unrestricted use of the vgpu driver in guests
      enable = true;
      #host = "192.168.1.81"; # Defaults to system hostname, use this setting to override
      #port = 53492; # Default is 443
      #timeZone = "Europe/Lisbon"; # Defaults to system TZ (Needs to be the same as the TZ in the VM)
      #dataDir = "/services/fastapi-dls"; # Default is "/var/lib/fastapi-dls"
    };
    #profile_overrides = {
    #  "GeForce RTX 2070-2" = {
    #    numDisplays = 2;
    #    vramMB = 4096;
    #    displaySize = { 
    #      width = 1920;
    #      height = 1080;
    #    };
    #    cudaEnabled = true;
    #    frameLimiter = false;
    #  };
    #};
  };
```
- This will attempt to compile and install a merged driver which merges the common NVIDIA linux driver and their GRID driver to share its GPU with multiple users. We can't provide the GRID driver, so you will be prompted with `nix-store --add-fixed...` to add it;  
  
  You'll need to get it [from NVIDIA](https://www.nvidia.com/object/vGPU-software-driver.html), you have to sign up and make a request that might take some days or refer to the [Discord VGPU-Unlock Community](https://discord.com/invite/5rQsSV3Byq) for support;  

  If you're still getting the `Unfortunately, we cannot download file...` error, use the option `vgpu_driver_src.sha256` to override the hardcoded hash. Find the hash of the file with `nix hash file file.zip`.

## Requirements

- Unlockable consumer NVIDIA GPU card (can't be `Ampere` architecture)
  - [These](https://github.com/VGPU-Community-Drivers/vGPU-Unlock-patcher/blob/550.90/patch.sh) are the graphic cards the driver supports.  
    Listed below for convenience
    ```
    RTX 2080 Ti
    RTX 2070 Super 8GB
    RTX 2080 Super 8GB
    RTX 2060 12GB
    RTX 2060 Mobile 6GB
    GTX 1660 6GB
    GTX 1650 Ti Mobile 4GB
    Quadro RTX 4000
    Quadro T400 4GB
    GTX 1050 Ti 4GB
    TITAN X
    GTX 1080 Ti
    GTX 1070
    GTX 1030 -> Tesla P40
    Tesla M40 -> Tesla M60
    GTX 980 -> Tesla M60
    GTX 980M -> Tesla M60
    # GTX 950M -> Tesla M10
    ```
    If yours is not in this list, you'll have to add support for your graphics card through `copyVGPUProfiles` option, please refer to [The official VGPU-Community-Drivers README](https://github.com/VGPU-Community-Drivers/vGPU-Unlock-patcher) for figuring out the right values for your graphics card.
  
      - Use the option as shown in the module configuration options, for example:
        ```nix
        copyVGPUProfiles = {
          "1f11:0000" = "1E30:12BA"; # RTX 2060 Mobile 6GB (is already supported in the repo)
        };
        ```
        would generate the vcfgclone line:  
        ```sh
        vcfgclone ${TARGET}/vgpuConfig.xml 0x1E30 0x12BA 0x1f11 0x0000
        ```
        The option adds vcfgclone lines to the patch.sh script of the vgpu-unlock-patcher.  
        They copy the vGPU profiles of officially supported GPUs specified by the attribute value ("1E30:12BA" in the example) to the video card specified by the attribute name ("1f11:0000" in the example). Not required when vcfgclone line with your GPU is already in the script. CASE-SENSETIVE, use UPPER case for the attribute value. Copy profiles from a GPU with a similar chip or at least architecture, otherwise nothing will work. See patch.sh for working vcfgclone examples.  

        If you found a working vcfgclone line that works and isn't in the repo yet, consider sharing it in the [VGPU-Unlock discord](https://discord.com/invite/5rQsSV3Byq) or with a maintainer of the [VGPU Unlock Community Repo](https://github.com/VGPU-Community-Drivers/vGPU-Unlock-patcher) for it to be added.

### Tested in

- Kernel `6.6.44` with a `NVIDIA GeForce RTX 2070 Super` in `NixOS 24.05.20240805.883180e`. 

## Guest VM

### Windows

In the Windows VM you need to install the appropriate drivers too, if you use an A profile([difference between profiles](https://youtu.be/cPrOoeMxzu0?t=1244)) for example (from the `mdevctl types` command) you can use the normal driver from the [NVIDIA Licensing Server](#nvidia-drivers), if you want a Q profile, you're gonna need to get the driver from the [NVIDIA servers](#nvidia-drivers) and patch it with the [Community vGPU Unlock Patcher](https://github.com/VGPU-Community-Drivers/vGPU-Unlock-patcher).

Besides the above profiles there are vGaming profiles, the ones I recommend, I used the special `GeForce RTX 2070-` profiles (from `mdevctl types`).  
If using this profile, you should be able to install the normal corresponding NVIDIA driver for the windows guest, it will support vulkan, opengl, directx and such for games but not CUDA.  
If you're having trouble with the licensing (altho fastapi-dls should be able to deal with it), you might have to install a specific Cloud Gaming driver.
> vGaming is specially licensed.  
> There's no trial and you need to buy a compute cluster from NVIDIA.  
> But Amazon has this and they host the drivers for people to use.
> The link comes from their bucket that has the vGaming drivers

Ask in the [VGPU-Unlock discord](https://discord.com/invite/5rQsSV3Byq) for the correct version if this is the case.

### nvidia-drivers

To get the NVIDIA vgpu drivers: downloads are available from NVIDIA site [here](http://nvid.nvidia.com/dashboard/), evaluation account may be obtained [here](http://www.nvidia.com/object/vgpu-evaluation.html)  
For guest drivers for windows get the ones with the name `Microsoft Hyper-V Server`  
To check and match versions see [here](https://docs.nvidia.com/grid/index.html).

## Additional Notes

To test if everything is installed correctly run `nvidia-smi vgpu` and `mdevctl types`, if there is no output, something went wrong.

You can also check if the services `nvidia-vgpu-mgr` and `nvidia-vgpud` executed without errors with `systemctl status nvidia-vgpud` and `systemctl status nvidia-vgpu-mgr`. (or something like `journalctl -fu nvidia-vgpud` to see the logs in real time)

If you set up fastapi-dls correctly, you should get a notification when your windows VM starts saying it was successful. In the Linux or Windows guest you can also run `nvidia-smi -q  | grep -i "License"` or `& 'nvidia-smi' -q | Select-String "License"` respectively to check.

I've tested creating an mdev on my own `NVIDIA GeForce RTX 2060 Mobile` by running:
```bash
> sudo su

> uuidgen
ce851576-7e81-46f1-96e1-718da691e53e

> lspci -D -nn | grep -i NVIDIA # to find the right address
0000:01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU106M [GeForce RTX 2060 Mobile] [10de:1f11] (rev a1)
0000:01:00.1 Audio device [0403]: NVIDIA Corporation TU106 High Definition Audio Controller [10de:10f9] (rev a1)
0000:01:00.2 USB controller [0c03]: NVIDIA Corporation TU106 USB 3.1 Host Controller [10de:1ada] (rev a1)
0000:01:00.3 Serial bus controller [0c80]: NVIDIA Corporation TU106 USB Type-C UCSI Controller [10de:1adb] (rev a1)

> mdevctl start -u ce851576-7e81-46f1-96e1-718da691e53e -p 0000:01:00.0 --type nvidia-258 && mdevctl start -u b761f485-1eac-44bc-8ae6-2a3569881a1a -p 0000:01:00.0 --type nvidia-258 && mdevctl define --auto --uuid ce851576-7e81-46f1-96e1-718da691e53e && mdevctl define --auto --uuid b761f485-1eac-44bc-8ae6-2a3569881a1a
```
That creates two VGPUs in my graphics card (because my card has 6Gb so 3Gb each VGPU. It needs to devide evenly, so I could also do 3 VGPUs of 2Gb each for example, but it's not possible to have 1 VGPU of 4Gb and one of 2Gb)

check if they were created successfully with `mdevctl list`
```bash
 ✘ ⚡ root@nixOS-Laptop  /home/yeshey  mdevctl list
ce851576-7e81-46f1-96e1-718da691e53e 0000:01:00.0 nvidia-258 (defined)
b761f485-1eac-44bc-8ae6-2a3569881a1a 0000:01:00.0 nvidia-258 (defined)
```

---

For more help [Join VGPU-Unlock discord for Support](https://discord.com/invite/5rQsSV3Byq)

## Known Issues

- **Some games stop working on host** (DXVK?), [Issue on GPU Unlocking discord](https://discord.com/channels/829786927829745685/1192188752915869767)

## Acknowledgements

- [Yeshey's Module](https://github.com/Yeshey/nixos-nvidia-vgpu)
- [danielfullmer's module](https://github.com/danielfullmer/nixos-nvidia-vgpu)
- [vGPU Unlock Patcher](https://github.com/VGPU-Community-Drivers/vGPU-Unlock-patcher)
