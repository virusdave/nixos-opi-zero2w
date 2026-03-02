{ lib, pkgs, ... }:
let
  # Armbian sunxi-6.12 baseline, filtered for H616/H618 + Zero2W-relevant patches.
  armbianPatchRoot = ../patches/uwe5622/armbian-sunxi-6.12;
  selectedPatchLines = lib.splitString "\n" (
    builtins.readFile (armbianPatchRoot + "/selected-for-opi-zero2w.list")
  );
  armbianSelectedPatchRelPaths = lib.filter
    (line: line != "" && !(lib.hasPrefix "#" line))
    (map lib.strings.trim selectedPatchLines);
  armbianSelectedPatches = builtins.map (relPath: {
    patch = armbianPatchRoot + "/${relPath}";
  }) armbianSelectedPatchRelPaths;
in {
  # Speed up repeated kernel iteration by enabling ccache only for kernel builds.
  # The custom builder exposes /nix/var/cache/ccache-kernel via extra-sandbox-paths.
  boot.kernelPackages = lib.mkForce (
    pkgs.linuxPackagesFor (pkgs.linux.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ pkgs.ccache ];
      # Mirror Armbian's driver_uwe5622() scripted integration step:
      # echo "obj-$(CONFIG_SPARD_WLAN_SUPPORT) += uwe5622/" >> drivers/net/wireless/Makefile
      postPatch = (old.postPatch or "") + ''
          if ! grep -q 'obj-\$(CONFIG_SPARD_WLAN_SUPPORT) += uwe5622/' drivers/net/wireless/Makefile; then
            echo 'obj-$(CONFIG_SPARD_WLAN_SUPPORT) += uwe5622/' >> drivers/net/wireless/Makefile
          fi

          # Armbian's UWE makefile snippets assume /bin/pwd exists.
          # Nix sandboxes don't guarantee that path, so use PATH-resolved pwd.
          if [ -d drivers/net/wireless/uwe5622 ]; then
            grep -rl '/bin/pwd' drivers/net/wireless/uwe5622 \
              | while IFS= read -r file; do
                  substituteInPlace "$file" --replace-fail '/bin/pwd' 'pwd'
                done
          fi

          # Linux 6.12 needs OF declarations in tty-sdio for DT parsing helpers.
          tty_sdio_file="drivers/net/wireless/uwe5622/tty-sdio/tty.c"
          if [ -f "$tty_sdio_file" ]; then
            grep -q '^#include <linux/of_device.h>$' "$tty_sdio_file" || sed -i '1i #include <linux/of_device.h>' "$tty_sdio_file"
            grep -q '^#include <linux/of.h>$' "$tty_sdio_file" || sed -i '1i #include <linux/of.h>' "$tty_sdio_file"
          fi

          # Linux 6.12 adds a link_id argument to tdls_mgmt callback.
          cfg80211_file="drivers/net/wireless/uwe5622/unisocwifi/cfg80211.c"
          if [ -f "$cfg80211_file" ]; then
            perl -0pi -e 's/(sprdwl_cfg80211_tdls_mgmt\s*\([^\)]*const\s+u8\s*\*peer,\s*)(u8\s+action_code)/\1int link_id, \2/s' "$cfg80211_file"
            perl -0pi -e 's/strncpy\(\s*scan_ssids->ssid\s*,\s*ssids\[i\]\.ssid\s*,\s*[^\)]*\)/memcpy(scan_ssids->ssid, ssids[i].ssid, ssids[i].ssid_len)/g' "$cfg80211_file"
          fi

          # Linux 6.12.70 netlink API expects split op callback signatures.
          npi_file="drivers/net/wireless/uwe5622/unisocwifi/npi.c"
          if [ -f "$npi_file" ]; then
            perl -0pi -e 's/const\s+struct\s+genl_ops\s*\*\s*(ops)/const struct genl_split_ops *\1/g' "$npi_file"
          fi
          '';
      # linux's builder doesn't preserve arbitrary attrs like CCACHE_DIR/makeFlags
      # in the final derivation env, so export these explicitly in preConfigure.
      preConfigure = (old.preConfigure or "") + ''
        export CCACHE_DIR=/nix/var/cache/ccache-kernel
        export CCACHE_COMPRESS=1
        export CCACHE_UMASK=007

        # ccache can break stdin-based compiler probes (`... -x c -`) used by Kbuild.
        # Wrap compilers to bypass ccache for stdin probes while caching normal compiles.
        ccache_wrap() {
          real_compiler="$1"
          wrapper_path="$2"
          cat > "$wrapper_path" <<EOF
#!/bin/sh
for arg in "\$@"; do
  if [ "\$arg" = "-" ]; then
    exec "$real_compiler" "\$@"
  fi
done
exec ccache "$real_compiler" "\$@"
EOF
          chmod +x "$wrapper_path"
        }

        ccache_wrap "${pkgs.stdenv.cc.targetPrefix}cc" "$TMPDIR/cc-with-ccache"
        ccache_wrap cc "$TMPDIR/hostcc-with-ccache"
        ccache_wrap c++ "$TMPDIR/hostcxx-with-ccache"

        makeFlags+=("CC=$TMPDIR/cc-with-ccache")
        makeFlags+=("HOSTCC=$TMPDIR/hostcc-with-ccache")
        makeFlags+=("HOSTCXX=$TMPDIR/hostcxx-with-ccache")
      '';
    }))
  );

  # Orange Pi Zero 2W baseline from Armbian sunxi 6.12 patch series.
  boot.kernelPatches = armbianSelectedPatches ++ [
    {
      name = "opi-zero-2w-minimal-hardware";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        # Minimize everything we don't think we need
        #
        # --- GPU & Display (Parents Only) ---
        DRM_LIMA = yes;
        DRM_SUN4I = yes;
        DRM_RADEON = no;

        # Disable the big vendor blocks
        WLAN_VENDOR_ATH = no;
        WLAN_VENDOR_BROADCOM = yes;
        WLAN_VENDOR_INTEL = no;
        WLAN_VENDOR_MARVELL = no;
        WLAN_VENDOR_TI = no;

        # UWE5622 (Unisoc) WiFi/BT stack from Armbian patchset.
        # Keep as modules for easier inspection with modinfo/lsmod.
        SPARD_WLAN_SUPPORT = yes;
        AW_WIFI_DEVICE_UWE5622 = yes;
        WLAN_UWE5622 = module;
        SPRDWL_NG = module;
        TTY_OVERY_SDIO = module;

        # MAC address manager used by the patched UWE BT path.
        SUNXI_ADDR_MGT = module;

        # --- Sound ---
        SOUND = yes;
        SND = yes;
        SND_SOC = yes;
        SND_SUN4I_CODEC = yes;
      };
    }
  ];

  # Keep firmware available in case selected patches or future kernel changes use it.
  hardware.firmware = [ (pkgs.callPackage ../patches/uwe5622/firmware.nix {}) ];

  # Enable wireless networking with wpa_supplicant by default for UWE5622.
  networking.wireless.enable = true;

  # Console on sunxi UART0
  boot.kernelParams = lib.mkDefault [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  # NixOS uses a shrunk module closure for the running system. Explicitly
  # requesting these modules keeps them in /run/current-system/kernel-modules
  # and also makes missing-module issues fail deterministically at build time.
  boot.kernelModules = [
    "sprdwl_ng"
    "sprdbt_tty"
    "sunxi_addr"
  ];

  # UWE5622 firmware loader still probes /lib/firmware paths.
  # Mirror NixOS firmware exposure there via tmpfiles for deterministic boot-time setup.
  systemd.tmpfiles.rules = [
    "L+ /lib/firmware - - - - /run/current-system/firmware"
  ];

  # Use only the OPI Zero 2W DTB, preserving the path expected by U-Boot.
  hardware.deviceTree = {
    enable = true;
    name = "allwinner/sun50i-h618-orangepi-zero2w.dtb";
  };
}
