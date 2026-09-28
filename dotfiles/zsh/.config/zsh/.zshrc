typeset -U path cdpath fpath manpath

HELPDIR="/usr/share/zsh/$ZSH_VERSION/help"

fpath=(${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions $fpath)
autoload -U compinit && compinit

HISTSIZE="1000"
SAVEHIST="1000"
HISTFILE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/history"
mkdir -p "$(dirname "$HISTFILE")"

set_opts=(
  HIST_FCNTL_LOCK HIST_IGNORE_SPACE SHARE_HISTORY autocd NO_APPEND_HISTORY
  NO_EXTENDED_HISTORY NO_HIST_EXPIRE_DUPS_FIRST NO_HIST_FIND_NO_DUPS
  NO_HIST_IGNORE_ALL_DUPS NO_HIST_IGNORE_DUPS NO_HIST_SAVE_NO_DUPS
)
for opt in "${set_opts[@]}"; do
  setopt "$opt"
done
unset opt set_opts

if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

autoload -U colors && colors
if [[ -o interactive ]] && [[ -t 0 ]]; then
  stty stop undef
fi
setopt interactive_comments

export PATH="$PATH:$HOME/.local/bin:$GOPATH/bin:$HOME/.local/share/pnpm/bin"

tmp() {
  local dir
  dir=$(mktemp -d) || return 1
  cd "$dir" || return 1
  if [ $# -ge 1 ]; then
      $EDITOR "$1"
  fi
}

gencomp() {
  if (( $# < 1 )); then
    print -u2 "usage: gencomp <command> [name]"
    return 2
  fi
  local bin=$1 name=${2:-${1:t}} tmpfile
  local dir=${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions
  mkdir -p $dir || return 1
  tmpfile=$(mktemp) || return 1
  if ! $bin completion zsh >| $tmpfile || [[ ! -s $tmpfile ]]; then
    command rm -f $tmpfile
    print -u2 "gencomp: $bin produced no zsh completion script"
    return 1
  fi
  command mv $tmpfile $dir/_$name || return 1
  chmod 644 $dir/_$name
  command rm -f ${ZDOTDIR:-$HOME}/.zcompdump
  print "gencomp: wrote $dir/_$name (run 'exec zsh')"
}

source /usr/share/zinit/zinit.zsh
zinit ice depth=1
zinit light romkatv/powerlevel10k
zinit load jeffreytse/zsh-vi-mode
[[ -f "$HOME/.config/zsh/.p10k.zsh" ]] && source "$HOME/.config/zsh/.p10k.zsh"

function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXX")"
  command yazi "$@" --cwd-file="$tmp"
  if cwd="$(<"$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

if test -n "$KITTY_INSTALLATION_DIR"; then
  export KITTY_SHELL_INTEGRATION="no-rc"
  autoload -Uz -- "$KITTY_INSTALLATION_DIR"/shell-integration/zsh/kitty-integration
  kitty-integration
  unfunction kitty-integration
fi

alias -- cp='cp -iv'
alias -- cpr='rsync -HAXhaxvPS --numeric-ids --stats'
alias -- diff='diff --color=auto'
alias -- ffmpeg='ffmpeg -hide_banner'
alias -- g=git
alias -- grep='grep --color=auto'
alias -- ip='ip -color=auto'
alias -- ls='eza -lAh --color=auto --git --header --group --group-directories-first'
alias -- mkd='mkdir -pv'
alias -- mv='mv -iv'
alias -- rm='rm -vI'
alias -- v='$EDITOR'
alias -- yz=yazi

alias -- up='sudo pacman -Syu && yay -Syua'
alias -- mj-make='$HOME/.config/manjaro-setup/install.sh'

source "$HOME/.config/zsh/bookmarks.zsh"

[[ -f source /usr/share/nvm/init-nvm.sh ]] && source source /usr/share/nvm/init-nvm.sh

command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
[[ -f /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -f /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh
bindkey -s '^f' '^ucd "$(dirname "$(fzf)")"\n'

source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main)

source "$HOME/.config/zsh/git-identity.zsh"
