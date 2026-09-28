#!/usr/bin/env bash
# Files and settings Manjaro leaves behind after its packages are gone:
# shell rc files, system-wide dconf defaults, and autostart entries.

stamp=$(date +%Y%m%d-%H%M%S)

backup_away() {
  local path=$1
  [[ -e $path ]] || { skip "$path absent"; return 0; }
  [[ -L $path ]] && { skip "$path is a symlink we manage"; return 0; }
  # Never back up a backup: the autostart glob below matches the .bak files
  # this function creates, which on a re-run produced .bak.<ts>.bak.<ts>.
  [[ $path == *.bak.[0-9]* ]] && return 0
  warn "moving $path -> $path.bak.$stamp"
  if [[ -w $(dirname "$path") ]]; then
    run mv "$path" "$path.bak.$stamp"
  else
    run sudo mv "$path" "$path.bak.$stamp"
  fi
}

### Shell rc files.
# zsh reads ~/.zshenv, which points ZDOTDIR at ~/.config/zsh, so a leftover
# ~/.zshrc is inert -- but it is confusing, and ~/.bashrc still runs for
# non-login bash. Move both aside rather than deleting.
log "Clearing Manjaro's shell configs"
for f in .zshrc .zprofile .bashrc .bash_profile .bash_logout; do
  target="$TARGET_HOME/$f"
  [[ -e $target ]] || continue
  if grep -qi 'manjaro\|grml' "$target" 2>/dev/null; then
    backup_away "$target"
  else
    skip "$target is not Manjaro's"
  fi
done

# /etc/skel seeds every future user with the same thing.
for f in /etc/skel/.zshrc /etc/skel/.bashrc /etc/skel/.bash_profile; do
  [[ -e $f ]] && grep -qi 'manjaro\|grml' "$f" 2>/dev/null && backup_away "$f"
done

### System-wide dconf defaults.
# Manjaro ships /etc/dconf/db/local.d entries that enable dash-to-dock, arcmenu
# and its own layout. Those are system defaults, so they win over an unset user
# key -- our dconf/gnome.ini sets user keys, but anything it does not mention
# would still come from here.
log "Clearing Manjaro's system-wide dconf defaults"
dconf_changed=false
if [[ -d /etc/dconf/db/local.d ]]; then
  while read -r f; do
    grep -qil 'manjaro\|dash-to-dock\|arcmenu\|dash-to-panel' "$f" 2>/dev/null || continue
    backup_away "$f"
    dconf_changed=true
  done < <(find /etc/dconf/db/local.d -maxdepth 1 -type f 2>/dev/null)
fi
if [[ $dconf_changed == true ]]; then
  run sudo dconf update
else
  skip "no Manjaro dconf defaults found"
fi

### GSettings schema overrides.
log "Clearing Manjaro's gsettings overrides"
schema_changed=false
while read -r f; do
  backup_away "$f"
  schema_changed=true
done < <(find /usr/share/glib-2.0/schemas -maxdepth 1 -iname '*manjaro*.gschema.override' 2>/dev/null)
if [[ $schema_changed == true ]]; then
  run sudo glib-compile-schemas /usr/share/glib-2.0/schemas
else
  skip "no Manjaro schema overrides found"
fi

### Autostart entries (manjaro-hello, matray, the settings-manager notifier).
log "Clearing Manjaro autostart entries"
autostart_found=false
for dir in /etc/xdg/autostart "$TARGET_HOME/.config/autostart"; do
  [[ -d $dir ]] || continue
  while read -r f; do
    backup_away "$f"
    autostart_found=true
  done < <(find "$dir" -maxdepth 1 -type f -name '*.desktop' \
             \( -iname '*manjaro*' -o -iname '*matray*' -o -iname '*pamac*' \) 2>/dev/null)
done
[[ $autostart_found == false ]] && skip "no Manjaro autostart entries found"

### Leftover GNOME Shell extensions from Manjaro's packages.
if [[ -d /usr/share/gnome-shell/extensions ]]; then
  remaining=$(find /usr/share/gnome-shell/extensions -maxdepth 1 -mindepth 1 2>/dev/null | wc -l)
  if [[ $remaining -gt 0 ]]; then
    warn "$remaining extension(s) still in /usr/share/gnome-shell/extensions:"
    find /usr/share/gnome-shell/extensions -maxdepth 1 -mindepth 1 -printf '       %f\n' 2>/dev/null
    warn "  dconf/gnome.ini sets enabled-extensions to empty, so none of them load."
    warn "  Find their owners with: pacman -Qo /usr/share/gnome-shell/extensions/<name>"
  fi
fi
