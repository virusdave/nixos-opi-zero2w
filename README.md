# opi-zero2w

Reusable NixOS board-support flake for the Orange Pi Zero 2W (Allwinner H618).

## What It Exposes

- `nixosModules.default`: essential board support (kernel patchset, UWE5622 integration, DTB selection, firmware wiring)
- `nixosModules.installerSdImage`: SD image/U-Boot wiring for bootable installer images
- `lib.withOpiZero2wEssentials`: combinator that appends board-essential module(s)
- `lib.withOpiZero2wInstallerEssentials`: combinator for board essentials + installer SD image module

## Example

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    opi-zero2w.url = "github:YOUR_ORG/opi-zero2w";
  };

  outputs = { nixpkgs, opi-zero2w, ... }: {
    nixosConfigurations.opi = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = opi-zero2w.lib.withOpiZero2wEssentials [
        ./your-base.nix
        ./your-host.nix
      ];
    };
  };
}
```
