# opi-zero2w

Reusable NixOS board-support flake for the Orange Pi Zero 2W (Allwinner H618).

This flake is intentionally focused on **board essentials only**: kernel/patch wiring,
firmware handling, DTB selection, and installer U-Boot image layout. Keep your own
site policy and host preferences (users, SSH policy, services, secrets, Wi-Fi credentials)
in your own flake modules.

All of these things, and in particular wifi support, were poorly documented with obsolete documentation, or outright don't work as described elsewhere.

Taking [Armbian](https://github.com/armbian/build) as a working example, which has working HDMI and (more importantly) working WIFI patched in by its build system, I've migrated the needed patches and supporting script elements from that repo to be applied as kernel patches to a nixos configuration.  This should let your preferred configuration boot successfully, with working wifi support.  Huzzah.

## What It Exposes

- `nixosModules.default`: essential board support (kernel patchset, UWE5622 integration, DTB selection, firmware wiring)
- `nixosModules.installerSdImage`: SD image/U-Boot wiring for bootable installer images
- `lib.withOpiZero2wEssentials`: combinator that appends board-essential module(s)
- `lib.withOpiZero2wInstallerEssentials`: combinator for board essentials + installer SD image module

## Example: Full System Configuration

Use this when you want a normal deployed system closure (`config.system.build.toplevel`).

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    opi-zero2w.url = "github:YOUR_ORG/opi-zero2w";
  };

  outputs = { nixpkgs, opi-zero2w, ... }: {
    nixosConfigurations.opi = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";

      # Start with your own modules, then append board essentials.
      modules = opi-zero2w.lib.withOpiZero2wEssentials [
        ./your-base.nix
        ./your-host.nix
      ];
    };
  };
}
```

## Example: Inline Installer Image

This example is intentionally self-contained so people can copy it into a new repo,
build an installer SD image, and then iterate.

```nix
{
  description = "Minimal Orange Pi Zero 2W installer image";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    opi-zero2w.url = "github:YOUR_ORG/opi-zero2w";
  };

  outputs = { nixpkgs, opi-zero2w, ... }:
    let
      system = "aarch64-linux";
    in {
      nixosConfigurations.opi-installer = nixpkgs.lib.nixosSystem {
        inherit system;

        # This combinator appends BOTH:
        # 1) board essentials (kernel, DTB, firmware, driver patching)
        # 2) installer SD image wiring (including U-Boot write step)
        modules = opi-zero2w.lib.withOpiZero2wInstallerEssentials [
          ({ pkgs, ... }: {
            networking.hostName = "opi-installer";

            # Keep this tiny and explicit for first boot bring-up.
            services.openssh.enable = true;
            # Set a real hash before booting (example: `mkpasswd -m yescrypt`).
            users.users.root.initialHashedPassword = "!";

            # Any local packages/policy can still be layered here.
            environment.systemPackages = with pkgs; [ git htop ];
          })
        ];
      };
    };
}
```

Build the installer image with:

```sh
nix build .#nixosConfigurations.opi-installer.config.system.build.sdImage
```
