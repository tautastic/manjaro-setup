# shellcheck shell=bash disable=SC2034

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

TIMEZONE="Europe/Berlin"

LOCALE_LANG="en_US.UTF-8"
LOCALE_REGIONAL="de_DE.UTF-8"
LOCALE_REGIONAL_KEYS=(
  LC_ADDRESS LC_IDENTIFICATION LC_MEASUREMENT LC_MONETARY LC_NAME
  LC_NUMERIC LC_PAPER LC_TELEPHONE LC_TIME
)
LOCALES_TO_GENERATE=("$LOCALE_LANG UTF-8" "$LOCALE_REGIONAL UTF-8")

CONSOLE_KEYMAP="us"
XKB_MODEL="pc105"
XKB_LAYOUT="us,de,ar"
XKB_VARIANT=",,mac"
XKB_OPTIONS="grp:win_space_toggle"

STOW_PACKAGES=(zsh kitty yazi vis zathura librewolf fontconfig xdg qt)

MHWD_VIDEO_CONFIG="video-nvidia"

ENABLE_FIREWALL=false

RTC_LOCAL_TIME=false

_cfg_dir="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"
# shellcheck source=/dev/null
[[ -f "$_cfg_dir/config.local.sh" ]] && source "$_cfg_dir/config.local.sh"
unset _cfg_dir
