{
  config,
  lib,
  pkgs,
  ...
}:
{
  hardware = {
    deviceTree = {
      enable = true;
      name = "eswin/eic7702-deepcomputing-fml13v03.dtb";
    };
    firmware = [
      (pkgs.runCommand "firmware-fml13v03" { } ''
        mkdir -p $out/lib/firmware
        cp ${config.system.build.secboot}/*.bin $out/lib/firmware
      '')
    ];
    enableRedistributableFirmware = true;
  };

  # Kernel 6.6.92 — includes critical display, HDMI, and stability fixes over 6.6.18:
  #   - 09467c5: Remove DRIVER_MODESET from IMG GPU (fixes Wayland compositor conflict)
  #   - 2fab721: Remove hardcoded HDMI clock whitelist (allows most display resolutions)
  #   - 4484e0c: Fix gamma timing (prevents display artifacts)
  #   - 7cc1d86: Fix Framework backlight pinctrl error
  #   - 3d3ce30: Fix HDMI suspend kernel panic
  boot.kernelPackages = lib.mkDefault (
    pkgs.linuxPackagesFor (
      pkgs.buildLinux {
        version = "6.6.92";
        modDirVersion = "6.6.92";
        src = pkgs.fetchFromGitHub {
          owner = "DC-DeepComputing";
          repo = "fml13v03_linux";
          rev = "417741216c08b3718c5ed541cce3523eb7ab20e4";
          hash = "sha256-lQYLKqhdQin0cydQJ22YK1Anzjsi4qI6SToYLH8/hPI=";
        };
        defconfig = "fml13v03_defconfig";

        # NixOS build-system patches (fix $(src) vs $(srctree), codec conflicts, etc).
        # Two patches from the 6.6.18 era are already fixed in 6.6.92:
        #   - eswin-ai-dsp: __clk_is_enabled now has extern declaration
        #   - eswin-headers: es_proc Makefile no longer copies headers
        kernelPatches = [
          {
            name = "fix-eswin-media-ext";
            patch = ./linux-fix-eswin-media-ext.patch;
          }
          {
            name = "fix-ap12275";
            patch = ./linux-fix-ap12275.patch;
          }
          {
            name = "fix-eswin-mem";
            patch = ./linux-fix-eswin-mem.patch;
          }
          {
            name = "fix-eswin-dev-buff";
            patch = ./linux-fix-eswin-dev-buff.patch;
          }
          {
            name = "fix-eswin-codec-conflict";
            patch = ./linux-fix-eswin-codec-conflict.patch;
          }
          {
            name = "fix-eswin-sysfs";
            patch = ./linux-fix-eswin-sysfs.patch;
          }
        ];

        structuredExtraConfig = with lib.kernel; {
          DWC_MIPI_TC_DPHY_GEN3 = no;
          DEBUG_INFO_BTF = lib.mkForce no;
          # Vendor modules referencing unexported symbols
          ESWIN_WATCHDOG = no;
          RSTKDUMP = no;
        };

        extraMakeFlags = [
          # zihintpause extension for assembler + GCC 15 compat
          "KCFLAGS=-Wa,-march=rv64imafdc_zicsr_zifencei_zihintpause -Wno-error=incompatible-pointer-types"
        ];
      }
    )
  );

  # Boot: U-Boot extlinux (no UEFI on this device)
  boot.loader = {
    grub.enable = lib.mkDefault false;
    generic-extlinux-compatible = {
      enable = lib.mkDefault true;
      configurationLimit = lib.mkDefault 10;
    };
  };

  # Kernel parameters for display and firmware loading
  boot.kernelParams = lib.mkDefault [
    "console=tty0"
    "console=ttyS0,115200"
    "earlycon"
    "rootwait"
    "clk_ignore_unused"
    "firmware_class.path=/lib/firmware/eic7x/"
  ];

  # Display: backlight defaults to off (bl_power=4) — turn it on at boot
  systemd.services.backlight-on = {
    description = "Turn on display backlight";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'if [ -e /sys/class/backlight/backlight/bl_power ]; then echo 0 > /sys/class/backlight/backlight/bl_power; echo 128 > /sys/class/backlight/backlight/brightness; fi'";
    };
  };

  system.build = {
    uboot = pkgs.buildUBoot {
      defconfig = "deepcomputing-fml13v03_defconfig";
      extraMeta.platforms = [ "riscv64-linux" ];
      filesToInstall = [
        "u-boot.bin"
        "u-boot.dtb"
      ];
      version = "2024.01";
      src = pkgs.fetchFromGitHub {
        owner = "DC-DeepComputing";
        repo = "fml13v03_u-boot";
        rev = "d68387b6204343f98d82164fb62613029dfc8528";
        hash = "sha256-cgVjGXityxsnqs/onLJ0E6tlLI4YH1LALUA/rM+LPUg=";
      };
      NIX_CFLAGS_COMPILE = "-Wno-implicit-function-declaration -Wno-incompatible-pointer-types -Wno-int-conversion";
    };
    opensbi =
      (pkgs.opensbi.overrideAttrs (
        _f: p: {
          src = pkgs.fetchFromGitHub {
            owner = "DC-DeepComputing";
            repo = "fml13v03_opensbi";
            rev = "37fc216159a439a4810900a109f45aa4b54e4b3a";
            hash = "sha256-RvZapBfQAokxVMNT2VU0tJqeI4LxMQTs1n+z74mR8XU=";
          };

          makeFlags = p.makeFlags ++ [
            "CHIPLET=BR2_CHIPLET_2"
            "CHIPLET_DIE_AVAILABLE=BR2_CHIPLET_1_DIE1_AVAILABLE"
            "PLATFORM_CLUSTER_X_CORE=BR2_CLUSTER_4_CORE"
            "MEM_MODE=BR2_MEMMODE_FLAT"
          ];
        }
      )).override
        {
          withPlatform = "eswin/eic770x";
          withPayload = "${config.system.build.uboot}/u-boot.bin";
          withFDT = "${config.system.build.uboot}/u-boot.dtb";
        };
    secboot = pkgs.pkgsCross.riscv64-embedded.stdenv.mkDerivation (_finalAttrs: {
      pname = "secboot";
      version = "0-unstable-2025-07-27";

      src = pkgs.fetchFromGitHub {
        owner = "DC-DeepComputing";
        repo = "fml13v03_secboot_fw";
        rev = "16edc598e626aae096e3dfe16f4781f6731a8dec";
        hash = "sha256-Fl1MwADKfM453Em+K6QBMfaHtxWK7Ehr/86+JmcNVY0=";
      };

      NIX_CFLAGS_COMPILE = "-no-pie";

      makeFlags = [
        "CROSS_COMPILE=${pkgs.pkgsCross.riscv64-embedded.stdenv.cc.targetPrefix}"
        "BIN_DIR_FOR_DOWNLOAD=${placeholder "out"}"
      ];

      preBuild = ''
        mkdir -p $out
      '';

      dontInstall = true;
    });
    firmware-tools =
      let
        pkgsx86_64 =
          if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then
            pkgs.buildPlatform
          else
            pkgs.pkgsCross.gnu64;
      in
      pkgsx86_64.stdenv.mkDerivation (finalAttrs: {
        name = "firmware-eswin-fml13v03";

        src = pkgsx86_64.fetchFromGitHub {
          owner = "DC-DeepComputing";
          repo = "fml13v03";
          rev = "e93f8903f9eb9fc34e9130881f56d6f2a08205c2";
          hash = "sha256-bMAYGA9/Ml5a0Eynmvcl+JGMZRf+1Uka43qCjxswO/s=";
        };

        sourceRoot = "${finalAttrs.src.name}/source";

        nativeBuildInputs = [
          pkgs.autoPatchelfHook
        ];

        buildInputs = [
          pkgsx86_64.stdenv.cc.cc
        ];

        installPhase = ''
          mkdir -p $out/bin
          mv firmware-eswin/nsign $out/bin/nsign

          patchelf --set-interpreter ${pkgsx86_64.stdenv.cc.libc}/lib/ld-linux-x86-64.so.2 $out/bin/nsign

          mkdir -p $out/lib
          mv firmware-eswin $out/lib/$name
        '';
      });
  };
}
