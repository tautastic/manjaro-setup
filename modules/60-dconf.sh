#!/usr/bin/env bash
# Load the GNOME settings this repo declares.

if [[ $DRY_RUN == true ]]; then
  skip "dry run -- would load $ROOT/dconf/gnome.ini"
  return 0 2>/dev/null || exit 0
fi

if ! command -v dconf >/dev/null; then
  die "dconf not found -- run module 25-gnome-core first"
fi

backup="$TARGET_HOME/.cache/manjaro-setup/dconf-backup-$(date +%Y%m%d-%H%M%S).ini"
mkdir -p "$(dirname "$backup")"
log "Backing up the current dconf database to $backup"
as_user dconf dump / > "$backup" 2>/dev/null || warn "could not dump dconf (no session bus?)"

log "Loading $ROOT/dconf/gnome.ini"
if as_user dconf load / < "$ROOT/dconf/gnome.ini"; then
  ok "dconf settings applied"
else
  die "dconf load failed -- run this module from inside a graphical session"
fi
