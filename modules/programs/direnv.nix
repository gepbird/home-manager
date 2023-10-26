{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.programs.direnv;

  tomlFormat = pkgs.formats.toml { };

in {
  imports = [
    (mkRenamedOptionModule [
      "programs"
      "direnv"
      "enableNixDirenvIntegration"
    ] [ "programs" "direnv" "nix-direnv" "enable" ])
    (mkRemovedOptionModule [ "programs" "direnv" "nix-direnv" "enableFlakes" ]
      "Flake support is now always enabled.")
  ];

  meta.maintainers = [ maintainers.rycee ];

  options.programs.direnv = {
    enable = mkEnableOption "direnv, the environment switcher";

    package = mkPackageOption pkgs "direnv" { };

    config = mkOption {
      type = tomlFormat.type;
      default = { };
      description = ''
        Configuration written to
        {file}`$XDG_CONFIG_HOME/direnv/direnv.toml`.

        See
        {manpage}`direnv.toml(1)`.
        for the full list of options.
      '';
    };

    stdlib = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Custom stdlib written to
        {file}`$XDG_CONFIG_HOME/direnv/direnvrc`.
      '';
    };

    enableBashIntegration = mkOption {
      default = true;
      type = types.bool;
      description = ''
        Whether to enable Bash integration.
      '';
    };

    enableZshIntegration = mkOption {
      default = true;
      type = types.bool;
      description = ''
        Whether to enable Zsh integration.
      '';
    };

    enableFishIntegration = mkOption {
      default = true;
      type = types.bool;
      readOnly = true;
      description = ''
        Whether to enable Fish integration. Note, enabling the direnv module
        will always active its functionality for Fish since the direnv package
        automatically gets loaded in Fish. If this is not the case try adding
        ```nix
          environment.pathsToLink = [ "/share/fish" ];
        ```
        to the system configuration.
      '';
    };

    enableNushellIntegration = mkOption {
      default = true;
      type = types.bool;
      description = ''
        Whether to enable Nushell integration.
      '';
    };

    nix-direnv = {
      enable = mkEnableOption ''
        [nix-direnv](https://github.com/nix-community/nix-direnv),
        a fast, persistent use_nix implementation for direnv'';

      package = mkPackageOption pkgs "nix-direnv" { };

      useXDGCache = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Whether to put the generated .direnv directories into $XDG_CACHE_HOME or keep it in the project directory.
          See: https://github.com/direnv/direnv/wiki/Customizing-cache-location#human-readable-directories.
        '';
      };
    };

  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."direnv/direnv.toml" = mkIf (cfg.config != { }) {
      source = tomlFormat.generate "direnv-config" cfg.config;
    };

    xdg.configFile."direnv/direnvrc" = let
      text = concatStringsSep "\n" (optional (cfg.stdlib != "") cfg.stdlib
        ++ optional cfg.nix-direnv.enable
        "source ${cfg.nix-direnv.package}/share/nix-direnv/direnvrc"
        ++ optional (cfg.nix-direnv.enable && cfg.nix-direnv.useXDGCache) ''
          : "''${XDG_CACHE_HOME:="''${HOME}/.cache"}"
          declare -A direnv_layout_dirs
          direnv_layout_dir() {
            local hash path
            echo "''${direnv_layout_dirs[$PWD]:=$(
              hash="$(sha1sum - <<< "$PWD" | head -c40)"
              path="''${PWD//[^a-zA-Z0-9]/-}"
              echo "''${XDG_CACHE_HOME}/direnv/layouts/''${hash}''${path}"
            )}"
          }
        '');
    in mkIf (text != "") { inherit text; };

    programs.bash.initExtra = mkIf cfg.enableBashIntegration (
      # Using mkAfter to make it more likely to appear after other
      # manipulations of the prompt.
      mkAfter ''
        eval "$(${cfg.package}/bin/direnv hook bash)"
      '');

    programs.zsh.initExtra = mkIf cfg.enableZshIntegration ''
      eval "$(${cfg.package}/bin/direnv hook zsh)"
    '';

    programs.fish.interactiveShellInit = mkIf cfg.enableFishIntegration (
      # Using mkAfter to make it more likely to appear after other
      # manipulations of the prompt.
      mkAfter ''
        ${cfg.package}/bin/direnv hook fish | source
      '');

    programs.nushell.extraConfig = mkIf cfg.enableNushellIntegration (
      # Using mkAfter to make it more likely to appear after other
      # manipulations of the prompt.
      mkAfter ''
        $env.config = ($env | default {} config).config
        $env.config = ($env.config | default {} hooks)
        $env.config = ($env.config | update hooks ($env.config.hooks | default [] pre_prompt))
        $env.config = ($env.config | update hooks.pre_prompt ($env.config.hooks.pre_prompt | append {
          code: "
            let direnv = (${cfg.package}/bin/direnv export json | from json)
            let direnv = if not ($direnv | is-empty) { $direnv } else { {} }
            $direnv | load-env
            "
        }))
      '');
  };
}
