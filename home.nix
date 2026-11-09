# Home Manager module for the pi coding agent.
# Called as `import ./module.nix piFlake`, where piFlake is the upstream
# earendil-works/pi flake (used only for the default package).
piFlake:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption mkIf types;

  cfg = config.programs.pi-coding-agent;

  jsonFormat = pkgs.formats.json { };

  defaultConfigDir = "${config.home.homeDirectory}/.pi/agent";

  isSource = v: lib.isPath v || lib.isDerivation v;

  # path/derivation -> symlink, attrs -> generated JSON
  mkJsonEntry =
    name: v:
    if isSource v then { source = v; } else { source = jsonFormat.generate name v; };

  extName = p: baseNameOf (toString p);

  # a single path/derivation (e.g. symlinkJoin) is a directory of skill folders
  skillsIsDir = !(lib.isAttrs cfg.skills) || lib.isDerivation cfg.skills;

  mkSkillEntry =
    name: v:
    if lib.hm.strings.isPathLike v && lib.pathIsDirectory v then
      lib.nameValuePair "${cfg.configDir}/skills/${name}" { source = v; }
    else
      lib.nameValuePair "${cfg.configDir}/skills/${name}/SKILL.md" (
        if lib.hm.strings.isPathLike v then { source = v; } else { text = v; }
      );
