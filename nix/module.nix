{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.denial;
in
{
  options.programs.denial = {
    enable = lib.mkEnableOption "Denial, a Flutter-native Wayland compositor";
    package = lib.mkPackageOption pkgs "denial" { };

    plugins = {
      enable = lib.mkEnableOption "Denial's plugin development and composition tools";
      package = lib.mkPackageOption pkgs "denialPluginManager" { };
    };

    polkitAgent = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to run a PolicyKit authentication agent in Denial sessions.
          Disable this when another desktop component already provides one.
        '';
      };
      command = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.package}/bin/denial-polkit-agent";
        defaultText = lib.literalExpression ''
          "''${config.programs.denial.package}/bin/denial-polkit-agent"
        '';
        description = "Absolute command used for the PolicyKit authentication agent.";
      };
    };

    ddc.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable I2C device access for Denial's DDC monitor controls.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      pkgs.zenity
    ] ++ lib.optional cfg.plugins.enable cfg.plugins.package;
    fonts.packages = [ pkgs.source-han-sans ];

    services.displayManager.sessionPackages = [ cfg.package ];
    services.graphical-desktop.enable = true;

    security.polkit.enable = true;
    security.rtkit.enable = true;
    hardware.i2c.enable = lib.mkDefault cfg.ddc.enable;
    programs.dconf.enable = lib.mkDefault true;
    programs.xwayland.enable = lib.mkDefault true;

    systemd.user.services.denial-polkit-agent = {
      enable = cfg.polkitAgent.enable;
      description = "PolicyKit authentication agent for Denial";
      documentation = [ "https://github.com/denialwm/denial" ];
      wantedBy = [ "denial-session.target" ];
      partOf = [ "denial-session.target" ];
      after = [ "graphical-session-pre.target" ];
      serviceConfig = {
        ExecStart = cfg.polkitAgent.command;
        Restart = "on-failure";
        RestartSec = "250ms";
      };
    };

    services.dbus.packages = [ cfg.package ];
    systemd.packages = [ cfg.package ];
    environment.etc."systemd/system-sleep/denial-suspend-mode".source =
      "${cfg.package}/lib/systemd/system-sleep/denial-suspend-mode";

    xdg.portal = {
      enable = lib.mkDefault true;
      wlr = {
        enable = true;
        settings.screencast = {
          # Denial does not expose layer-shell yet, so slurp cannot be used as
          # the chooser. Keep this absolute: the wlr portal does not inherit
          # the interactive session's PATH on NixOS.
          chooser_type = "dmenu";
          chooser_cmd = "${pkgs.zenity}/bin/zenity --list --title='Share your screen' --text='Choose a source to share' --column='Source' --width=520 --height=320";
        };
      };
      extraPortals = [
        cfg.package
        pkgs.xdg-desktop-portal-gtk
      ];
      config.denial = {
        default = [ "gtk" ];
        "org.freedesktop.impl.portal.Settings" = [
          "denial"
          "gtk"
        ];
        "org.freedesktop.impl.portal.ScreenCast" = "wlr";
        "org.freedesktop.impl.portal.Screenshot" = "wlr";
      };
    };
  };
}
