#!/usr/bin/env bash
#
# setup.sh — provision an Arch machine from this repo.
# Runs the transferable layer (configs + core/gui packages + yay).
# Hardware (CPU microcode, GPU drivers) is per-box and is NOT installed —
# a short reminder is printed at the end.
#
# Usage:
#   ./setup.sh            # auto-detect: prompt about desktop packages
#   ./setup.sh --gui      # force-install desktop packages (non-interactive)
#   ./setup.sh --no-gui   # skip desktop packages (headless/server)
#
# Re-running after `git pull` is how you sync — every step is idempotent.

set -euo pipefail

# --- guards -----------------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
  echo "Don't run this as root. It symlinks into \$HOME and builds AUR" >&2
  echo "packages as your user; it will call sudo itself where needed." >&2
  exit 1
fi
if ! command -v pacman >/dev/null 2>&1; then
  echo "pacman not found — this script is for Arch Linux." >&2
  echo "(On a WSL/Ubuntu box use apt; these lists don't apply there.)" >&2
  exit 1
fi

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- args -------------------------------------------------------------------
GUI=auto
for arg in "$@"; do
  case "$arg" in
    --gui)     GUI=yes ;;
    --no-gui)  GUI=no ;;
    -h|--help) sed -n '3,14p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg (try --gui, --no-gui, --help)" >&2; exit 1 ;;
  esac
done

info() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

# --- symlinks ---------------------------------------------------------------
link() {
  local src="$1" dst="$2"
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    mv "$dst" "$dst.bak.$(date +%s)"
    echo "  backed up existing $dst"
  fi
  ln -sf "$src" "$dst"
  echo "  linked $dst"
}

info "Symlinking configs"
link "$DOTFILES/.bashrc"        "$HOME/.bashrc"
link "$DOTFILES/.gitconfig"     "$HOME/.gitconfig"
link "$DOTFILES/.tmux.conf"     "$HOME/.tmux.conf"
mkdir -p "$HOME/.config/alacritty"
link "$DOTFILES/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"

# --- core packages ----------------------------------------------------------
info "Installing core packages (package.txt)"
sudo pacman -S --needed - < "$DOTFILES/package.txt"

# --- gui decision -----------------------------------------------------------
if [[ "$GUI" == auto ]]; then
  if [[ -t 0 ]]; then
    read -rp $'\nInstall desktop packages (gui-package.txt)? [Y/n] ' ans
    if [[ "$ans" =~ ^[Nn] ]]; then GUI=no; else GUI=yes; fi
  else
    echo "Non-interactive run with no --gui/--no-gui flag; skipping desktop packages."
    GUI=no
  fi
fi

if [[ "$GUI" == yes ]]; then
  info "Installing desktop packages (gui-package.txt)"
  sudo pacman -S --needed - < "$DOTFILES/gui-package.txt"
else
  info "Skipping desktop packages"
fi

# --- yay bootstrap ----------------------------------------------------------
if ! command -v yay >/dev/null 2>&1; then
  info "Bootstrapping yay (AUR helper)"
  sudo pacman -S --needed git base-devel
  tmp="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay.git "$tmp/yay"
  ( cd "$tmp/yay" && makepkg -si --noconfirm )
  rm -rf "$tmp"
else
  echo "yay already installed — skipping bootstrap"
fi

# --- hardware reminder (deliberately NOT automated) -------------------------
info "Hardware layer — install by hand, per box"
echo "  CPU microcode and GPU drivers depend on this machine's hardware and are"
echo "  NOT installed by this script. Install them manually after setup."

info "Done. Restart your shell or run: source ~/.bashrc"
