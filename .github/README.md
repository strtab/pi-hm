# pi-hm

Home Manager module for the [pi coding agent](https://github.com/earendil-works/pi).

The upstream repository ships a flake with `packages`, `apps` and `overlays`, but no Home Manager module. This flake wraps the upstream package and provides the module `programs.pi-coding-agent`.

## How it works

- The `pi` flake input provides the package (`pi.packages.<system>.default`). The version is pinned through the URL of this input.
- The module writes the agent configuration into `configDir` (default `~/.pi/agent`) using Home Manager `home.file`.
- If `environment` is not empty, or `configDir` differs from the default, the `pi` binary is wrapped with `makeWrapper` and the variables are set with `--set`. `PI_CODING_AGENT_DIR` is added automatically for a custom `configDir`.
- Files managed by Home Manager are read-only symlinks into the Nix store. Anything pi wants to write itself (for example `settings.json` changed through `/model`) will fail. Credentials such as `auth.json` are not managed by the module.

Resulting layout:

```
<configDir>/
  settings.json      from `settings`
  models.json        from `models`
  keybindings.json   from `keybindings`
  AGENTS.md          from `rules`
  extensions/<name>  from `extensions` (one symlink per entry)
  skills/            from `skills`
```

## Options

All options live under `programs.pi-coding-agent`.

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | `false` | Enable the module and install pi. |
| `package` | package | `pi.packages.<system>.default` | Package to install. Normally pinned via the flake input instead. |
| `finalPackage` | package (read-only) | wrapped `package` | Package after the environment wrapper is applied. |
| `configDir` | string | `~/.pi/agent` | Agent config directory. Sets `PI_CODING_AGENT_DIR` through the wrapper when changed. |
| `settings` | JSON attrs | `{ }` | Contents of `settings.json`. Not written when empty. |
| `models` | null, path or JSON attrs | `null` | `models.json`. A path is symlinked, an attrset is rendered to JSON. |
| `keybindings` | null, path or JSON attrs | `null` | `keybindings.json`, same rules as `models`. |
| `rules` | lines or path | `""` | Global context written to `AGENTS.md`. Not written when empty. |
| `extensions` | list of paths | `[ ]` | Extension files or directories, symlinked into `extensions/` under their base name. |
| `skills` | attrset or path | `{ }` | See below. |
| `environment` | attrs of strings | `{ }` | Environment variables baked into the wrapper. |

### skills

Two forms are accepted.

A single path or derivation. It is symlinked to `<configDir>/skills` and must contain one folder per skill, each with a `SKILL.md`. This works with the result of `pkgs.symlinkJoin`.

```nix
skills = pkgs.symlinkJoin {
  name = "pi-skills";
  paths = [ "${inputs.some-skills}/skills" ./skills ];
};
```

An attribute set. The name becomes the skill directory:

- a string becomes `skills/<name>/SKILL.md`
- a path to a file becomes `skills/<name>/SKILL.md`
- a path to a directory is linked as `skills/<name>/`

```nix
skills = {
  my-skill = ./skills/my-skill;
  quick = ''
    ---
    name: quick
    description: Example skill
    ---
    Instructions here.
  '';
};
```

### extensions

Each entry is linked as `<configDir>/extensions/<basename>`. Both single `.ts` files and directories with an `index.ts` work. Nix does not run `npm install`, so extensions that need `node_modules` (a `package.json` with dependencies) have to be made self-contained or packaged separately.

## Usage

### 1. Add the inputs

In the root `flake.nix`:

```nix
{
  inputs = {
    # Pin the pi version here:
    #   github:earendil-works/pi/stable     latest release
    #   github:earendil-works/pi/v1.0.0     fixed release tag
    #   github:earendil-works/pi            main branch
    pi.url = "github:earendil-works/pi/stable";

    pi-hm = {
      url = "github:strtab/pi-hm";
      inputs.pi.follows = "pi";
    };
  };
}
```

Make sure `inputs` is passed to Home Manager modules (`extraSpecialArgs = { inherit inputs; };`).

### 2. Configure pi

```nix
{ config, pkgs, inputs, ... }:
let
  agentDir = "${config.xdg.configHome}/pi/agent";
in
{
  imports = [ inputs.pi-hm.homeModules.default ];

  programs.pi-coding-agent = {
    enable = true;
    configDir = agentDir;

    rules = ''
      Write comments in the code only in English.
    '';

    extensions = [
      ./extensions/clear.ts
      ./extensions/prompt-snippets
    ];

    skills = pkgs.symlinkJoin {
      name = "pi-skills";
      paths = [ ./skills ];
    };

    models = ./models.json;
    keybindings = ./keybindings.json;

    settings = {
      quietStartup = true;
      theme = "light/dark";
      defaultProvider = "llama-cpp";
      defaultModel = "my-model";
      compaction.enabled = true;
    };

    environment.PI_SKIP_VERSION_CHECK = "1";
  };
}
```

### Updating or changing the version

```sh
# bump to the newest revision of the tracked ref
nix flake update pi

# or switch to a specific release: edit pi.url, then
nix flake update pi
```

## Notes

- Home Manager asserts nothing about `models`/`keybindings` content. Invalid JSON for pi is only detected at runtime.
- To use pi without Home Manager: `nix run github:earendil-works/pi/stable`.
