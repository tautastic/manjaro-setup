# Shared helpers. Sourced by install.sh and every module.

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; BLU=$'\033[34m'; DIM=$'\033[2m'; RST=$'\033[0m'

log()  { printf '%s==>%s %s\n' "$BLU" "$RST" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '%s warn%s %s\n' "$YLW" "$RST" "$*" >&2; }
die()  { printf '%sfail%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }
skip() { printf '%s skip%s %s\n' "$DIM" "$RST" "$*"; }

DRY_RUN="${DRY_RUN:-false}"

run() {
  if [[ $DRY_RUN == true ]]; then
    printf '%s would run:%s %s\n' "$DIM" "$RST" "$*"
  else
    "$@" || die "command failed: $*"
  fi
}

# Run a command as the target user, with their session bus available.
as_user() {
  if [[ $DRY_RUN == true ]]; then
    printf '%s would run (as %s):%s %s\n' "$DIM" "$TARGET_USER" "$RST" "$*"
    return 0
  fi
  if [[ $(id -un) == "$TARGET_USER" ]]; then
    "$@" || die "command failed: $*"
  else
    sudo -u "$TARGET_USER" -H "$@"
  fi
}

need_root() {
  [[ $EUID -eq 0 ]] || die "this step needs root; re-run install.sh with sudo"
}

pkg_installed() { pacman -Qq "$1" &>/dev/null; }

# Install only what is missing, so re-runs are no-ops.
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
  as_user yay -S --needed --noconfirm "${missing[@]}"
}

svc_enable() {
  local unit
  for unit in "$@"; do
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      skip "$unit already enabled"
    else
      run sudo systemctl enable "$unit"
    fi
  done
}

svc_disable() {
  local unit
  for unit in "$@"; do
    if systemctl list-unit-files "$unit" &>/dev/null && systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      run sudo systemctl disable --now "$unit"
    else
      skip "$unit not enabled"
    fi
  done
}

# Write a file only when its contents would change, and report which.
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

# Same, but owned by the target user (no sudo).
write_user_file() {
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
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  chmod "$mode" "$path"
  ok "wrote $path"
}

# Ensure `line` is present in `file` (matched by `key`), adding or replacing it.
ensure_line() {
  local file=$1 key=$2 line=$3
  [[ -f $file ]] || die "$file does not exist"
  if grep -qE "$key" "$file"; then
    grep -qxF "$line" "$file" && { skip "$file already has: $line"; return 0; }
    run sudo sed -i -E "s|$key|$line|" "$file"
  else
    run sudo sh -c "printf '%s\n' '$line' >> '$file'"
  fi
  ok "$file: $line"
}

# Regenerate grub.cfg, whichever wrapper this distro ships.
regen_grub() {
  log "Regenerating GRUB configuration"
  if command -v update-grub >/dev/null; then
    run sudo update-grub
  else
    run sudo grub-mkconfig -o /boot/grub/grub.cfg
  fi
}

# Set KEY="VALUE" in /etc/default/grub, adding it if absent.
set_grub_var() {
  local key=$1 value=$2 current
  current=$(grep -E "^${key}=" /etc/default/grub 2>/dev/null | head -1 | sed -E "s/^${key}=\"?([^\"]*)\"?$/\1/")
  if [[ "$current" == "$value" ]]; then
    skip "/etc/default/grub: $key already $value"
    return 1
  fi
  if grep -qE "^#?${key}=" /etc/default/grub; then
    run sudo sed -i -E "s|^#?${key}=.*|${key}=\"${value}\"|" /etc/default/grub
  else
    run sudo sh -c "printf '%s\n' '${key}=\"${value}\"' >> /etc/default/grub"
  fi
  ok "/etc/default/grub: $key=$value"
  return 0
}

# Strip comments and blank lines from a package manifest.
read_pkg_list() {
  sed -E 's/#.*//' "$1" | tr -s '[:space:]' '\n' | grep -v '^$'
}
