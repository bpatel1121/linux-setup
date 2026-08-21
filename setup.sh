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

# Dotfiles live in home/ WITHOUT their leading dot, and gain it when linked:
# home/zshrc -> ~/.zshrc. Storing them undotted keeps them visible to a plain
# `ls`, stops the repo root from looking like a second $HOME, and avoids tools
# that refuse to index directories containing shell rc files.
HOME_DOTFILES=(bashrc zshrc gitconfig tmux.conf)

# The Hyprland/waybar/wofi/mako config is its own repo — see install_hypr.
HYPR_REPO="https://github.com/bpatel1121/hyprland"

# --- output helpers ----------------------------------------------------------
c_info=$'\e[1;36m'
c_ok=$'\e[1;32m'
c_warn=$'\e[1;33m'
c_err=$'\e[1;31m'
c_off=$'\e[0m'
info() { printf '%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
ok() { printf '%s  ok%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '%swarn%s %s\n' "$c_warn" "$c_off" "$*" >&2; }
die() {
  printf '%s err%s %s\n' "$c_err" "$c_off" "$*" >&2
  exit 1
}

# --- preflight ---------------------------------------------------------------
preflight() {
  [[ $EUID -ne 0 ]] || die "Do not run as root. makepkg refuses to build as root; sudo is invoked per-command."
  command -v pacman >/dev/null || die "pacman not found. This script is Arch-only."

  info "Requesting sudo up front"
  sudo -v
  # Keep the sudo timestamp warm for the whole run (long AUR builds outlive the default 15m).
  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" 2>/dev/null || exit
  done 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
}

# Read a package list: strip comments, inline comments, blanks, whitespace.
read_pkg_list() {
  local file="$1"
  [[ -f "$file" ]] || {
    warn "missing $file — skipping"
    return 0
  }
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

  # Only what the yay bootstrap needs before packages/pacman.txt is installed —
  # zsh, tmux and the rest are in that list and land a step later.
  info "Ensuring build toolchain (base-devel, git)"
  sudo pacman -S --needed --noconfirm base-devel git
}

# --- 2. pacman packages ------------------------------------------------------
install_pacman_packages() {
  local -a pkgs
  mapfile -t pkgs < <(read_pkg_list "$REPO_DIR/packages/pacman.txt" | sort -u)
  if ((${#pkgs[@]} == 0)); then
    warn "no pacman packages listed"
    return 0
  fi

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
  (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
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
  if ((${#pkgs[@]} == 0)); then
    warn "no AUR packages to install"
    return 0
  fi

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
    yay -S --needed --noconfirm -- "$p" || {
      warn "AUR install failed: $p"
      ((failed++)) || true
    }
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
  # `|| true`: an unguarded command substitution under set -e would abort the
  # whole run with no message if zsh ever went missing from packages/pacman.txt.
  local zsh_path
  zsh_path="$(command -v zsh || true)"
  if [[ -z "$zsh_path" ]]; then
    warn "zsh not installed — skipping chsh"
  elif [[ "${SHELL:-}" != "$zsh_path" ]]; then
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
#
# ORDER MATTERS, and used to be wrong in a way that never showed up as an
# error. sddm-apply.sh refuses when themes/current is missing — and that
# symlink is gitignored MACHINE state, so the clone install_hypr just made
# does not have one. The only thing that creates it is theme-apply.sh, which
# this script merely *suggested* on its last line. So on every fresh box the
# SDDM step ran, exited 1 for a perfectly good reason, got swallowed by the
# `|| warn` below, and left a stock login screen that looked like a theme
# nobody had gotten around to configuring.
#
# Running theme-apply.sh here fixes it at the source: it owns the default
# theme name (this script must not duplicate it), it is idempotent, and it is
# what the end-of-run hint tells you to run anyway. It is safe with no session
# yet — it is `set -uo pipefail` without -e, and every hyprctl/pkill/wallpaper
# call inside is individually `|| true` guarded, so headless it does little
# more than create the symlink.
install_sddm_theme() {
  local script="$CONFIG_HOME/hypr/scripts/sddm-apply.sh"
  [[ -f "$script" ]] || {
    warn "sddm-apply.sh not found in hypr repo — skipping login theme"
    return 0
  }

  local apply="$CONFIG_HOME/hypr/scripts/theme-apply.sh"
  [[ -f "$apply" ]] && bash "$apply" >/dev/null 2>&1 || true

  info "Theming the SDDM login screen"
  if sudo bash "$script"; then
    # sddm-apply.sh exits 0 when the active theme simply ships no sddm/ dir,
    # which is legitimate — but so is checking, because "succeeded" and
    # "changed the login screen" are not the same thing, and the gap between
    # them is precisely what hid the bug above for months.
    [[ -f /etc/sddm.conf.d/10-hypr-theme.conf ]] ||
      warn "SDDM step succeeded but wrote no drop-in — login screen is still stock"
  else
    warn "SDDM theme install failed — login screen left stock"
  fi
}

# Everything in system/ lives outside any user's home, so it needs root — same
# shape as the SDDM step, and never fatal:
#   pacman-hooks/  refresh waybar's update counters after every transaction, so
#                  the Pac-Man chip clears whether you update from the bar, a
#                  shell, or yay.
#   zram-generator.conf  zram-generator ships NO default config and does nothing
#                  without one, so the package alone buys you no swap. Applies
#                  at the next boot.
#   sddm-hypr-theme.service.in  re-runs sddm-apply.sh before the greeter starts,
#                  so the login screen follows SUPER+T without theme-switch.sh
#                  needing root. RENDERED, not copied: systemd wants an absolute
#                  ExecStart and no tracked file here may bake in a username —
#                  same @PLACEHOLDER@ treatment hyprlock.conf gets in the hypr
#                  repo. Boot rather than shutdown, because a shutdown unit is
#                  skipped on a crash or a hard power-off and you would only
#                  find out at the next login screen.
install_system_files() {
  local src="$REPO_DIR/system"
  [[ -d "$src" ]] || return 0
  info "Installing system files (pacman hooks, zram, sddm theme unit)"
  sudo install -d -m 755 /etc/pacman.d/hooks
  sudo install -m 644 "$src"/pacman-hooks/*.hook /etc/pacman.d/hooks/ &&
    ok "pacman hooks installed" || warn "pacman hook install failed (non-fatal)"
  sudo install -m 644 "$src"/zram-generator.conf /etc/systemd/zram-generator.conf &&
    ok "zram config installed (active next boot)" || warn "zram config install failed (non-fatal)"

  # `|` as the sed delimiter since $HOME contains slashes. Rendered to a temp
  # file first so a failed sed can never leave a half-written unit in /etc.
  local unit=/etc/systemd/system/sddm-hypr-theme.service tmp
  tmp=$(mktemp)
  if sed "s|@HOME@|$HOME|g" "$src"/sddm-hypr-theme.service.in >"$tmp" &&
    sudo install -m 644 "$tmp" "$unit"; then
    sudo systemctl daemon-reload
    sudo systemctl enable sddm-hypr-theme.service >/dev/null 2>&1 &&
      ok "sddm theme unit installed (greeter follows the theme from next boot)" ||
      warn "sddm theme unit installed but enable failed (non-fatal)"
  else
    warn "sddm theme unit install failed (non-fatal) — greeter will not auto-follow"
  fi
  rm -f "$tmp"
}

# --- 7. dotfile symlinks -----------------------------------------------------
# Links repo dirs into ~/.config. Existing real files/dirs get moved to a
# timestamped backup rather than clobbered.
link() {
  local src="$1" dest="$2"

  [[ -e "$src" ]] || {
    warn "source missing: $src — skipping"
    return 0
  }

  if [[ -L "$dest" ]]; then
    local existing
    existing="$(readlink -f "$dest" || true)"
    if [[ "$existing" == "$(readlink -f "$src")" ]]; then
      ok "already linked: $dest"
      return 0
    fi
    # A link into this repo (or a dangling one left by a file move) is ours to
    # fix — that's the whole point of --link-only. Anything else belongs to
    # another repo (the hypr theme links) and is left alone.
    if [[ "$existing" == "$REPO_DIR"/* || ! -e "$existing" ]]; then
      info "re-linking stale $dest -> $existing"
    else
      warn "$dest is already a symlink -> $existing"
      warn "  refusing to replace it with $src (another repo probably owns this)."
      warn "  If linux-setup should own it, remove the link first: rm '$dest'"
      return 0
    fi
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

  # home/<name> -> ~/.<name>   (home/zshrc -> ~/.zshrc, ...)
  # Runs after install_oh_my_zsh so nothing can clobber the .zshrc link.
  info "Linking dotfiles -> $HOME"
  local f
  for f in "${HOME_DOTFILES[@]}"; do
    link "$REPO_DIR/home/$f" "$HOME/.$f"
  done

  info "Installing local-run"
  mkdir -p "$BIN_DIR"
  link "$REPO_DIR/local-run" "$BIN_DIR/local-run"

  case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    warn "$BIN_DIR is not on your PATH — add it in ~/.zshrc:"
    warn '  export PATH="$HOME/.local/bin:$PATH"'
    ;;
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
  # No pre-flight unit-file scan: systemctl already fails on a missing unit,
  # and scanning every unit file once per service was the slow way to ask.
  local s
  for s in NetworkManager sddm bluetooth ufw power-profiles-daemon; do
    sudo systemctl enable "$s" >/dev/null 2>&1 &&
      ok "enabled $s" || warn "could not enable $s — is the package installed?"
  done

  # ufw: enabling the unit starts the daemon, but the firewall itself must be
  # turned on once with sane defaults. Idempotent: skip if already active.
  if command -v ufw >/dev/null && ! sudo ufw status | grep -q "^Status: active"; then
    info "Activating ufw (deny incoming / allow outgoing)"
    sudo ufw default deny incoming >/dev/null
    sudo ufw default allow outgoing >/dev/null
    sudo ufw --force enable >/dev/null
    ok "ufw active"
  fi
}

# --- 10. XDG user directories -------------------------------------------------
# Apps read XDG_DOWNLOAD_DIR from ~/.config/user-dirs.dirs to decide where saved
# files land. On a minimal Arch install that file doesn't exist, so browsers
# either nag on every download or drop things in $HOME. Written directly rather
# than pulling in xdg-user-dirs, which would also create seven directories
# (Desktop, Templates, Public, ...) this setup never uses.
#
# The literal $HOME in the value is deliberate — that's the format xdg expects,
# and it keeps the file portable across users.
USER_DIRS="$CONFIG_HOME/user-dirs.dirs"

setup_user_dirs() {
  if [[ -f "$USER_DIRS" ]]; then
    ok "user-dirs.dirs already present"
    return 0
  fi
  info "Declaring XDG_DOWNLOAD_DIR -> ~/Downloads"
  mkdir -p "$HOME/Downloads" "$CONFIG_HOME"
  printf 'XDG_DOWNLOAD_DIR="$HOME/Downloads"\n' >"$USER_DIRS"
  ok "user-dirs.dirs written"
}

# --- 11. ssh key ---------------------------------------------------------------
# Generates this machine's git identity if it doesn't have one. Deliberately
# does NOT upload it: that needs either a browser or a token carrying
# admin:public_key, and a provisioner that silently registers push credentials
# is worse than one that hands you a two-minute task. Keys are per-machine —
# never copy id_ed25519 between boxes, generate a fresh one and add it too.
SSH_KEY="$HOME/.ssh/id_ed25519"

install_ssh_key() {
  if [[ -f "$SSH_KEY" ]]; then
    ok "ssh key already present ($SSH_KEY)"
    return 0
  fi

  info "Generating an ed25519 ssh key for this machine"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  # -C tags the key with user@host so GitHub's key list says which box it is.
  ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)" -f "$SSH_KEY" ||
    {
      warn "ssh-keygen failed — skipping"
      return 0
    }
  ok "ssh key created"
}

# Printed at the end of a run rather than mid-stream, so it isn't scrolled away
# by the LazyVim install. Silent when the key is already known to GitHub.
ssh_key_hint() {
  [[ -f "$SSH_KEY.pub" ]] || return 0
  # Match on the greeting, not the exit code: GitHub answers a *successful*
  # auth with status 1 (it provides no shell), so piping into grep under
  # pipefail would report every working key as unregistered.
  local reply
  reply="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=5 -T git@github.com 2>&1 || true)"
  if [[ "$reply" == *"successfully authenticated"* ]]; then
    ok "ssh key is registered with GitHub"
    return 0
  fi
  echo
  warn "This machine's ssh key is not registered with GitHub yet. Add it at"
  warn "  https://github.com/settings/ssh/new"
  echo
  cat "$SSH_KEY.pub"
}

# --- audit mode: ./setup.sh --audit ------------------------------------------
# Answers "is this box still minimal?" without installing anything:
#   1. explicit packages on the box that the repo doesn't know about (drift —
#      hardware packages are EXPECTED here, that's the per-box set)
#   2. packages in the lists but missing from the box
#   3. orphaned dependencies nothing requires anymore
audit_packages() {
  local all_lists
  all_lists=$(read_pkg_list "$REPO_DIR/packages/pacman.txt" | sort -u)

  info "Explicit REPO packages not in packages/*.txt (drift — hardware is expected here):"
  comm -23 <(pacman -Qqen | sort) <(printf '%s\n' "$all_lists") | sed 's/^/    /'

  info "Foreign (AUR) packages not in aur.txt:"
  # yay itself and -debug artifacts are expected foreigners — filter the noise.
  # `|| true`: grep exits 1 when there is no drift, and pipefail would then
  # abort the whole audit, silently swallowing every section below this one.
  comm -23 <(pacman -Qqem | sort) <(read_pkg_list "$REPO_DIR/packages/aur.txt" | sort -u) |
    grep -vE '^(yay|yay-bin)$|-debug$' | sed 's/^/    /' || true

  info "Listed in the repo but NOT installed on this box:"
  # -Qq (everything installed), NOT -Qqe: a listed package that something else
  # pulled in as a dependency is present, and reporting it as missing is a lie.
  # Each comm input must also be ONE globally sorted stream, not two sorted
  # lists concatenated — that's what tripped "comm: file is not in sorted order".
  comm -13 <(pacman -Qq | sort -u) \
    <({
      printf '%s\n' "$all_lists"
      read_pkg_list "$REPO_DIR/packages/aur.txt"
    } | sort -u) | sed 's/^/    /'

  info "Orphaned dependencies (remove with: sudo pacman -Rns \$(pacman -Qdtq)):"
  pacman -Qdtq 2>/dev/null | sed 's/^/    /' || ok "none"
}

# --- main --------------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage: ./setup.sh [MODE]

  (no args)     full provision: packages, yay, services, dotfiles, LazyVim
  --link-only   only re-link dotfiles and config/ — no packages, no updates.
                Use after moving files around in the repo.
  --audit       report package drift against packages/*.txt; installs nothing
  --help        this text
EOF
}

main() {
  case "${1:-}" in
  --help | -h)
    usage
    exit 0
    ;;
  --audit)
    command -v pacman >/dev/null || die "pacman not found"
    audit_packages
    exit 0
    ;;
  --link-only)
    link_configs
    ok "Links refreshed."
    [[ -d "$BACKUP_DIR" ]] && warn "Replaced configs were backed up to $BACKUP_DIR" || true
    exit 0
    ;;
  "") ;;
  *) die "unknown option: $1 (try --help)" ;;
  esac

  preflight
  install_base
  install_pacman_packages
  install_yay
  install_aur_packages
  enable_services
  install_oh_my_zsh
  install_hypr       # before link_configs: wezterm.lua reads the theme tree
  install_sddm_theme # after install_hypr: runs the hypr repo's sddm-apply.sh
  install_system_files
  setup_user_dirs
  link_configs
  install_ssh_key # before lazyvim: plugin fetches are the slow part
  install_lazyvim # after link_configs: needs ~/.config/nvim to exist

  echo
  ok "Provisioning complete."
  # `|| true`: without it, set -e exits here on a re-run that backed nothing up,
  # skipping the hint below and returning non-zero from a perfectly good run.
  [[ -d "$BACKUP_DIR" ]] && warn "Replaced configs were backed up to $BACKUP_DIR" || true
  echo "Start a new shell, then apply the desktop theme with:"
  echo "  ~/.config/hypr/scripts/theme-apply.sh"
  ssh_key_hint
}

main "$@"
