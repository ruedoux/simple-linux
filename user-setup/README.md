# user-setup

Per-user dotfiles, theming, and day-to-day management. Everything is self-contained to an individual user — never requires sudo.

## Quick Start

Run [setup.sh](setup.sh) to bootstrap a user environment:

```bash
./user-setup/setup.sh
```

Copies dotfiles via rsync (preserving wallpapers and user `bashrc-extension.sh`), starts PipeWire and HyprSunset user services, configures Hyprland autostart via `.bash_profile`, creates `hyprland-session.target` for session management, then runs `sl-controller.sh reload-all`.

Safe to run multiple times, but overrides most dotfiles (excluding wallpapers and `bashrc-extension.sh`).

---

## Controller (`sl-controller.sh`)

Central management hub at `~/.config/simple-linux/sl-controller.sh`:

| Command | Description |
|---|---|
| `reload-all` | Full environment refresh: bashrc → yazi desktop → packages → source bashrc → python → flatpaks → wallpaper → monitors → themes |
| `update-packages` | Installs/updates all packages from `packages/` |
| `update-flatpacks` | Adds Flathub remote, updates all, installs packages from `SL_USER_FLATPAK_PACKAGES`, applies `SL_USER_FLATPAK_OVERRIDES` |
| `update-bashrc` | Rsyncs `.bashrc` to `~/.bashrc` (with `.bck` backup) |
| `update-python` | Installs Python via pyenv, sets global version, upgrades pip |
| `update-wallpaper --path <file>` | Set wallpaper, generate blurred variant via ImageMagick, reload hyprpaper, regenerate Material Design colors via matugen |
| `remove-wallpaper --name <name>` | Delete a stored wallpaper (not the active one) |
| `update-monitors` | Query `hyprctl`, regenerate monitor/workspace/hyprpaper config from templates |
| `update-themes` | Set GTK/Qt gsettings, render all non-monitor templates, run matugen, reload Quickshell |
| `switch-theme-mode` | Toggles `dark ↔ light` in `config.env`, re-themes everything |
| `config` | Opens `config.env` in `$EDITOR` |
| `reload-quickshell` | Kills and restarts the Quickshell desktop shell |
| `setup-dev-env` | Initializes containerd rootless + BuildKit, enables user services; also installs Roslyn LSP if dotnet is available |

---

## Configuration (`config.env`)

All user-facing settings in one file (`~/.config/simple-linux/config.env`):

```bash
SL_FONT="CaskaydiaCove Nerd Font Mono"
SL_FONT_SIZE="12"
SL_MAIN_MONITOR="DP-1" # leave empty for highest-resolution display
SL_MONITOR_ORDER="HDMI-A-1:0.67,DP-1" # NAME[:SCALE][:DIRECTION], comma-separated
SL_UI_SCALE="2" # UI/font scale (does not affect monitor resolution)
SL_TERMINAL="kitty"
SL_THEME_MODE="dark" # dark | light
SL_ICON_THEME="candy-icons"
SL_HYPRCURSOR_THEME="rose-pine-hyprcursor"
SL_HYPRCURSOR_SIZE="48"
SL_QT_DARK_THEME="catppuccin-mocha-mauve"
SL_QT_LIGHT_THEME="catppuccin-latte-mauve"
SL_PYENV_PYTHON_VER="3.12"
SL_CONTAINERS_DIR="/shared/containers"
SL_CONTAINERS_PERSISTENT_DIR="/shared/containers-persistent"
SL_CONTAINERS_CONFIG_FILE="${SL_CONTAINERS_DIR}/config.json"
SL_CONTAINERS_COMPOSE_FILE="${SL_CONTAINERS_DIR}/compose.yaml"
SL_OPENCODE_DIR="/shared/opencode"
SL_USER_FLATPAK_PACKAGES="app.zen_browser.zen" # Per-user flatpak packages
SL_USER_FLATPAK_OVERRIDES="" # Per-app flatpak overrides
```

Change any value, then run `sl-controller.sh update-themes` to apply. A full `reload-all` picks up everything.

---

## Theming System

Theming is a multi-stage pipeline driven by a single wallpaper image.

**Pipeline steps** (`sl-controller.sh update-themes`):

1. **GTK settings** — `gsettings` for GTK theme, color scheme, cursor, icon theme, font, UI scale
2. **Template rendering** — `envsubst` replaces all `${SL_*}` variables in config templates (Kitty, Qt, Kvantum, Hyprland env overrides, Quickshell settings)
3. **matugen** — `matugen image <wallpaper> --prefer saturation --mode <dark|light>` extracts Material Design 3 colors into `colors.css` and `colors.conf`
4. **Reload** — Quickshell restarted to pick up new colors

Monitor templates (`monitors.lua`, `workspaces.lua`, `hyprpaper.conf`) are rendered separately by `update-monitors`, which queries live display info from `hyprctl monitors -j`, generates the config blocks, exports them as `SL_MONITOR_BLOCKS` / `SL_WORKSPACE_BLOCKS` / `SL_HYPRPAPER_BLOCKS`, then substitutes them into the templates.

