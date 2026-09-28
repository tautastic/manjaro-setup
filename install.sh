#!/usr/bin/env bash
# Set up a minimal GNOME desktop on Manjaro.
#
#   ./install.sh                     run every module, in order
#   ./install.sh --dry-run           show what would change, touch nothing
#   ./install.sh --list              list the modules
#   ./install.sh --only 20-gnome-prune [--only 60-dconf ...]
#   ./install.sh --skip 10-nvidia
#
# Every module is idempotent: re-running a finished install makes no changes.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT

source "$ROOT/lib/common.sh"
source "$ROOT/config.sh"

ONLY=(); SKIP=()

usage() { sed -n '2,11p' "$0" | sed 's/^# \?//'; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    --only)    ONLY+=("$2"); shift 2 ;;
    --skip)    SKIP+=("$2"); shift 2 ;;
    --list)    basename -a "$ROOT"/modules/*.sh | sed 's/\.sh$//' ; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *)         die "unknown option: $1 (try --help)" ;;
  esac
done
export DRY_RUN

[[ -f /etc/manjaro-release ]] || warn "/etc/manjaro-release not found -- this targets Manjaro"
[[ $EUID -eq 0 ]] && die "run this as your normal user; it calls sudo where it needs to"
[[ -n ${TARGET_HOME:-} && -d $TARGET_HOME ]] || die "could not resolve the home directory of $TARGET_USER"

# Without config.local.sh, config.sh's placeholder identities would be installed
# as if they were real -- silently giving you a git setup for "gituser1".
if [[ ! -f $ROOT/config.local.sh ]]; then
  warn "config.local.sh is missing, so the placeholder identities in config.sh would be used."
  warn "  Generate it first:  ./bin/redact hydrate"
  warn "  (needs age: sudo pacman -S age)"
  die "refusing to install with placeholder values"
fi

selected() {
  local name=$1 s
  for s in "${SKIP[@]:-}"; do [[ $name == "$s" ]] && return 1; done
  [[ ${#ONLY[@]} -eq 0 ]] && return 0
  for s in "${ONLY[@]}"; do [[ $name == "$s" ]] && return 0; done
  return 1
}

if [[ $DRY_RUN == true ]]; then
  printf '\n%s*** DRY RUN -- nothing will be changed ***%s\n' "$YLW" "$RST"
fi

printf '\n%s%s%s  ->  user %s, home %s\n\n' "$BLU" "manjaro-setup" "$RST" "$TARGET_USER" "$TARGET_HOME"

log "Asking for sudo up front"
[[ $DRY_RUN == true ]] || sudo -v || die "sudo is required"

ran=0; failed=()
for mod in "$ROOT"/modules/*.sh; do
  name=$(basename "$mod" .sh)
  selected "$name" || { skip "module $name"; continue; }

  printf '\n%s------ %s %s%s\n' "$BLU" "$name" "$(printf '%.0s-' $(seq 1 $((50 - ${#name}))))" "$RST"
  # shellcheck source=/dev/null
  ( source "$mod" )
  status=$?
  if [[ $status -ne 0 ]]; then
    failed+=("$name")
    printf '%smodule %s failed (exit %d)%s\n' "$RED" "$name" "$status" "$RST" >&2
    break
  fi
  ran=$((ran + 1))
done

printf '\n'
if [[ ${#failed[@]} -gt 0 ]]; then
  die "stopped after ${failed[*]} -- fix the cause and re-run (earlier modules are no-ops)"
fi

ok "$ran module(s) completed"
if [[ $DRY_RUN != true ]]; then
  cat <<'NEXT'

Next steps
  1. Reboot. The NVIDIA modules, the GRUB menu and the login shell all need it.
  2. At the GRUB menu, check that "Windows Boot Manager" is listed.
  3. Log in, open a terminal: zinit fetches powerlevel10k and zsh-vi-mode once.
  4. Copy your SSH keys into ~/.ssh if you have not yet, then run `gid list`.
NEXT
fi
