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