---

## Package Manager (`sl-install-package.sh`)

A user-level package manager for small tools, themes, and utilities. Everything installs into `$HOME` — no root, no sudo. Designed as an AUR replacement for packages where root is overkill: icon themes, cursor themes, CLI tools, font sets.

### Package Format (`.pkg.sh`)

Follows PKGBUILD conventions. A package file is a bash script defining:

```bash
pkgname=shellcheck
pkgver=0.11.0
pkgrel=1
url="https://github.com/koalaman/shellcheck"
source=("shellcheck-v${pkgver}.linux.x86_64.tar.gz::${url}/releases/download/v${pkgver}/shellcheck-v${pkgver}.linux.x86_64.tar.gz")
sha256sums=('b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6')
depends=()

package() {
    install -D "${srcdir}/shellcheck-v${pkgver}/shellcheck" "${pkgdir}/.local/bin/shellcheck"
}
```

`package()` stages files into `$pkgdir` using `$HOME`-relative paths (e.g. `${pkgdir}/.local/bin/foo`). Optional `build()` and `clean()` functions are supported for compilation workflows.

### Commands

```bash
sl-install-package.sh install <package-file>            # Install
sl-install-package.sh install <package-file> --force    # Reinstall regardless of version
sl-install-package.sh uninstall <package-file>          # Remove all tracked files
sl-install-package.sh list                              # List installed packages + versions
```

### Safety Features

| Feature | Detail |
|---|---|
| **Checksum verification** | All downloads verified against `sha256sums` |
| **Path traversal protection** | Rejects `..`, `../`, absolute paths, and newlines in paths |
| **File conflict detection** | Refuses to overwrite files owned by a different package |
| **Manifest tracking** | Every installed file recorded in `~/.local/share/install-package/db/` |
| **Orphan cleanup** | On version change, removes files no longer in the new version |
| **Empty directory pruning** | Cleans directories left empty after removal |

### Package Catalog

| Package | Description | Installs to |
|---|---|---|
| `shellcheck` 0.11.0-1 | Static analysis for shell scripts | `~/.local/bin/` |
| `rose-pine-hyprcursor` | Rose Pine cursor theme | `~/.local/share/icons/` |
| `pyenv` | Python version manager | `~/.pyenv/` |
| `oh-my-posh-bin` | Shell prompt themer (binary) | `~/.local/bin/` |
| `candy-icons` | Candy icon theme | `~/.local/share/icons/` |
| `dragon-drop` 1.2.0-1 | Drag-and-drop utility | `~/.local/bin/` |

---

## CLI Toolkit (`sl-toolset.sh`)

Available on PATH from `.bashrc`. Dispatch subcommands:

| Subcommand | Description |
|---|---|
| `backup` | Restic backup/restore (local, remote, push, pull). Accepts a `--config <file>` flag pointing to a standalone JSON config with repository details. |
| `containers` | nerdctl container management via compose: `up-all`, `down-all`, `up`, `down`, `restart` (with health checks). |
| `git-switch` | Switch git accounts and SSH keys per session. Reads profiles from a configurable directory. |
| `maintanance` | Btrfs maintenance, port listing, dangling dependency checks. |
| `notifications` | Desktop notifications, reminders, S.M.A.R.T. alerts. |
| `opencode` | Run OpenCode in a container. |
| `wireguard` | WireGuard setup (WIP — remote and local modes). |

---

## Desktop Environment

| Component | Role |
|---|---|
| **Hyprland** | Lua-based Wayland compositor. Modular config split across `env`, `env-overrides`, `keybinds`, `colors`, `rules`, `monitors`, `workspaces`, `default-apps`, `user-overrides`. |
| **Quickshell** | Custom Qt/QML desktop shell — status bar (CPU, memory, network, volume), notification center, app menu with system actions, system tray, wallpaper browser. |
| **Hyprlock** | Lock screen with blurred wallpaper and Material Design colors (`$primary`, `$on_primary`, `$error`, `$shadow`). |
| **Hypridle** | Idle daemon: dim screen → lock → DPMS off. |
| **Hyprsunset** | Night light / blue light filter. |
| **Kitty** | GPU-accelerated terminal emulator (config generated from template with font and size from `config.env`). |
| **Yazi** | Terminal file manager with desktop entry for `kitty --class yazi -e yazi`. |
| **Fastfetch** | System info displayed on login. |
| **feh** | Lightweight image viewer. |
| **mpv** | Media player with custom config. |
| **Neovim** | Fully configured text editor (Lua init, plugin manager, LSP support). |
| **Oh My Posh** | Shell prompt themer, colored via matugen template. |
| **PipeWire** | Audio server. |
| **Qt5ct / Qt6ct** | Qt5/Qt6 color scheme configuration, colors generated by matugen. |
| **Kvantum** | SVG-based Qt theming engine (Catppuccin Mocha/Latte Mauve variants). |

GTK theming uses `adw-gtk3` (dark/light toggled by `SL_THEME_MODE`). Both GTK3 and GTK4 import `colors.css` generated by matugen.
