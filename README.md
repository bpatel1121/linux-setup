# linux-setup

My Arch Linux dotfiles and packages. Configs for bash, git, tmux and Allacritty and the packages to recreate on a new machine.

## Contents

 - '.bashrc' - shell config
 - '.gitconfig' - git identity + aliases
 - '.tmux.conf' - tmux configs
 - 'alacritty.toml' - terminal config
 - 'packages.txt' - packages installed

## Setup on new machine

Clone the repo:
    
    git clone https://github.com/bpatel1121/linux-setup.git ~/dotfiles

Symlink the configs into place:

    ln -sf ~/dotfiles/.bashrc ~/.bashrc
    ln - sf ~/dotfiles/.gitconfig ~/.gitconfig
    ln -sf ~/dotfiles/.tmux.conf ~/.tmux.conf
    mkdir -p ~/.config/alacritty
    ln -sf ~/dotfiles/alacritty.toml ~/.config/alacritty/alacritty.toml

Apply the bash config:
    
    source ~/.bashrc

## Reinstall packages
    
    sudo pacman -S --needed - < packages.txt

## Pull changes on another machine
    
    cd ~/dotfiles
    git pull

## Secret injection (local-run)

`local-run` injects secrets into a command's environment from a local,
gitignored secrets file. The secrets themselves are NEVER committed.

### Setup on a new machine

The `local-run` script comes with this repo. Make it executable:

    chmod +x ~/dotfiles/local-run

Optionally symlink it onto your PATH:

    ln -sf ~/dotfiles/local-run ~/.local/bin/local-run

Create your local secrets file (NEVER committed — gitignored):

    nvim ~/.local-secrets

Add secrets as KEY=VALUE lines, for example:

    MY_API_KEY=actual-secret-value-here

### Usage

Make a template file with `local://` placeholders referencing your secrets:

    # example.env
    API_KEY=local://MY_API_KEY

Run a command with secrets injected as environment variables:

    local-run example.env -- your-command

The script reads `~/.local-secrets`, swaps the `local://` placeholders for
real values, and runs the command with those as environment variables.
Real secrets exist only in `~/.local-secrets` and at runtime — never in git.
