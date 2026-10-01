# shellcheck shell=bash

if [[ -t 1 ]]; then
  RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; BLU=$'\033[34m'; DIM=$'\033[2m'; RST=$'\033[0m'
else
  RED=""; GRN=""; YLW=""; BLU=""; DIM=""; RST=""
fi

log()  { printf '%s==>%s %s\n' "$BLU" "$RST" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '%s warn%s %s\n' "$YLW" "$RST" "$*" >&2; }
die()  { printf '%sfail%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }
skip() { printf '%s skip%s %s\n' "$DIM" "$RST" "$*"; }

DRY_RUN="${DRY_RUN:-false}"
PRUNE="${PRUNE:-false}"

run() {
  if [[ $DRY_RUN == true ]]; then
    printf '%s would run:%s %s\n' "$DIM" "$RST" "$*"
  else
    "$@" || die "command failed: $*"
  fi
}

as_user() {
  if [[ $DRY_RUN == true ]]; then
    printf '%s would run (as %s):%s %s\n' "$DIM" "$TARGET_USER" "$RST" "$*"
    return 0
  fi
  if [[ $(id -un) == "$TARGET_USER" ]]; then
    "$@"
  else
    sudo -u "$TARGET_USER" -H "$@"
  fi
}

confirm() {
  [[ ${ASSUME_YES:-false} == true ]] && return 0
  local reply
  printf '%s%s [y/N] %s' "$YLW" "$1" "$RST" >&2
  { IFS= read -r reply </dev/tty; } 2>/dev/null || return 1
  [[ $reply == [yY]* ]]
}

pkg_installed() { pacman -Qq "$1" &>/dev/null; }

pkg_install() {
  local missing=() p
  for p in "$@"; do
    pkg_installed "$p" || missing+=("$p")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    skip "already installed: $*"
    return 0
  fi
  log "pacman: installing ${missing[*]}"
  run sudo pacman -S --needed --noconfirm "${missing[@]}"
}

aur_install() {
  local missing=() p
  for p in "$@"; do
    pkg_installed "$p" || missing+=("$p")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    skip "already installed (AUR): $*"
    return 0
  fi
  command -v yay >/dev/null || die "yay is not installed; run module 00-base first"
  log "yay: installing ${missing[*]}"
  as_user yay -S --needed --noconfirm "${missing[@]}" \
    || die "yay failed for: ${missing[*]}"
}

unit_exists() {
  [[ -n $(systemctl list-unit-files --no-legend "$1" 2>/dev/null) ]]
}

svc_enable() {
  local unit
  for unit in "$@"; do
    if ! unit_exists "$unit"; then
      warn "$unit does not exist; not enabling it"
    elif systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      skip "$unit already enabled"
    else
      run sudo systemctl enable "$unit"
    fi
  done
}

svc_disable() {
  local unit
  for unit in "$@"; do
    if ! unit_exists "$unit"; then
      skip "$unit does not exist"
    elif systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      run sudo systemctl disable --now "$unit"
    else
      skip "$unit not enabled"
    fi
  done
}

write_file() {
  local path=$1 mode=${2:-644} content
  content=$(cat)
  if [[ -f $path ]] && [[ "$(cat "$path")" == "$content" ]]; then
    skip "$path unchanged"
    return 0
  fi
  if [[ $DRY_RUN == true ]]; then
    printf '%s would write:%s %s\n' "$DIM" "$RST" "$path"
    return 0
  fi
  sudo mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" | sudo tee "$path" >/dev/null
  sudo chmod "$mode" "$path"
  ok "wrote $path"
}

write_user_file() {
  local path=$1 mode=${2:-644} content
  content=$(cat)
  if [[ -L $path ]]; then
    if [[ $DRY_RUN == true ]]; then
      printf '%s would replace symlink:%s %s\n' "$DIM" "$RST" "$path"
    else
      rm -f "$path"
      warn "replaced a symlink at $path with a generated file"
    fi
  elif [[ -f $path ]] && [[ "$(cat "$path")" == "$content" ]]; then
    skip "$path unchanged"
    return 0
  fi
  if [[ $DRY_RUN == true ]]; then
    printf '%s would write:%s %s\n' "$DIM" "$RST" "$path"
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  chmod "$mode" "$path"
  ok "wrote $path"
}

append_line() {
  local file=$1 line=$2
  if grep -qxF "$line" "$file" 2>/dev/null; then
    skip "$file already has: $line"
    return 0
  fi
  if [[ $DRY_RUN == true ]]; then
    printf '%s would append to %s:%s %s\n' "$DIM" "$file" "$RST" "$line"
    return 0
  fi
  printf '%s\n' "$line" | sudo tee -a "$file" >/dev/null
  ok "$file += $line"
}

regen_grub() {
  log "Regenerating GRUB configuration"
  if command -v update-grub >/dev/null; then
    run sudo update-grub
  else
    run sudo grub-mkconfig -o /boot/grub/grub.cfg
  fi
}

grub_value() {
  local key=$1 line
  line=$(grep -E "^${key}=" /etc/default/grub 2>/dev/null | head -1) || return 1
  [[ -z $line ]] && return 1
  line=${line#"${key}="}
  if [[ ${#line} -ge 2 && ${line:0:1} == '"' && ${line: -1} == '"' ]]; then
    line=${line:1:${#line}-2}
  elif [[ ${#line} -ge 2 && ${line:0:1} == "'" && ${line: -1} == "'" ]]; then
    line=${line:1:${#line}-2}
  fi
  printf '%s' "$line"
}

grub_write() {
  local key=$1 value=$2 esc
  esc=$(printf '%s' "$value" | sed -e 's/[&|\\"]/\\&/g')
  if grep -qE "^#?${key}=" /etc/default/grub; then
    run sudo sed -i -E "s|^#?${key}=.*|${key}=\"${esc}\"|" /etc/default/grub
  else
    append_line /etc/default/grub "${key}=\"${value}\""
  fi
}

set_grub_var() {
  local key=$1 value=$2 current
  current=$(grub_value "$key" || true)
  if [[ "$current" == "$value" ]]; then
    skip "/etc/default/grub: $key already $value"
    return 1
  fi
  grub_write "$key" "$value"
  ok "/etc/default/grub: $key=$value"
  return 0
}

read_pkg_list() {
  sed -E 's/#.*//' "$1" | tr -s '[:space:]' '\n' | grep -v '^$'
}

assert_hydrated() {
  local f="$ROOT/config.local.sh" left
  [[ -f $f ]] || die "config.local.sh is missing. Run: ./bin/redact hydrate"
  left=$(grep -ohE '@@[A-Z][A-Z0-9_]*@@' "$f" 2>/dev/null | sort -u || true)
  [[ -z $left ]] && return 0
  die "config.local.sh still holds placeholder tokens:
$(printf '%s\n' "$left" | sed 's/^/       /')
     Fill them in from secrets.age:  ./bin/redact hydrate"
}
