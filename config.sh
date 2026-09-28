# shellcheck shell=bash disable=SC2034  # every setting here is read by install.sh and modules/
# User-tunable settings for the Manjaro setup. Sourced by install.sh.

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

HOSTNAME_NEW="manjaro-pc"
TIMEZONE="Europe/Berlin"

# LANG, then the LC_* categories that get the German locale.
LOCALE_LANG="en_US.UTF-8"
LOCALE_REGIONAL="de_DE.UTF-8"
LOCALE_REGIONAL_KEYS=(
  LC_ADDRESS LC_IDENTIFICATION LC_MEASUREMENT LC_MONETARY LC_NAME
  LC_NUMERIC LC_PAPER LC_TELEPHONE LC_TIME
)
LOCALES_TO_GENERATE=("$LOCALE_LANG UTF-8" "$LOCALE_REGIONAL UTF-8")

# Console + X/XWayland keyboard. The Wayland session uses dconf/gnome.ini instead.
CONSOLE_KEYMAP="us"
XKB_MODEL="pc105"
XKB_LAYOUT="us,de,ar"
XKB_VARIANT=",,mac"
XKB_OPTIONS="grp:win_space_toggle"

# Git identities.
# Format: name|email|ssh key basename (under ~/.ssh)|p10k prompt color
# These are placeholders -- put your real identities in config.local.sh, which
# is gitignored. scripts/check-secrets.sh refuses to let real ones be committed.
GIT_DEFAULT_IDENTITY="gituser1"
GIT_IDENTITIES=(
  "gituser1|00000000+gituser1@users.noreply.github.com|gituser1_id_ed25519|66"
  "gituser2|00000000+gituser2@users.noreply.github.com|gituser2_id_ed25519|178"
)

# Stow packages under dotfiles/ to link into $TARGET_HOME.
# ~/.ssh/config is deliberately NOT managed here -- it names real hosts, and
# this repo is public. Keep it alongside your SSH keys, by hand.
STOW_PACKAGES=(zsh kitty yazi vis zathura git librewolf fontconfig xdg qt)

# Leave the firewall off.
ENABLE_FIREWALL=false

# Dual boot: set true to make Linux keep the RTC in local time like Windows.
# The better fix is to make Windows use UTC -- see modules/15-boot-menu.sh.
RTC_LOCAL_TIME=false

# Real, machine-specific values live here and are never committed. Copy
# config.local.sh.example to config.local.sh and edit it.
# shellcheck source=/dev/null
_cfg_dir="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"
[[ -f "$_cfg_dir/config.local.sh" ]] && source "$_cfg_dir/config.local.sh"
unset _cfg_dir
