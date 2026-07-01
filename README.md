# linux-setup

My Arch Linux dotfiles and packages. Configs for bash, git, tmux, and Alacritty,
plus the package lists and a `setup.sh` to recreate a working environment on a
new machine.

Hardware packages (CPU microcode, GPU drivers) are deliberately **not** in these
lists or the script — they differ per box and are installed by hand. The lists
stay transferable to any Arch machine, present or future.

## Contents

- `.bashrc` — shell config
- `.gitconfig` — git identity + aliases
- `.tmux.conf` — tmux config
- `alacritty.toml` — terminal config
- `package.txt` — core packages (CLI, base system, boot) — every Arch machine
- `gui-package.txt` — desktop packages (KDE + GUI apps) — machines with a display
- `setup.sh` — one-shot provisioner (symlinks + packages + yay)
- `local-run` — secret-injection wrapper (see below)

## Quick start

```
git clone https://github.com/bpatel1121/linux-setup.git ~/dotfiles
cd ~/dotfiles
chmod +x setup.sh
./setup.sh
```

`setup.sh` symlinks the configs, installs the core packages, prompts about the
desktop packages, and bootstraps `yay`. Hardware (CPU microcode, GPU drivers) is
per-box — install it separately by hand afterward. Flags: `--gui` / `--no-gui`
skip the prompt (useful for non-interactive or headless runs).

To sync later, just pull and re-run — every step is idempotent:

```
cd ~/dotfiles && git pull && ./setup.sh
```

## Manual setup (what setup.sh does)

If you'd rather run it by hand, or the script isn't available:

```
# 1. symlink configs
ln -sf ~/dotfiles/.bashrc ~/.bashrc
ln -sf ~/dotfiles/.gitconfig ~/.gitconfig
ln -sf ~/dotfiles/.tmux.conf ~/.tmux.conf
mkdir -p ~/.config/alacritty
ln -sf ~/dotfiles/alacritty.toml ~/.config/alacritty/alacritty.toml

# 2. core packages (every machine)
sudo pacman -S --needed - < ~/dotfiles/package.txt

# 3. desktop packages (machines with a display only)
sudo pacman -S --needed - < ~/dotfiles/gui-package.txt

# 4. hardware layer — per box, install CPU microcode + GPU drivers by hand

# 5. bootstrap yay (not in the official repos, so build from source)
sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay.git /tmp/yay
cd /tmp/yay && makepkg -si

# 6. apply shell config
source ~/.bashrc
```

## Hardware

CPU microcode and GPU drivers depend on the actual hardware in each box, so
they're not in the transferable lists or the script. Install them by hand per
machine after running setup.

`mesa` (generic OpenGL) is intentionally in `gui-package.txt`, not treated as a
hardware package — it's vendor-neutral and works on any graphical machine.

## Regenerating the package lists

To refresh from what's currently installed — explicitly installed, repo packages
only — then hand-sort into the two files (dropping hardware packages):

```
pacman -Qqen > /tmp/repo-explicit.txt   # repo, explicit
pacman -Qqem > /tmp/aur-explicit.txt    # AUR/foreign, for reference
```

`-Qqe` lists explicitly installed packages (not pulled-in dependencies);
`-n` = repo, `-m` = AUR.

## Secret injection (local-run)

`local-run` injects secrets into a command's environment from a local,
gitignored secrets file. The secrets themselves are NEVER committed.

### Setup on a new machine

The `local-run` script comes with this repo. Make it executable:

```
chmod +x ~/dotfiles/local-run
```

Optionally symlink it onto your PATH:

```
ln -sf ~/dotfiles/local-run ~/.local/bin/local-run
```

Create your local secrets file (NEVER committed — gitignored):

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
