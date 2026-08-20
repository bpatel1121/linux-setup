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

# Dotfiles live at the repo root (not in a subdir) and link into ~ directly.
HOME_DOTFILES=(.bashrc .zshrc .gitconfig .tmux.conf)

# The Hyprland/waybar/wofi/mako config is its own repo — see install_hypr.
HYPR_REPO="https://github.com/bpatel1121/hyprland"
LAZYVIM_STARTER="https://github.com/LazyVim/starter"

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

# clone_or_pull <url> <dest> [full]
# Shallow by default — right for third-party repos we only ever consume. Pass
# "full" for repos you edit and push from; shallow clones make that awkward.
clone_or_pull() {
  local url="$1" dest="$2" depth="${3:-shallow}"
  if [[ -d "$dest/.git" ]]; then
    info "Updating $(basename "$dest")"
    git -C "$dest" pull --ff-only --quiet || warn "pull failed for $dest (leaving as-is)"
  else
    info "Cloning $(basename "$dest")"
    local -a args=(clone)
    [[ "$depth" == full ]] || args+=(--depth=1)
    git "${args[@]}" "$url" "$dest"
  fi
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
  mapfile -t pkgs < <(read_pkg_list "$REPO_DIR/packages/pacman.txt" | sort -u)
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

# --- 4. AUR packages ---------------------------------------------------------
# packages/aur.txt is the single source of truth. Note that `yay` itself does not
# belong in it: install_yay bootstraps yay-bin, and the two conflict as providers.
install_aur_packages() {
  local -a pkgs
  mapfile -t pkgs < <(read_pkg_list "$REPO_DIR/packages/aur.txt" | sort -u)
  if ((${#pkgs[@]} == 0)); then warn "no AUR packages to install"; return 0; fi

  info "Installing ${#pkgs[@]} AUR package(s) via yay"
  if yay -S --needed --noconfirm -- "${pkgs[@]}"; then
    ok "AUR packages done"
    return 0
  fi

  # A single bad name — renamed, orphaned, or a debug split-package that isn't a
  # real target — fails the whole batch. Retry individually so everything that
  # *is* installable still lands, instead of set -e killing the run here.
  warn "batch install failed — retrying one package at a time"
  local p failed=0
  for p in "${pkgs[@]}"; do
    yay -S --needed --noconfirm -- "$p" || { warn "AUR install failed: $p"; ((failed++)) || true; }
  done
  ((failed == 0)) && ok "AUR packages done" || warn "$failed AUR package(s) failed — see above"
  return 0
}

# --- 5. oh-my-zsh + plugins --------------------------------------------------
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

# --- 6. hyprland desktop config ----------------------------------------------
# Hyprland, waybar, wofi and mako are all installed from packages/pacman.txt, but
# none of them are configured by this repo — the whole desktop lives in a separate
# repo whose root *is* ~/.config/hypr (hyprland.lua + scripts/ + themes/). So it's
# a plain clone into place, nothing to link. Without it a fresh box comes up with
# Hyprland running an empty config.
#
# Full clone rather than shallow: this one you actually edit and push from.
install_hypr() {
  clone_or_pull "$HYPR_REPO" "$CONFIG_HOME/hypr" full
  ok "hyprland config ready"
}

# The SDDM greeter is the one themed surface that lives outside ~/.config —
# SDDM runs as its own user and reads /usr/share/sddm/themes, so installing it
# needs root. The hypr repo's script handles the copy + the /etc/sddm.conf.d
# drop-in; sudo is already warm here, which is what makes this seamless on a
# fresh box. Never fatal: a theme with no sddm/ dir (or a failed install) just
# leaves the stock login screen.
install_sddm_theme() {
  local script="$CONFIG_HOME/hypr/scripts/sddm-apply.sh"
  [[ -f "$script" ]] || { warn "sddm-apply.sh not found in hypr repo — skipping login theme"; return 0; }
  info "Theming the SDDM login screen"
  sudo bash "$script" || warn "SDDM theme install failed — login screen left stock"
}

# Pacman hooks live outside any user's home (/etc/pacman.d/hooks), so they need
# root — same shape as the SDDM step. Currently one hook: refresh waybar's
# update counters after every transaction, so the Pac-Man chip clears whether
# you update from the bar, a shell, or yay. Never fatal.
install_pacman_hooks() {
  local src="$REPO_DIR/system/pacman-hooks"
  [[ -d "$src" ]] || return 0
  info "Installing pacman hooks"
  sudo install -d -m 755 /etc/pacman.d/hooks
  sudo install -m 644 "$src"/*.hook /etc/pacman.d/hooks/ \
    && ok "pacman hooks installed" || warn "pacman hook install failed (non-fatal)"
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

  # Root-level dotfiles -> ~/<name>   (.zshrc, .gitconfig, .tmux.conf, ...)
  # Runs after install_oh_my_zsh so nothing can clobber the .zshrc link.
  info "Linking dotfiles -> $HOME"
  local f
  for f in "${HOME_DOTFILES[@]}"; do
    link "$REPO_DIR/$f" "$HOME/$f"
  done

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

# --- 8. LazyVim --------------------------------------------------------------
# Runs after link_configs, which has already pointed ~/.config/nvim at
# config/nvim. All that's left is fetching the plugins.
install_lazyvim() {
  if ! command -v nvim >/dev/null; then
    warn "neovim not installed — skipping LazyVim"
    return 0
  fi

  # Only reachable if config/nvim is missing from the repo (nothing vendored yet).
  if [[ ! -e "$CONFIG_HOME/nvim" ]]; then
    info "No config/nvim in the repo — cloning the LazyVim starter"
    git clone --depth=1 "$LAZYVIM_STARTER" "$CONFIG_HOME/nvim"
    rm -rf "$CONFIG_HOME/nvim/.git"
  fi

  # lua/config/lazy.lua bootstraps lazy.nvim itself on first start, so `install`
  # covers a cold machine. `restore` then pins every plugin to the revisions in
  # lazy-lock.json, reproducing the exact set this repo was tested with.
  #
  # Deliberately NOT `Lazy! sync`: sync updates plugins to latest and rewrites
  # lazy-lock.json — and since ~/.config/nvim is a symlink into this repo, that
  # would dirty the git tree on every provisioning run.
  #
  # Never fatal: a flaky GitHub fetch shouldn't take down the whole run, and
  # lazy.nvim installs anything still missing on the next interactive launch.
  info "Installing LazyVim plugins (slow on a fresh box)"
  if nvim --headless "+Lazy! install" +qa && nvim --headless "+Lazy! restore" +qa; then
    ok "LazyVim ready"
  else
    warn "plugin install failed — retry later with:"
    warn "  nvim --headless '+Lazy! install' +qa && nvim --headless '+Lazy! restore' +qa"
  fi
}

# --- 9. system services -----------------------------------------------------
# Installing a package does NOT enable its service. Without this step a truly
# fresh box boots with no network, no display manager, no bluetooth, and an
# inert firewall. `systemctl enable` is idempotent, so this is free on re-runs.
enable_services() {
  info "Enabling system services"
  local s
  for s in NetworkManager sddm bluetooth ufw; do
    if systemctl list-unit-files --type=service | grep -q "^$s.service"; then
      sudo systemctl enable "$s" >/dev/null 2>&1 && ok "enabled $s" || warn "could not enable $s"
    else
      warn "$s.service not found — is the package installed?"
    fi
  done

  # ufw: enabling the unit starts the daemon, but the firewall itself must be
  # turned on once with sane defaults. Idempotent: skip if already active.
  if command -v ufw >/dev/null && ! sudo ufw status | grep -q "^Status: active"; then
    info "Activating ufw (deny incoming / allow outgoing)"
    sudo ufw default deny incoming  >/dev/null
    sudo ufw default allow outgoing >/dev/null
    sudo ufw --force enable         >/dev/null
    ok "ufw active"
  fi
}

# --- audit mode: ./setup.sh --audit ------------------------------------------
# Answers "is this box still minimal?" without installing anything:
#   1. explicit packages on the box that the repo doesn't know about (drift —
#      hardware packages are EXPECTED here, that's the per-box set)
#   2. packages in the lists but missing from the box
#   3. orphaned dependencies nothing requires anymore
#   4. explicit leaves (-Qqet): the true "stuff I chose" list
audit_packages() {
  local all_lists
  all_lists=$(read_pkg_list "$REPO_DIR/packages/pacman.txt" | sort -u)

  info "Explicit REPO packages not in packages/*.txt (drift — hardware is expected here):"
  comm -23 <(pacman -Qqen | sort) <(printf '%s\n' "$all_lists") | sed 's/^/    /'

  info "Foreign (AUR) packages not in aur.txt:"
  # yay itself and -debug artifacts are expected foreigners — filter the noise.
  comm -23 <(pacman -Qqem | sort) <(read_pkg_list "$REPO_DIR/packages/aur.txt" | sort -u) \
    | grep -vE '^(yay|yay-bin)$|-debug$' | sed 's/^/    /'

  info "Listed in the repo but NOT installed on this box:"
  # each comm input must be ONE globally sorted stream, not two sorted lists
  # concatenated — that's what tripped "comm: file is not in sorted order".
  comm -13 <({ pacman -Qqen; pacman -Qqem; } | sort -u) \
           <({ printf '%s\n' "$all_lists"; read_pkg_list "$REPO_DIR/packages/aur.txt"; } | sort -u) | sed 's/^/    /'

  info "Orphaned dependencies (remove with: sudo pacman -Rns \$(pacman -Qdtq)):"
  pacman -Qdtq 2>/dev/null | sed 's/^/    /' || ok "none"

  echo
  info "Full explicit-leaf list (explicit AND nothing depends on it):"
  pacman -Qqet | sed 's/^/    /'
}

# --- main --------------------------------------------------------------------
main() {
  if [[ "${1:-}" == "--audit" ]]; then
    command -v pacman >/dev/null || die "pacman not found"
    audit_packages
    exit 0
  fi

  preflight
  install_base
  install_pacman_packages
  install_yay
  install_aur_packages
  enable_services
  install_oh_my_zsh
  install_hypr      # before link_configs: wezterm.lua reads the theme tree
  install_sddm_theme # after install_hypr: runs the hypr repo's sddm-apply.sh
  install_pacman_hooks
  link_configs
  install_lazyvim   # after link_configs: needs ~/.config/nvim to exist

  echo
  ok "Provisioning complete."
  # `|| true`: without it, set -e exits here on a re-run that backed nothing up,
  # skipping the hint below and returning non-zero from a perfectly good run.
  [[ -d "$BACKUP_DIR" ]] && warn "Replaced configs were backed up to $BACKUP_DIR" || true
  echo "Start a new shell, then apply the desktop theme with:"
  echo "  ~/.config/hypr/scripts/theme-apply.sh"
}

main "$@"
