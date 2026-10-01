#!/usr/bin/env bash
set -euo pipefail
ROOT=${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"

INI="$ROOT/dconf/gnome.ini"
[[ -f $INI ]] || die "$INI is missing"

owned_paths() { grep -oE '^\[[^]]+\]' "$INI" | tr -d '[]'; }

if [[ $DRY_RUN == true ]]; then
  skip "dry run -- would reset $(owned_paths | grep -c .) paths and load $INI"
  exit 0
fi

command -v dconf >/dev/null || die "dconf not found -- is gnome installed?"

BACKUPS="$TARGET_HOME/.cache/manjaro-setup"
mkdir -p "$BACKUPS"
backup="$BACKUPS/dconf-backup-$(date +%Y%m%d-%H%M%S).ini"
log "Backing up the current dconf database to $backup"
as_user dconf dump / > "$backup" 2>/dev/null || warn "could not dump dconf (no session bus?)"
find "$BACKUPS" -maxdepth 1 -name 'dconf-backup-*.ini' -printf '%T@ %p\n' 2>/dev/null \
  | sort -rn | tail -n +11 | cut -d' ' -f2- | while IFS= read -r old; do rm -f "$old"; done

log "Resetting the paths $INI owns"
while IFS= read -r p; do
  [[ -z $p ]] && continue
  as_user dconf reset -f "/$p/" || warn "could not reset /$p/"
done < <(owned_paths)

log "Loading $INI"
if as_user dconf load / < "$INI"; then
  ok "dconf settings applied"
else
  die "dconf load failed -- run this module from inside a graphical session"
fi

exit 0
