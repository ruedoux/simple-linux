#!/bin/bash

# Fix environment when su is used without '-' (preserves calling user's HOME)
_CURRENT_USER="$(id -un 2>/dev/null)"
_CURRENT_HOME="$(getent passwd "$_CURRENT_USER" 2>/dev/null | cut -d: -f6)"
if [ -n "$_CURRENT_HOME" ] && [ "$HOME" != "$_CURRENT_HOME" ]; then
    export HOME="$_CURRENT_HOME"
    cd "$HOME" 2>/dev/null || true
    # Clear inherited XDG vars so they default to $HOME-based paths
    unset XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME 2>/dev/null
fi
unset _CURRENT_USER _CURRENT_HOME

[[ $- != *i* ]] && return
PS1='[\u@\h \W]\$ '

if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi

if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# COLORS
case "$TERM" in
  xterm-color|*-256color) color_prompt=yes;;
esac

force_color_prompt=yes
if [ -n "$force_color_prompt" ]; then
  if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    color_prompt=yes
  else
    color_prompt=
  fi
fi

if [ "$color_prompt" = yes ]; then
  PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w \$\[\033[00m\] '
else
  PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi

case "$TERM" in
xterm*|rxvt*)
  PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
  ;;
*)
  ;;
esac

if [ -x /usr/bin/dircolors ]; then
  test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi

unset color_prompt force_color_prompt

# EXPORTS
export PATH=$PATH:$HOME/.local/bin
export HISTFILESIZE=10000
export HISTSIZE=500
export HISTTIMEFORMAT="%F %T "
export HISTCONTROL=erasedups:ignoredups:ignorespace
shopt -s checkwinsize
shopt -s histappend
PROMPT_COMMAND='history -a'

bind "set completion-ignore-case on"
bind "set show-all-if-ambiguous On"
bind "set bell-style none"

export CLICOLOR=1
export LS_COLORS='no=00:fi=00:di=00;34:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.avi=01;35:*.fli=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.ogg=01;35:*.mp3=01;35:*.wav=01;35:*.xml=00;31:'
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# ALIASES
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias ll='ls -Flah'
cd() { builtin cd "$@" && ls -a; }
alias cp='cp -i'
alias mv='mv -i'
alias cls='clear'
alias home='cd ~'
alias cd..='cd ..'
alias ..='cd ..'

# FUNCTIONS
extract() {
	for archive in "$@"; do
		if [ -f "$archive" ]; then
			case $archive in
			*.tar.bz2) tar xvjf $archive ;;
			*.tar.gz) tar xvzf $archive ;;
			*.bz2) bunzip2 $archive ;;
			*.rar) rar x $archive ;;
			*.gz) gunzip $archive ;;
			*.tar) tar xvf $archive ;;
			*.tbz2) tar xvjf $archive ;;
			*.tgz) tar xvzf $archive ;;
			*.zip) unzip $archive ;;
			*.Z) uncompress $archive ;;
			*.7z) 7z x $archive ;;
			*) echo "don't know how to extract '$archive'..." ;;
			esac
		else
			echo "'$archive' is not a valid file!"
		fi
	done
}

y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	command rm -f -- "$tmp"
}

# ENV
export DOTNET_CLI_TELEMETRY_OPTOUT=1 # For all the dotnet users :)
export SL_ROOT_PATH=$HOME/.config/simple-linux
export BASHRC_EXTENSION_PATH=$SL_ROOT_PATH/bashrc-extension.sh
export EDITOR=nvim
export PATH=$PATH:$SL_ROOT_PATH
export PATH=$PATH:$SL_ROOT_PATH/tools
export PATH=$PATH:$HOME/.pyenv/bin

if [ -f $BASHRC_EXTENSION_PATH ]; then
  . $BASHRC_EXTENSION_PATH
else
  echo "extend the .bashrc functionality by creating '${BASHRC_EXTENSION_PATH}' file - DO NOT EDIT ~/.bashrc UPDATE COMMANDS OVERWRITE IT"
fi

if command -v pyenv >/dev/null 2>&1; then
	export PYENV_ROOT="$HOME/.pyenv"
  [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init - bash)"
else
  echo "Please install pyenv in order to easily manage python versions"
fi

if [ -f /usr/bin/fastfetch ]; then
	fastfetch --config "$HOME/.config/fastfetch/config.jsonc"
fi

if command -v oh-my-posh >/dev/null 2>&1; then
	eval "$(oh-my-posh init bash --config $HOME/.config/oh-my-posh/default.json)"
fi

if command -v sl-toolset.sh >/dev/null 2>&1; then
	mkdir -p "$HOME/.config/reminders"

	DAILY_CHECK_FILE="$HOME/.config/reminders/.last-reminder-check"
	TODAY="$(date +%Y-%m-%d)"
	LAST_CHECK="$(cat "$DAILY_CHECK_FILE" 2>/dev/null || true)"

	if [ "$LAST_CHECK" != "$TODAY" ]; then
		sl-toolset.sh notifications remind -f "$HOME/.config/reminders/.reminder-btrfs" -s 2592000 -c "Health check on btrfs"
		sl-toolset.sh notifications remind -f "$HOME/.config/reminders/.reminder-update" -s 604800 -c "Update the system + backup"
		echo "$TODAY" > "$DAILY_CHECK_FILE"
	fi

	sl-toolset.sh notifications list-alerts -d "$HOME/.config/alerts"
fi
