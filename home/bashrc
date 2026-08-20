# ~/.bashrc
case $- in
	*i*) ;;
	*) return;;
esac

# History
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s checkwinsize

# Prompt: user@host:dir$
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$'

# Color
alias ls='ls --color=auto'
alias grep='grep --color=auto'

# ls aliases
alias ll='ls -la'
alias la='ls -A'

# Bash Completion
if ! shopt -oq posix; then
	if [ -f /usr/share/bash-completion/bash_completion ]; then
		. /usr/share/bash-completion/bash_completion
	fi
fi

# User-local bin (Claude Code + user installs)
export PATH="$HOME/.local/bin:$PATH"

# Personal Aliases
alias gs='git status'
alias gl='git lg' #lg is in .gitconfig
alias ..='cd ..'
alias ~='cd ~'
alias vi='nvim'
alias ga.='git add .'
alias ga='git add'
alias gp='git push'
alias gcm='git commit -m'
alias ta='tmux attach'

# Safety Nets
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Convenience
alias c='clear'

# Disable Ctrl-S freeze
stty -ixon

[ -f ~/.bashrc.local ] && source ~/.bashrc.local
