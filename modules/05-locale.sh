#!/usr/bin/env bash
# Timezone, locales, console and X/XWayland keyboard, hostname.

log "Setting timezone to $TIMEZONE"
if [[ "$(timedatectl show -p Timezone --value)" == "$TIMEZONE" ]]; then
  skip "timezone already $TIMEZONE"
else
  run sudo timedatectl set-timezone "$TIMEZONE"
fi

log "Generating locales"
locale_changed=false
for loc in "${LOCALES_TO_GENERATE[@]}"; do
  if grep -qxF "$loc" /etc/locale.gen; then
    skip "locale.gen already has $loc"
  elif grep -qxF "#$loc" /etc/locale.gen; then
    run sudo sed -i "s/^#$loc\$/$loc/" /etc/locale.gen
    locale_changed=true
  else
    run sudo sh -c "printf '%s\n' '$loc' >> /etc/locale.gen"
    locale_changed=true
  fi
done
[[ $locale_changed == true ]] && run sudo locale-gen

# LANG, plus the nine LC_* categories that take the regional locale.
{
  printf 'LANG=%s\n' "$LOCALE_LANG"
  for key in "${LOCALE_REGIONAL_KEYS[@]}"; do
    printf '%s=%s\n' "$key" "$LOCALE_REGIONAL"
  done
} | write_file /etc/locale.conf 644

printf 'KEYMAP=%s\n' "$CONSOLE_KEYMAP" | write_file /etc/vconsole.conf 644

# The Wayland session reads dconf instead, but this covers XWayland, the GDM
# greeter and the virtual consoles.
cat <<KB | write_file /etc/X11/xorg.conf.d/00-keyboard.conf 644
# Written by manjaro-setup (05-locale.sh). Do not edit by hand.
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbModel" "$XKB_MODEL"
        Option "XkbLayout" "$XKB_LAYOUT"
        Option "XkbVariant" "$XKB_VARIANT"
        Option "XkbOptions" "$XKB_OPTIONS"
EndSection
KB

if [[ "$(cat /etc/hostname 2>/dev/null)" == "$HOSTNAME_NEW" ]]; then
  skip "hostname already $HOSTNAME_NEW"
else
  log "Setting hostname to $HOSTNAME_NEW"
  run sudo hostnamectl set-hostname "$HOSTNAME_NEW"
fi
