{
  pkgs,
  module,
  nixosSystem,
}:

let
  evaluated = nixosSystem {
    inherit (pkgs.stdenv.hostPlatform) system;
    modules = [
      module
      {
        # A consumer overlay must reach Denial's native runtime rather than
        # being bypassed by self.packages from the flake's own package set.
        nixpkgs.overlays = [
          (_final: prev: {
            libgbm = prev.libgbm.overrideAttrs (_: {
              pname = "denial-module-host-libgbm";
            });
            libglvnd = prev.libglvnd.overrideAttrs (_: {
              pname = "denial-module-host-libglvnd";
            });
          })
        ];
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
        programs.denial.enable = true;
        system.stateVersion = "26.05";
      }
    ];
  };
  cfg = evaluated.config;
  hostPkgs = evaluated.pkgs;
  expectedChooser = "${hostPkgs.zenity}/bin/zenity --list --title='Share your screen' --text='Choose a source to share' --column='Source' --width=520 --height=320";
  disabledIntegrations = nixosSystem {
    inherit (pkgs.stdenv.hostPlatform) system;
    modules = [
      module
      {
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
        programs.denial = {
          enable = true;
          polkitAgent.enable = false;
          ddc.enable = false;
        };
        system.stateVersion = "26.05";
      }
    ];
  };
  disabledCfg = disabledIntegrations.config;
in
pkgs.runCommand "denial-module-evaluation" { } ''
  test '${toString cfg.programs.denial.enable}' = 1
  test '${toString (cfg.programs.denial.package.drvPath == hostPkgs.denial.drvPath)}' = 1
  test '${toString (builtins.elem hostPkgs.libgbm cfg.programs.denial.package.compositor.buildInputs)}' = 1
  test '${
    toString (
      cfg.programs.denial.package.compositor.stdenv.cc.libc.drvPath == hostPkgs.stdenv.cc.libc.drvPath
    )
  }' = 1
  test '${toString (builtins.elem (toString hostPkgs.libglvnd) (map toString hostPkgs.denialFlutter.engine.release.toolchain.paths))}' = 1
  test '${
    toString (
      hostPkgs.denialFlutter.engine.release.stdenv.cc.libc.drvPath == hostPkgs.stdenv.cc.libc.drvPath
    )
  }' = 1
  test '${toString (builtins.elem cfg.programs.denial.package cfg.services.displayManager.sessionPackages)}' = 1
  test '${toString cfg.security.polkit.enable}' = 1
  test '${toString cfg.security.rtkit.enable}' = 1
  test '${toString cfg.hardware.i2c.enable}' = 1
  test '${toString cfg.programs.xwayland.enable}' = 1
  test '${toString (builtins.elem hostPkgs.source-han-sans cfg.fonts.packages)}' = 1
  test '${cfg.xdg.portal.wlr.settings.screencast.chooser_type}' = dmenu
  test '${toString (cfg.xdg.portal.wlr.settings.screencast.chooser_cmd == expectedChooser)}' = 1
  test '${
    toString (
      cfg.systemd.user.services.denial-polkit-agent.serviceConfig.ExecStart
      == "${hostPkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
    )
  }' = 1
  test '${toString (builtins.elem "denial-session.target" cfg.systemd.user.services.denial-polkit-agent.wantedBy)}' = 1
  test '${toString (!disabledCfg.hardware.i2c.enable)}' = 1
  test '${toString (!builtins.hasAttr "denial-polkit-agent" disabledCfg.systemd.user.services)}' = 1
  touch $out
''
