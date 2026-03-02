{ config, pkgs, modulesPath, ... }:
let
  ubootOrangePiZero2W =
    pkgs.buildUBoot {
      defconfig = "orangepi_zero2w_defconfig";
      extraMeta.platforms = [ "aarch64-linux" ];
      BL31 = "${pkgs.armTrustedFirmwareAllwinnerH616}/bl31.bin";
      filesToInstall = [ "u-boot-sunxi-with-spl.bin" ];
    };
in {
  imports = [
    (modulesPath + "/installer/sd-card/sd-image.nix")
  ];

  sdImage = {
    firmwareSize = 16;
    populateFirmwareCommands = "";

    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
        -c ${config.system.build.toplevel} \
        -d ./files/boot
    '';

    postBuildCommands = ''
      dd if=${ubootOrangePiZero2W}/u-boot-sunxi-with-spl.bin of=$img \
        bs=1024 seek=8 \
        conv=notrunc
    '';
  };
}
