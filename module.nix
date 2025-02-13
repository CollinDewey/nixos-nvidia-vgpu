{ pkgs, lib, config, ... }:

let
  cfg = config.hardware.nvidia.vgpu;
  gnrl-version = "550.90.07";
  vgpu-version = "550.90.05";
  grid-version = "550.90.07";
  wdys-version = "552.55";
  minimum-kernel-version = "6.1"; # Unsure of the actual minimum. 6.1 LTS should do.
  maximum-kernel-version = "6.9";
in
let
  combinedZipName = "NVIDIA-GRID-Linux-KVM-${vgpu-version}-${grid-version}-${wdys-version}.zip";
  requireFile = { name, ... }@args: pkgs.requireFile (rec {
    inherit name;
    url = "https://www.nvidia.com/object/vGPU-software-driver.html";
    message = ''
      Unfortunately, we cannot download file ${name} automatically.
      Please go to ${url} to download it yourself or ask the vgpu discord community for support (https://discord.com/invite/5rQsSV3Byq)
      You can see the related nvidia driver versions here: https://docs.nvidia.com/grid/index.html. Add it to the Nix store
      using either
        nix-store --add-fixed sha256 ${name}
      or
        nix-prefetch-url --type sha256 file:///path/to/${name}

      If you already added the file, maybe the sha256 is wrong, use "nix hash file ${name}" and the option vgpu_driver_src.sha256 to override the hardcoded hash.
    '';
  } // args);

  profileReplace = name: config: let 
    xmlCommand = ''xmlstarlet ed --inplace --pf --update "vgpuconfig/vgpuType[@name='${name}']'';
  in lib.concatStringsSep "\n" ([ "" ]
    ++ lib.optional (config.numDisplays != null)  ''${xmlCommand}/numHeads" --value ${toString config.numDisplays} vgpuConfig.xml''
    ++ lib.optional (config.cudaEnabled != null)  ''${xmlCommand}/cudaEnabled" --value ${toString config.cudaEnabled} vgpuConfig.xml''
    ++ lib.optional (config.frameLimiter != null) ''${xmlCommand}/frame_rate_limiter" --value ${(if config.frameLimiter then "1" else "0")} vgpuConfig.xml''
    ++ lib.optional (config.vramMB != null) ''
       ${xmlCommand}/profileSize" --value $(awk 'BEGIN {printf "0x%X", int((${toString config.vramMB}/1024) * 0x40000000)}') vgpuConfig.xml
       ${xmlCommand}/fbReservation" --value $(awk 'BEGIN {printf "0x%X", int(0x8000000 + (((${toString config.vramMB} / 1024) - 1) * 0x40000000) / 0x10)}') vgpuConfig.xml
       ${xmlCommand}/framebuffer" --value $(awk 'BEGIN {printf "0x%X", int(${toString config.vramMB} * (1024 * 1024) - (0x8000000 + (((${toString config.vramMB} / 1024) - 1) * 0x40000000) / 0x10))}') vgpuConfig.xml
       ''
    ++ lib.optional (config.displaySize.width != null) ''
       ${xmlCommand}/display/@width" --value ${toString config.displaySize.width} vgpuConfig.xml
       ${xmlCommand}/display/@height" --value ${toString config.displaySize.height} vgpuConfig.xml
       ${xmlCommand}/maxPixels" --value ${toString (config.displaySize.height * config.displaySize.width)} vgpuConfig.xml
       ''
  );

  mdevctl = pkgs.runCommand "mdevctl" { buildInputs = [ pkgs.makeWrapper ]; } ''
    mkdir -p $out/bin $out/etc $out/usr/lib/mdevctl/scripts.d/notifiers $out/usr/lib/mdevctl/scripts.d/callouts $out/lib/udev/rules.d
    ln -s /etc/mdevctl.d $out/etc/mdevctl.d
    ln -s /sys $out/sys
    substitute ${pkgs.mdevctl}/lib/udev/rules.d/60-mdevctl.rules $out/lib/udev/rules.d/60-mdevctl.rules \
      --replace /usr/sbin/ $out/
    makeWrapper ${pkgs.mdevctl}/bin/mdevctl $out/bin/mdevctl \
      --set MDEVCTL_ENV_ROOT $out
  '';

  compiled-driver = pkgs.stdenv.mkDerivation {
    name = "NVIDIA-Linux-x86_64-${gnrl-version}-merged-vgpu-kvm-patched";
    nativeBuildInputs = [ pkgs.p7zip pkgs.unzip pkgs.coreutils pkgs.bash pkgs.zstd ];
      system = "x86_64-linux";
      src = pkgs.fetchFromGitHub {
        owner = "VGPU-Community-Drivers";
        repo = "vGPU-Unlock-patcher";
        rev = "8f19e550540dcdeccaded6cb61a71483ea00d509";
        hash = "sha256-TyZkZcv7RI40U8czvcE/kIagpUFS/EJhVN0SYPzdNJM=";
        fetchSubmodules = true;
      };
      original_driver_src = pkgs.fetchurl {
        url = "https://download.nvidia.com/XFree86/Linux-x86_64/${gnrl-version}/NVIDIA-Linux-x86_64-${gnrl-version}.run";
        sha256 = "sha256-Uaz1edWpiE9XOh0/Ui5/r6XnhB4iqc7AtLvq4xsLlzM=";
      };
      vgpu_driver_src = if cfg.vgpu_driver_src.url != null then pkgs.fetchurl {
        url = cfg.vgpu_driver_src.url;
        sha256 = cfg.vgpu_driver_src.sha256;
      } else requireFile {
          name = combinedZipName;
          sha256 = cfg.vgpu_driver_src.sha256;
      };

      buildPhase = ''
        mkdir -p $out
        cd $TMPDIR
        ln -s $vgpu_driver_src ${combinedZipName}
        
        ${pkgs.unzip}/bin/unzip -j ${combinedZipName} Host_Drivers/NVIDIA-Linux-x86_64-${vgpu-version}-vgpu-kvm.run
        cp -a $src/* .
        cp -a $original_driver_src NVIDIA-Linux-x86_64-${gnrl-version}.run
        sed -i '0,/^    vcfgclone \''${TARGET}\/vgpuConfig.xml /s//${lib.attrsets.foldlAttrs (s: n: v: s + "    vcfgclone \\\${TARGET}\\/vgpuConfig.xml 0x${builtins.substring 0 4 v} 0x${builtins.substring 5 4 v} 0x${builtins.substring 0 4 n} 0x${builtins.substring 5 4 n}\\n") "" cfg.copyVGPUProfiles}&/' ./patch.sh
        
        bash ./patch.sh --force-nvidia-gpl-I-know-it-is-wrong --enable-nvidia-gpl-for-experimenting --repack general-merge
        cp -a NVIDIA-Linux-x86_64-${gnrl-version}-merged-vgpu-kvm-patched.run $out
      '';
  };
in
{
  options = with lib; {
    hardware.nvidia.vgpu = {
      enable = mkEnableOption "vGPU support";

      copyVGPUProfiles = mkOption {
        default = {};
        type = types.attrs;
        example = {
          "1122:3344" = "5566:7788";
          "1f11:0000" = "1E30:12BA"; # vcfgclone line for RTX 2060 Mobile 6GB. generates: vcfgclone ${TARGET}/vgpuConfig.xml 0x1E30 0x12BA 0x1f11 0x0000
        };
        description = ''
          Adds vcfgclone lines to the patch.sh script of the vgpu-unlock-patcher.
          They copy the vGPU profiles of officially supported GPUs specified by the attribute value to the video card specified by the attribute name. Not required when vcfgclone line with your GPU is already in the script. CASE-SENSETIVE, use UPPER case. Copy profiles from a GPU with a similar chip or at least architecture, otherwise nothing will work. See patch.sh for working vcfgclone examples.
          In the first example option value, it will copy the vGPU profiles of 5566:7788 to GPU 1122:3344 (vcfgclone ''${TARGET}/vgpuConfig.xml 0x5566 0x7788 0x1122 0x3344 in patch.sh).
        '';
      };

      vgpu_driver_src.url = mkOption {
        default = null;
        type = types.nullOr types.str;
        example = "https://example.com/${combinedZipName}";
        description = ''
          URL of the vgpu_driver_file to be downloaded from
        '';
      };

      vgpu_driver_src.sha256 = mkOption {
        default = "sha256-qzTsKUKKdplZFnmcz4r5zGGTruyM7e85zRu3hQDc0gA=";
        type = types.str;
        description = ''
          sha256 of the vgpu_driver file in case you're having trouble adding it with for Example `nix-store --add-fixed sha256 NVIDIA-GRID-Linux-KVM-535.129.03-537.70.zip`
          You can find the hash of the file with `nix hash file foo.txt`
        '';
      };

      profile_overrides = mkOption {
        description = "List of profiles to override";
        default = {};
        type = types.attrsOf (types.submodule { options = { #There are more settings than this, but this is enough for now
            numDisplays = mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              example = 2;
              description = "The number of displays";
            };
            vramMB = mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              example = 2048;
              description = "The VRAM size (in MB)";
            };
            displaySize = mkOption {
              type = types.submodule { options = {
                width = mkOption {
                  type = types.nullOr types.ints.positive;
                  default = null;
                  example = 2560;
                  description = "Display Width";
                };
                height = mkOption {
                  type = types.nullOr types.ints.positive;
                  default = null;
                  example = 1440;
                  description = "Display Height";
                };
              };};
              default = {};
              description = "Display Size";
            };
            cudaEnabled = mkOption {
              type = types.nullOr types.bool;
              default = null;
              example = true;
              description = "Enables CUDA";
            };
            frameLimiter = mkOption {
              type = types.nullOr types.bool;
              default = null;
              example = false;
              description = "Enables Framerate Limiter";
            };
          };
        });
        example = {
          "GRID P40-2A" = {
            numDisplays = 1;
            vramMB = 1024;
            displaySize = { 
              width = 1920;
              height = 1080;
            };
            cudaEnabled = true;
            frameLimiter = false;
          };
        };
      };

      fastapi-dls = mkOption {
        description = "fastapi-dls host server";
        default = {};
        type = types.submodule {
          options = {
            enable = mkEnableOption "Enable running the fastapi-dls host server";
            dataDir = mkOption {
              description = "Path to the fastapi-dls working directory";
              default = "/var/lib/fastapi-dls";
              example = "/opt/vgpu/data";
              type = types.path;
            };
            host = mkOption {
              description = "Your IP address or Hostname";
              default = config.networking.hostName;
              example = "192.168.1.81";
              type = types.str;
            };
            timeZone = mkOption {
              description = "Time zone of fastapi-dls";
              default = config.time.timeZone;
              example = "Europe/Lisbon";
              type = types.addCheck types.str (str: filter (c: c == " ") (stringToCharacters str) == []);
            };
            port = mkOption { 
              description = "Port to listen on.";
              default = "443";
              example = "53492";
              type = types.ints.unsigned;
            };
          };
        };
      };

      mdev = {
        enable = mkOption {
          type = types.bool;
          default = config.hardware.nvidia.vgpu.enable;
          example = false;
          description = "Enable mdev";
        };
        mdevctl.enable = mkOption {
          type = types.bool;
          default = config.hardware.nvidia.vgpu.enable;
          example = false;
          description = "Enable mdevctl";
        };
        device = mkOption {
          type = types.str;
          default = "0000:04:00.0";
          description = "PCI ID of graphics card. You can figure it with {command}`ls /sys/class/mdev_bus`.";
        };
        vgpus = mkOption {
          default = { };
          type = with types; attrsOf (submodule [ { options = { uuid = mkOption { type = with types; listOf str; }; }; } ]);
          description = ''
            Virtual GPUs to be used in Qemu. You can find devices via {command}`ls /sys/bus/pci/devices/*/mdev_supported_types`
            and find info about device via {command}`cat /sys/bus/pci/devices/*/mdev_supported_types/nvidia-261/description`
          '';
          example = {
            nvidia-261.uuid = [ "57d6c526-375a-466f-b9a7-963f63e91197" ];
          };
        };
      };
    };
  };

  config = lib.mkMerge [ ( lib.mkIf cfg.enable {
  
      assertions = (lib.attrValues (
        lib.mapAttrs (name: value: {
          assertion = (value.displaySize.width != null) == (value.displaySize.height != null);
          message = "Both width and height need to be set.";
        }) cfg.profile_overrides)) ++
        (lib.attrValues (
          lib.mapAttrs (name: value: {
          assertion = value.vramMB != null -> value.vramMB >= 384;
          message = "More than 384MB of VRAM is required.";
        }) cfg.profile_overrides)) ++
        [
        {
          assertion = cfg.enable -> lib.elem "nvidia" config.services.xserver.videoDrivers;
          message = "hardware.nvidia.vgpu.enable requires the nvidia driver to be available (services.xserver.videoDrivers).";
        }
        {
          assertion = cfg.enable
            -> (lib.versionAtLeast config.boot.kernelPackages.kernel.version minimum-kernel-version)
            -> (lib.versionOlder config.boot.kernelPackages.kernel.version maximum-kernel-version); # Patches supposedly support up till 6.8
          message = "hardware.nvidia.vgpu.enable requires a kernel at least ${minimum-kernel-version} and below ${maximum-kernel-version}";
        }
      ];

      hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable.overrideAttrs (
        { patches ? [], postUnpack ? "", postPatch ? "", preFixup ? "", ... }: {
        # Overriding https://github.com/NixOS/nixpkgs/tree/nixos-unstable/pkgs/os-specific/linux/nvidia-x11
        # that gets called from the option hardware.nvidia.package from here: https://github.com/NixOS/nixpkgs/blob/nixos-22.11/nixos/modules/hardware/video/nvidia.nix
        name = "NVIDIA-Linux-x86_64-${gnrl-version}-merged-vgpu-kvm-patched-${config.boot.kernelPackages.kernel.version}";
        version = "${gnrl-version}";

        src = "${compiled-driver}/NVIDIA-Linux-x86_64-${gnrl-version}-merged-vgpu-kvm-patched.run";

        patches = [];

        postPatch = (if postPatch != null then postPatch else "") + ''
          # Move path for vgpuConfig.xml into /etc
          sed -i 's|/usr/share/nvidia/vgpu|/etc/nvidia/vgpuConfig|' nvidia-vgpud

          substituteInPlace sriov-manage \
            --replace-fail lspci ${pkgs.pciutils}/bin/lspci \
            --replace-fail setpci ${pkgs.pciutils}/bin/setpci
        '';

        # HACK: Using preFixup instead of postInstall since nvidia-x11 builder.sh doesn't support hooks
        preFixup = preFixup + ''
          for i in libnvidia-vgpu.so.${vgpu-version} libnvidia-vgxcfg.so.${vgpu-version}; do
            install -Dm755 "$i" "$out/lib/$i"
          done
          patchelf --set-rpath ${pkgs.stdenv.cc.cc.lib}/lib $out/lib/libnvidia-vgpu.so.${vgpu-version}
          install -Dm644 vgpuConfig.xml $out/vgpuConfig.xml

          for i in nvidia-vgpud nvidia-vgpu-mgr; do
            install -Dm755 "$i" "$bin/bin/$i"
            # stdenv.cc.cc.lib is for libstdc++.so needed by nvidia-vgpud
            patchelf --interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
              --set-rpath $out/lib "$bin/bin/$i"
          done
          install -Dm755 sriov-manage $bin/bin/sriov-manage
        '';
      });

      systemd.services.nvidia-vgpud = {
        description = "NVIDIA vGPU Daemon";
        wants = [ "syslog.target" ];
        wantedBy = [ "multi-user.target" ];
        restartIfChanged = false;

        serviceConfig = {
          Type = "forking";
          ExecStart = "${lib.getBin config.hardware.nvidia.package}/bin/nvidia-vgpud";
          ExecStopPost = "${pkgs.coreutils}/bin/rm -rf /var/run/nvidia-vgpud";
          Environment = [ "__RM_NO_VERSION_CHECK=1" ];
        };
      };

      systemd.services.nvidia-vgpu-mgr = {
        description = "NVIDIA vGPU Manager Daemon";
        wants = [ "syslog.target" ];
        wantedBy = [ "multi-user.target" ];
        after = [ "nvidia-vgpud.service" ];
        restartIfChanged = false;

        serviceConfig = {
          Type = "forking";
          KillMode = "process";
          ExecStart = "${lib.getBin config.hardware.nvidia.package}/bin/nvidia-vgpu-mgr";
          ExecStopPost = "${pkgs.coreutils}/bin/rm -rf /var/run/nvidia-vgpu-mgr";
          Environment = [
            "__RM_NO_VERSION_CHECK=1"
            "LD_LIBRARY_PATH=${pkgs.glib.out}/lib:$LD_LIBRARY_PATH"
            "LD_PRELOAD=${pkgs.glib.out}/lib/libglib-2.0.so"
          ];
        };
      };
      
      boot.extraModprobeConfig = "options nvidia vup_sunlock=1 vup_qmode=1";

      environment.etc."nvidia/vgpuConfig/vgpuConfig.xml".source = "${pkgs.runCommand "vgpuConfigGen" { buildInputs = [ pkgs.xmlstarlet ]; } ''
          mkdir -p $out
          cd $out
          cp --no-preserve=mode ${config.hardware.nvidia.package}/vgpuConfig.xml vgpuConfig.xml
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList profileReplace config.hardware.nvidia.vgpu.profile_overrides)}
        ''}/vgpuConfig.xml";

      boot.kernelModules = [ "nvidia-vgpu-vfio" ];
    })

    (lib.mkIf cfg.mdev.mdevctl.enable {
      environment.systemPackages = [ mdevctl ];
      services.udev.packages = [ mdevctl ];
      environment.etc."mdevctl.d/.keep".text = "";
    })

    (lib.mkIf cfg.mdev.enable {
      systemd = let
        vgpus = lib.listToAttrs (lib.flatten (lib.mapAttrsToList
          (mdev: opt: map (id: lib.nameValuePair "nvidia-vgpu-${id}" { inherit mdev; uuid = id; }) opt.uuid)
          cfg.mdev.vgpus));
      in {
        services = lib.mapAttrs (_: opt:
          {
            description = "NVIDIA VGPU ${opt.uuid}";
            after = [ "nvidia-vgpu-mgr.service" ];
            wantedBy = [ "multi-user.target" ];
            restartIfChanged = false;

            unitConfig.ConditionDirectoryNotEmpty = "/sys/bus/pci/devices/${cfg.mdev.device}/mdev_supported_types";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${pkgs.bash}/bin/bash -c 'if [ ! -e /sys/bus/pci/devices/${cfg.mdev.device}/${opt.uuid} ]; then echo ${opt.uuid} > /sys/bus/pci/devices/${cfg.mdev.device}/mdev_supported_types/${opt.mdev}/create; fi'";
              ExecStop = "${pkgs.bash}/bin/bash -c 'if [ -e /sys/bus/pci/devices/${cfg.mdev.device}/${opt.uuid} ]; then echo 1 > /sys/bus/pci/devices/${cfg.mdev.device}/${opt.uuid}/remove; fi'";
            };
          }) vgpus;
      };
    })

    (lib.mkIf cfg.fastapi-dls.enable {
    
      virtualisation.oci-containers.containers = {
        fastapi-dls = {
          image = "collinwebdesigns/fastapi-dls";
          imageFile = pkgs.dockerTools.pullImage {
            imageName = "collinwebdesigns/fastapi-dls";
            imageDigest = "sha256:b7b5781a19058b7a825e8a4bb6982e09d0e390ee6c74f199ff9938d74934576c";
            sha256 = "sha256-1qvsVMzM4/atnQmxDMIamIVHCEYpxh0WDLLbANS2Wzw=";
          };
          volumes = [
            "${cfg.fastapi-dls.dataDir}/cert:/app/cert:rw"
            "${cfg.fastapi-dls.dataDir}/dls-db:/app/database"
          ];
          environment = {
            TZ = cfg.fastapi-dls.timeZone;
            DLS_URL = cfg.fastapi-dls.host;
            DLS_PORT = builtins.toString cfg.fastapi-dls.port;
            LEASE_EXPIRE_DAYS="90";
            DATABASE = "sqlite:////app/database/db.sqlite";
            DEBUG = "true";
          };
          extraOptions = [
          ];
          ports = [ "${builtins.toString cfg.fastapi-dls.port}:443" ];
          autoStart = false; # Started by fastapi-dls-mgr
        };
      };

      systemd.timers.fastapi-dls-mgr = {
        wantedBy = [ "multi-user.target" ];
        timerConfig = {
          OnActiveSec = "1s";
          OnUnitActiveSec = "1h";
          AccuracySec = "1s";
          Unit = "fastapi-dls-mgr.service";
        };
      };

      systemd.services.fastapi-dls-mgr = {
        path = [ pkgs.openssl ];
        requires = [ "${config.virtualisation.oci-containers.backend}.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
        script = ''
          WORKING_DIR=${cfg.fastapi-dls.dataDir}/cert
          CERT_CHANGED=false

          recreate_private () {
            echo "Recreating private key..."
            rm -f $WORKING_DIR/instance.private.pem
            openssl genrsa -out $WORKING_DIR/instance.private.pem 2048
          }

          recreate_public () {
            echo "Recreating public key..."
            rm -f $WORKING_DIR/instance.public.pem
            openssl rsa -in $WORKING_DIR/instance.private.pem -outform PEM -pubout -out $WORKING_DIR/instance.public.pem
          }

          recreate_certs () {
            echo "Recreating certificates..."
            rm -f $WORKING_DIR/webserver.key
            rm -f $WORKING_DIR/webserver.crt
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $WORKING_DIR/webserver.key -out $WORKING_DIR/webserver.crt -subj "/C=XX/ST=StateName/L=CityName/O=CompanyName/OU=CompanySectionName/CN=CommonNameOrHostname"
          }

          check_recreate() {
            echo "Checking if certificates need to be recreated..."
            if [ ! -e $WORKING_DIR/instance.private.pem ]; then
              echo "Private key missing, recreating..."
              recreate_private
              recreate_public
              recreate_certs
              CERT_CHANGED=true
            fi
            if [ ! -e $WORKING_DIR/instance.public.pem ]; then
              echo "Public key missing, recreating..."
              recreate_public
              recreate_certs
              CERT_CHANGED=true
            fi
            if [ ! -e $WORKING_DIR/webserver.key ] || [ ! -e $WORKING_DIR/webserver.crt ]; then
              echo "Webserver certificates missing, recreating..."
              recreate_certs
              CERT_CHANGED=true
            fi
            if ( ! openssl x509 -checkend 864000 -noout -in $WORKING_DIR/webserver.crt); then
              echo "Webserver certificate will expire soon, recreating..."
              recreate_certs
              CERT_CHANGED=true
            fi
          }

          echo "Ensuring working directory exists..."
          if [ ! -d $WORKING_DIR ]; then
            mkdir -p $WORKING_DIR
          fi

          check_recreate

          if ( ! systemctl is-active --quiet ${config.virtualisation.oci-containers.backend}-fastapi-dls.service); then
            echo "Starting ${config.virtualisation.oci-containers.backend}-fastapi-dls.service..."
            systemctl start ${config.virtualisation.oci-containers.backend}-fastapi-dls.service
          elif $CERT_CHANGED; then
            echo "Restarting ${config.virtualisation.oci-containers.backend}-fastapi-dls.service due to certificate change..."
            systemctl stop ${config.virtualisation.oci-containers.backend}-fastapi-dls.service
            systemctl start ${config.virtualisation.oci-containers.backend}-fastapi-dls.service
          fi
        '';
      };
    })
  ];
}