in
{
  options.programs.pi-coding-agent = {
    enable = lib.mkEnableOption "pi coding agent";

    package = mkOption {
      type = types.package;
      default = piFlake.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "pi.packages.\${system}.default";
      description = ''
        The pi package to install.

        By default it comes from the `pi` flake input, so the version is
        pinned through the URL of that input.
      '';
      example = lib.literalExpression "inputs.pi.packages.\${pkgs.stdenv.hostPlatform.system}.default";
    };

    finalPackage = mkOption {
      type = types.package;
      readOnly = true;
      internal = true;
      description = "Resulting customized pi package.";
    };

    configDir = mkOption {
      type = types.str;
      default = defaultConfigDir;
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.pi/agent"'';
      example = lib.literalExpression ''"''${config.xdg.configHome}/pi/agent"'';
      description = ''
        Directory holding pi's configuration files.

        Defaults to {file}`~/.pi/agent`, matching the upstream default.
        The {env}`PI_CODING_AGENT_DIR` environment variable is exported
        through the {command}`pi` wrapper whenever the directory differs from
        this default, so pi reads configuration from the same location.
      '';
    };

    settings = mkOption {
      inherit (jsonFormat) type;
      default = { };
      example = {
        quietStartup = true;
        theme = "dark";
        compaction.enabled = true;
        defaultProvider = "anthropic";
        defaultModel = "claude-sonnet-4-5";
      };
      description = ''
        JSON configuration for pi.

        The value is written to {file}`settings.json` inside
        {option}`programs.pi-coding-agent.configDir`. The file is not
        created when the set is empty.
      '';
    };

    models = mkOption {
      type = types.nullOr (types.either types.path jsonFormat.type);
      default = null;
      example = lib.literalExpression "./models.json";
      description = ''
        Custom providers and models for pi.

        The value is either:
        - A path to a JSON file
        - An attribute set that is rendered to JSON

        The content is written to {file}`models.json` inside
        {option}`programs.pi-coding-agent.configDir`.
      '';
    };

    keybindings = mkOption {
      type = types.nullOr (types.either types.path jsonFormat.type);
      default = null;
      example = lib.literalExpression "./keybindings.json";
      description = ''
        Custom keybindings for pi.

        The value is either:
        - A path to a JSON file
        - An attribute set that is rendered to JSON

        The content is written to {file}`keybindings.json` inside
        {option}`programs.pi-coding-agent.configDir`.
      '';
    };

    rules = mkOption {
      type = types.either types.lines types.path;
      default = "";
      example = lib.literalExpression "./AGENTS.md";
      description = ''
        Global context for pi.

        The value is either:
        - Inline content as a string
        - A path to a file containing the content

        The configured content is written to {file}`AGENTS.md` inside
        {option}`programs.pi-coding-agent.configDir`.
      '';
    };

    extensions = mkOption {
      type = types.listOf types.path;
      default = [ ];
      example = lib.literalExpression ''
        [
          ./extensions/clear.ts
          ./extensions/prompt-snippets
        ]
      '';
      description = ''
        Extensions for pi.
        Each entry is either:
        - A path to a single extension file
        - A path to an extension directory with an {file}`index.ts`

        Entries are symlinked into the {file}`extensions/` subdirectory of
        {option}`programs.pi-coding-agent.configDir` under their own base name.

        Dependencies are not installed. Extensions that need
        {file}`node_modules` must be made self-contained or packaged separately.
      '';
    };

    skills = mkOption {
      type = types.either (types.attrsOf (types.either types.lines types.path)) types.path;
      default = { };
      description = ''
        Custom skills for pi.

        This option can be either:
        - An attribute set defining skills
        - A path to a directory containing skill folders

        If an attribute set is used, the attribute name becomes the
        skill directory name, and the value is either:
        - Inline content as a string (creates {file}`skills/<name>/SKILL.md`)
        - A path to a file (creates {file}`skills/<name>/SKILL.md`)
        - A path to a directory (creates {file}`skills/<name>/` with all files)

        If a path is used, it is expected to contain one folder per
        skill name, each containing a {file}`SKILL.md`. The directory is
        symlinked to the {file}`skills/` subdirectory of
        {option}`programs.pi-coding-agent.configDir`. This also accepts
        derivations, for example the result of {command}`pkgs.symlinkJoin`.
      '';
      example = lib.literalExpression ''
        {
          my-skill = ./skills/my-skill;
          quick = '''
            ---
            name: quick
            description: Example skill. Use when the user asks for a quick example.
            ---

            # Quick

            Instructions for the skill.
          ''';
        }
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        PI_SKIP_VERSION_CHECK = "1";
      };
      description = ''
        Environment variables set by the {command}`pi` wrapper.

        Unlike {option}`home.sessionVariables` they apply to every
        invocation of pi, regardless of how it was started.
      '';
    };
  };

  config = mkIf cfg.enable {
    programs.pi-coding-agent.finalPackage =
      let
        allEnv =
          cfg.environment
          // lib.optionalAttrs (cfg.configDir != defaultConfigDir) {
            PI_CODING_AGENT_DIR = cfg.configDir;
          };
        args = lib.concatStringsSep " " (
          lib.mapAttrsToList (n: v: "--set ${n} ${lib.escapeShellArg v}") allEnv
        );
      in
      if allEnv == { } then
        cfg.package
      else
        pkgs.symlinkJoin {
          name = "pi-wrapped";
          paths = [ cfg.package ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            rm $out/bin/pi
            makeWrapper ${cfg.package}/bin/pi $out/bin/pi ${args}
          '';
          inherit (cfg.package) meta;
        };

    home.packages = [ cfg.finalPackage ];

    home.file = lib.mkMerge [
      (mkIf (cfg.settings != { }) {
        "${cfg.configDir}/settings.json".source = jsonFormat.generate "pi-settings.json" cfg.settings;
      })
      (mkIf (cfg.models != null) {
        "${cfg.configDir}/models.json" = mkJsonEntry "pi-models.json" cfg.models;
      })
      (mkIf (cfg.keybindings != null) {
        "${cfg.configDir}/keybindings.json" = mkJsonEntry "pi-keybindings.json" cfg.keybindings;
      })
      (
        if lib.isPath cfg.rules then
          { "${cfg.configDir}/AGENTS.md".source = cfg.rules; }
        else
          mkIf (cfg.rules != "") { "${cfg.configDir}/AGENTS.md".text = cfg.rules; }
      )
      (
        if skillsIsDir then
          { "${cfg.configDir}/skills".source = cfg.skills; }
        else
          lib.mapAttrs' mkSkillEntry cfg.skills
      )
      (lib.listToAttrs (
        map (p: lib.nameValuePair "${cfg.configDir}/extensions/${extName p}" { source = p; }) cfg.extensions
      ))
    ];
  };
}
