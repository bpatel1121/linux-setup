# linux-setup

My Arch Linux dotfiles and packages, plus a `setup.sh` that recreates a working
environment on a new machine in one command: packages, `yay`, oh-my-zsh, the
Hyprland desktop config, every dotfile symlinked, and LazyVim with its plugins
already installed.

## Contents

- `.bashrc`, `.zshrc` — shell config
- `.gitconfig` — git identity + aliases
- `.tmux.conf` — tmux config
- `config/nvim/` — LazyVim config (plugins pinned by `lazy-lock.json`)
- `config/wezterm/` — terminal config
- `packages/pacman.txt` — official-repo packages
- `packages/aur.txt` — AUR packages
- `setup.sh` — one-shot provisioner (packages + yay + symlinks + LazyVim)
- `local-run` — secret-injection wrapper (see below)

## Quick start

```
git clone https://github.com/bpatel1121/linux-setup.git ~/Projects/linux-setup
cd ~/Projects/linux-setup
./setup.sh
```

To sync later, just pull and re-run — every step is idempotent:

```
cd ~/Projects/linux-setup && git pull && ./setup.sh
```

## What setup.sh does

1. `pacman -Syu`, then the base toolchain (`base-devel git curl zsh tmux`).
2. Installs `packages/pacman.txt`.
3. Bootstraps `yay` from `yay-bin` (prebuilt — no Go compile). Don't put `yay`
   itself in `aur.txt`: it conflicts with `yay-bin` as a provider.
4. Installs `packages/aur.txt`. If the batch fails it retries package-by-package,
   so one dead AUR name warns instead of aborting the run.
5. Enables system services (`NetworkManager`, `sddm`, `bluetooth`, `ufw`) and
   activates the firewall with deny-in/allow-out defaults. Installing a package
   does not enable its service — without this a fresh box boots to a black
   screen with no network.
6. Clones oh-my-zsh + `zsh-autosuggestions` / `zsh-syntax-highlighting`, and
   `chsh`es to zsh.
7. Clones the **Hyprland config** (see below) into `~/.config/hypr`.
8. Symlinks `config/*` → `~/.config/<name>` and the root dotfiles → `~`. Anything
   real that's in the way is moved to `~/.config-backup/<timestamp>/` first;
   symlinks owned by another repo are left alone with a warning.
9. Installs LazyVim's plugins headlessly (`Lazy! install` then `Lazy! restore`),
   so the first `nvim` launch is instant and plugins match `lazy-lock.json`.

Symlinks, not copies — edit either side and both change, and `git pull` updates
the live config immediately.

## The Hyprland config lives in a separate repo

`hyprland`, `waybar`, `wofi`, and `mako` are installed from `pacman.txt`, but
none of them are configured here. The whole desktop — `hyprland.lua`, the theme
switcher, and the themes themselves — is
[bpatel1121/hyprland](https://github.com/bpatel1121/hyprland), whose repo root
*is* `~/.config/hypr`. `setup.sh` clones it there directly; there's nothing to
link.

That repo owns `~/.config/mako/config` too — `scripts/theme-apply.sh` repoints it
on every theme switch, so `~/.config/mako` must stay a real directory and is
deliberately not managed here.

After provisioning, apply the active theme with:

```
~/.config/hypr/scripts/theme-apply.sh
```

## Hardware

CPU microcode and GPU drivers are deliberately **not** in these lists — they
differ per box, and keeping them out is what makes the lists transferable to any
Arch machine. Install whatever the hardware needs by hand after provisioning.

## Regenerating the package lists

To refresh from what's currently installed — explicitly installed, repo packages
only — then hand-sort into the two files (dropping hardware packages):

```
pacman -Qqen > /tmp/repo-explicit.txt   # repo, explicit
pacman -Qqem > /tmp/aur-explicit.txt    # AUR/foreign, for reference
```

`-Qqe` lists explicitly installed packages (not pulled-in dependencies);
`-n` = repo, `-m` = AUR.

Two things to strip from the output before committing: `-debug` split-packages
(`yay-debug` and friends aren't installable targets), and `yay` itself, which
`setup.sh` bootstraps as `yay-bin`.

## Secret injection (local-run)

`local-run` injects secrets into a command's environment from a local,
gitignored secrets file. The secrets themselves are NEVER committed.

### Setup on a new machine

`setup.sh` already makes `local-run` executable and links it to
`~/.local/bin/local-run`, so all that's left is creating your local secrets file
(NEVER committed — gitignored):

```
nvim ~/.local-secrets
```

Add secrets as `KEY=VALUE` lines, for example:

```
MY_API_KEY=actual-secret-value-here
```

### Usage

Make a template file with `local://` placeholders referencing your secrets:

```
# example.env
API_KEY=local://MY_API_KEY
```

Run a command with secrets injected as environment variables:

```
local-run example.env -- your-command
```

The script reads `~/.local-secrets`, swaps the `local://` placeholders for real
values, and runs the command with those as environment variables. Real secrets
exist only in `~/.local-secrets` and at runtime — never in git.
