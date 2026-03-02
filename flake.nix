{
  description = "Orange Pi Zero 2W board-support modules and combinators for NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      mkUbootOrangePiZero2W = pkgs:
        pkgs.buildUBoot {
          defconfig = "orangepi_zero2w_defconfig";
          extraMeta.platforms = [ "aarch64-linux" ];
          BL31 = "${pkgs.armTrustedFirmwareAllwinnerH616}/bl31.bin";
          filesToInstall = [ "u-boot-sunxi-with-spl.bin" ];
        };
    in {
      lib = {
        inherit mkUbootOrangePiZero2W;

        withOpiZero2wEssentials = modules:
          modules ++ [ self.nixosModules.default ];

        withOpiZero2wInstallerEssentials = modules:
          self.lib.withOpiZero2wEssentials (modules ++ [ self.nixosModules.installerSdImage ]);
      };

      nixosModules = {
        default = import ./modules/essential.nix;
        installerSdImage = import ./modules/installer-sd-image.nix;
      };
    };
}
