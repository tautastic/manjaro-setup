#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT

# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"

usage() {
  cat <<'USAGE'
Set up a minimal GNOME desktop on Manjaro.

  ./install.sh                     run every module, in order
  ./install.sh --dry-run           show what would change, touch nothing
  ./install.sh --list              list the modules
  ./install.sh --only 60-dconf     run one module (repeatable)
  ./install.sh --skip 10-nvidia    run everything but one (repeatable)
  ./install.sh --prune             also remove packages the manifest does not list
  ./install.sh --upgrade           pacman -Syu first
  ./install.sh --yes               do not ask before removing packages

Modules are ordinary scripts: ./modules/60-dconf.sh works on its own too.
Re-running a finished install changes nothing.
USAGE
}

modules() { basename -a "$ROOT"/modules/*.sh | sed 's/\.sh$//' | sort; }

ONLY=(); SKIP=(); UPGRADE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    --prune)   PRUNE=true; shift ;;
    --upgrade) UPGRADE=true; shift ;;
    --yes)     ASSUME_YES=true; shift ;;
    --only)    ONLY+=("${2:?--only needs a module name}"); shift 2 ;;
    --skip)    SKIP+=("${2:?--skip needs a module name}"); shift 2 ;;
    --list)    modules; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *)         die "unknown option: $1 (try --help)" ;;
  esac
done
export DRY_RUN PRUNE ASSUME_YES

known=$(modules)
for name in ${ONLY[@]+"${ONLY[@]}"} ${SKIP[@]+"${SKIP[@]}"}; do
  grep -qxF "$name" <<< "$known" \
    || die "no such module: $name
$(printf '%s\n' "$known" | sed 's/^/     /')"
done

[[ -f /etc/manjaro-release ]] || warn "/etc/manjaro-release not found -- this targets Manjaro"
[[ $EUID -eq 0 ]] && die "run this as your normal user; it calls sudo where it needs to"

# shellcheck source=/dev/null
source "$ROOT/config.sh"
[[ -n ${TARGET_HOME:-} && -d $TARGET_HOME ]] || die "could not resolve the home directory of $TARGET_USER"
assert_hydrated
assert_user

selected() {
  local name=$1 s
  for s in ${SKIP[@]+"${SKIP[@]}"}; do [[ $name == "$s" ]] && return 1; done
  [[ ${#ONLY[@]} -eq 0 ]] && return 0
  for s in "${ONLY[@]}"; do [[ $name == "$s" ]] && return 0; done
  return 1
}

[[ $DRY_RUN == true ]] && printf '\n%s*** DRY RUN -- nothing will be changed ***%s\n' "$YLW" "$RST"
printf '\n%smanjaro-setup%s  ->  user %s, home %s\n\n' "$BLU" "$RST" "$TARGET_USER" "$TARGET_HOME"

log "Asking for sudo up front"
[[ $DRY_RUN == true ]] || sudo -v || die "sudo is required"

if [[ $UPGRADE == true ]]; then
  log "Upgrading the system"
  run sudo pacman -Syu --noconfirm
fi

ran=0; failed=()
for mod in "$ROOT"/modules/*.sh; do
  name=$(basename "$mod" .sh)
  selected "$name" || { skip "module $name"; continue; }

  rule=$(printf '%*s' $((50 - ${#name})) ''); rule=${rule// /-}
  printf '\n%s------ %s %s%s\n' "$BLU" "$name" "$rule" "$RST"

  bash "$mod"
  status=$?
  if [[ $status -ne 0 ]]; then
    failed+=("$name")
    printf '%smodule %s failed (exit %d)%s\n' "$RED" "$name" "$status" "$RST" >&2
    break
  fi
  ran=$((ran + 1))
done

printf '\n'
[[ ${#failed[@]} -gt 0 ]] && die "stopped at ${failed[*]} -- fix the cause and re-run; earlier modules are no-ops"

ok "$ran module(s) completed"
if [[ $DRY_RUN != true ]]; then
  cat <<'NEXT'

Next steps
  1. Reboot. The NVIDIA modules, the GRUB menu and the login shell all need it.
  2. At the GRUB menu, check that "Windows Boot Manager" is listed.
  3. Copy your SSH keys into ~/.ssh if you have not yet, then run `gid list`.
NEXT
fi
