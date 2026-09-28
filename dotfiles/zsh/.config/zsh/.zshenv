# Only source this once
if [[ -z "${__ZSH_SESS_VARS_SOURCED-}" ]]; then
  export __ZSH_SESS_VARS_SOURCED=1
  export BROWSER="librewolf"
  export EDITOR="vis"
  export VISUAL="vis"
  export GOPATH="$HOME/.local/go"
  export LOCAL_BIN="$HOME/.local/bin"
  export XDG_CACHE_HOME="$HOME/.cache"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_DATA_HOME="$HOME/.local/share"
fi

export ZDOTDIR="$HOME/.config/zsh"
