#!/usr/bin/env bash
#
# linux-setup provisioner
#
# Idempotent. Safe to re-run. Run from anywhere:
#   ./setup.sh
#
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN_DIR="$HOME/.local/bin"
BACKUP_DIR="$HOME/.config-backup/$(date +%Y%m%d-%H%M%S)"

# AUR packages guaranteed regardless of packages/aur.txt contents.
REQUIRED_AUR=(spotify)

# --- output helpers ----------------------------------------------------------
c_info=$'\e[1;36m'; c_ok=$'\e[1;32m'; c_warn=$'\e[1;33m'; c_err=$'\e[1;31m'; c_off=$'\e[0m'
info() { printf '%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$c_ok"   "$c_off" "$*"; }
warn() { printf '%swarn%s %s\n' "$c_warn" "$c_off" "$*" >&2; }
die()  { printf '%s err%s %s\n' "$c_err"  "$c_off" "$*" >&2; exit 1; }

# --- preflight ---------------------------------------------------------------
preflight() {
  [[ $EUID -ne 0 ]] || die "Do not run as root. makepkg refuses to build as root; sudo is invoked per-command."
  command -v pacman >/dev/null || die "pacman not found. This script is Arch-only."

  info "Requesting sudo up front"
  sudo -v
  # Keep the sudo timestamp warm for the whole run (long AUR builds outlive the default 15m).
  while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
}

# Read a package list: strip comments, inline comments, blanks, whitespace.
read_pkg_list() {
  local file="$1"
  [[ -f "$file" ]] || { warn "missing $file — skipping"; return 0; }
  sed -e 's/#.*//' -e 's/[[:space:]]\+//g' -e '/^$/d' "$file"
}

# --- 1. system update + base toolchain ---------------------------------------
install_base() {
  info "Syncing repos and updating system"
  sudo pacman -Syu --noconfirm

  info "Ensuring build toolchain (base-devel, git, curl, zsh, tmux)"
  sudo pacman -S --needed --noconfirm base-devel git curl zsh tmux
}

# --- 2. pacman packages ------------------------------------------------------
install_pacman_packages() {
  local -a pkgs
  mapfile -t pkgs < <(read_pkg_list "$REPO_DIR/packages/pacman.txt")
  if ((${#pkgs[@]} == 0)); then warn "no pacman packages listed"; return 0; fi

  info "Installing ${#pkgs[@]} pacman package(s)"
  # --needed skips anything already present, so this is cheap on re-runs.
  sudo pacman -S --needed --noconfirm -- "${pkgs[@]}"
  ok "pacman packages done"
}

# --- 3. yay bootstrap --------------------------------------------------------
install_yay() {
  if command -v yay >/dev/null; then
    ok "yay already present ($(yay --version | head -n1))"
    return 0
  fi

  info "Bootstrapping yay from the AUR"
  local tmp
  tmp="$(mktemp -d)"
  # yay-bin ships a prebuilt binary — no Go toolchain, no 5-minute compile.
  git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
  ( cd "$tmp/yay-bin" && makepkg -si --noconfirm )
  rm -rf "$tmp"

  command -v yay >/dev/null || die "yay bootstrap failed"
  ok "yay installed"
}

# --- 4. Spotify GPG key ------------------------------------------------------
# The AUR `spotify` PKGBUILD verifies the upstream .deb against Spotify's signing
# key. If the key isn't in your keyring, the build fails with
# "unknown public key" — this is the single most common failure on a fresh box.
import_spotify_key() {
  local key="C85668DF69375001"
  if gpg --list-keys "$key" &>/dev/null; then
    ok "Spotify signing key already in keyring"
    return 0
  fi
  info "Importing Spotify signing key ($key)"
  if curl -fsSL "https://download.spotify.com/debian/pubkey_${key}.gpg" | gpg --import -; then
    ok "Spotify key imported"
  else
    warn "Could not import Spotify key — the spotify build will likely fail."
    warn "Fallback: sudo pacman -S spotify-launcher  (official repo, no AUR, no key dance)"
  fi
}

# --- 5. AUR packages ---------------------------------------------------------
install_aur_packages() {
  local -a pkgs
  mapfile -t pkgs < <(read_pkg_list "$REPO_DIR/packages/aur.txt")
  pkgs+=("${REQUIRED_AUR[@]}")

  # dedupe, preserving nothing in particular
  mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | sort -u)
  if ((${#pkgs[@]} == 0)); then warn "no AUR packages to install"; return 0; fi

  # Only fuss with the GPG key if spotify is actually in the set.
  if printf '%s\n' "${pkgs[@]}" | grep -qx 'spotify'; then
    import_spotify_key
  fi

  info "Installing ${#pkgs[@]} AUR package(s) via yay"
  yay -S --needed --noconfirm -- "${pkgs[@]}"
  ok "AUR packages done"
}

# --- 6. oh-my-zsh + plugins --------------------------------------------------
# Cloned directly rather than piping install.sh into a shell: the official
# installer wants to rewrite ~/.zshrc and run chsh, both of which fight with a
# provisioner that owns the dotfiles. A clone is the same result, fully idempotent.
OMZ_DIR="$HOME/.oh-my-zsh"
ZSH_CUSTOM="$OMZ_DIR/custom"

# name -> repo url
OMZ_PLUGINS=(
  "zsh-autosuggestions     https://github.com/zsh-users/zsh-autosuggestions"
  "zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting"
)

clone_or_pull() {
  local url="$1" dest="$2"
  if [[ -d "$dest/.git" ]]; then
    info "Updating $(basename "$dest")"
    git -C "$dest" pull --ff-only --quiet || warn "pull failed for $dest (leaving as-is)"
  else
    info "Cloning $(basename "$dest")"
    git clone --depth=1 "$url" "$dest"
  fi
}

install_oh_my_zsh() {
  clone_or_pull "https://github.com/ohmyzsh/ohmyzsh" "$OMZ_DIR"

  mkdir -p "$ZSH_CUSTOM/plugins" "$ZSH_CUSTOM/themes"
  local entry name url
  for entry in "${OMZ_PLUGINS[@]}"; do
    read -r name url <<<"$entry"
    clone_or_pull "$url" "$ZSH_CUSTOM/plugins/$name"
  done
  ok "oh-my-zsh ready"

  # Login shell. chsh needs your password; skip silently if already zsh.
  local zsh_path
  zsh_path="$(command -v zsh)"
  if [[ "${SHELL:-}" != "$zsh_path" ]]; then
    info "Setting login shell to zsh (you'll be prompted for your password)"
    chsh -s "$zsh_path" || warn "chsh failed — run manually: chsh -s $zsh_path"
  else
    ok "login shell already zsh"
  fi
}

# --- 7. dotfile symlinks -----------------------------------------------------
# Links repo dirs into ~/.config. Existing real files/dirs get moved to a
# timestamped backup rather than clobbered.
link() {
  local src="$1" dest="$2"

  [[ -e "$src" ]] || { warn "source missing: $src — skipping"; return 0; }

  if [[ -L "$dest" ]]; then
    local existing
    existing="$(readlink -f "$dest" || true)"
    if [[ "$existing" == "$(readlink -f "$src")" ]]; then
      ok "already linked: $dest"
      return 0
    fi
    # Almost certainly a theme link from the dotfiles repo. Do not clobber silently.
    warn "$dest is already a symlink -> $existing"
    warn "  refusing to replace it with $src (another repo probably owns this)."
    warn "  If linux-setup should own it, remove the link first: rm '$dest'"
    return 0
  elif [[ -e "$dest" ]]; then
    mkdir -p "$BACKUP_DIR"
    warn "backing up existing $dest -> $BACKUP_DIR/"
    mv "$dest" "$BACKUP_DIR/"
  fi

  mkdir -p "$(dirname "$dest")"
  ln -sfn "$src" "$dest"
  ok "linked $dest -> $src"
}

link_configs() {
  # Anything in config/ -> ~/.config/<name>
  if [[ -d "$REPO_DIR/config" ]]; then
    info "Linking config/ -> $CONFIG_HOME"
    local d
    for d in "$REPO_DIR/config"/*; do
      [[ -e "$d" ]] || continue
      link "$d" "$CONFIG_HOME/$(basename "$d")"
    done
  fi

  # Anything in home/ -> ~/<name>   (.zshrc, .gitconfig, .tmux.conf, ...)
  # Runs after install_oh_my_zsh so nothing can clobber the .zshrc link.
  if [[ -d "$REPO_DIR/home" ]]; then
    info "Linking home/ -> $HOME"
    local f
    shopt -s dotglob nullglob
    for f in "$REPO_DIR/home"/*; do
      link "$f" "$HOME/$(basename "$f")"
    done
    shopt -u dotglob nullglob
  else
    warn "no home/ dir — ~/.zshrc, ~/.gitconfig, ~/.tmux.conf are unmanaged."
  fi

  info "Installing local-run"
  mkdir -p "$BIN_DIR"
  chmod +x "$REPO_DIR/local-run" 2>/dev/null || true
  link "$REPO_DIR/local-run" "$BIN_DIR/local-run"

  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not on your PATH — add it in ~/.zshrc:"
       warn '  export PATH="$HOME/.local/bin:$PATH"' ;;
  esac
}

# --- main --------------------------------------------------------------------
main() {
  preflight
  install_base
  install_pacman_packages
  install_yay
  install_aur_packages
  install_oh_my_zsh
  link_configs

  echo
  ok "Provisioning complete."
  [[ -d "$BACKUP_DIR" ]] && warn "Replaced configs were backed up to $BACKUP_DIR"
  echo "Reload mako with:  makoctl reload"
}

main "$@"
