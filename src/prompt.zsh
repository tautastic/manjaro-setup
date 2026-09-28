autoload -Uz add-zsh-hook

typeset -g _git_identity_state=

_git_identity_reset() {
  _git_identity_state=
}

_git_identity_compute() {
  emulate -L zsh
  local dir=$PWD email name key want

  while [[ ! -e $dir/.git ]]; do
    if [[ -z $dir ]]; then
      _git_identity_state=-
      return
    fi
    dir=${dir%/*}
  done

  email=$(command git config --get user.email 2>/dev/null)
  name=${_git_identity_name[$email]-}

  if [[ -z $name ]]; then
    _git_identity_state="196 ${email:-no identity}"
    return
  fi

  key=$(command git config --get core.sshCommand 2>/dev/null)
  want=${_git_identity_key[$name]}

  if [[ " $key " == *" -i $want "* ]]; then
    _git_identity_state="${_git_identity_color[$name]} $name"
  else
    _git_identity_state="196 $name ssh?"
  fi
}

prompt_git_identity() {
  [[ -n $_git_identity_state ]] || _git_identity_compute
  [[ $_git_identity_state == - ]] && return
  p10k segment -f ${_git_identity_state%% *} -i $'\uF113' -t "${_git_identity_state#* }"
}

_git_identity_preexec() {
  if [[ ${1[(w)1]} == (g|git|gid|git-identity) ]]; then
    _git_identity_reset
  fi
}

add-zsh-hook chpwd _git_identity_reset
add-zsh-hook preexec _git_identity_preexec

gid() {
  command git-identity "$@"
  local ret=$?
  _git_identity_reset
  return $ret
}

if (( $+functions[compdef] )); then
  compdef _git-identity gid
fi
