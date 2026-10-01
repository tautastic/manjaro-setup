#!/usr/bin/env bash
set -euo pipefail
ROOT=${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"

current_shell=$(getent passwd "$TARGET_USER" | cut -d: -f7)
if [[ $current_shell == /usr/bin/zsh || $current_shell == /bin/zsh ]]; then
  skip "login shell is already $current_shell"
else
  log "Setting the login shell to zsh"
  run sudo chsh -s /usr/bin/zsh "$TARGET_USER"
fi

if [[ -r /usr/share/zinit/zinit.zsh ]]; then
  ok "zinit present at /usr/share/zinit/zinit.zsh"
else
  warn "zinit not found at /usr/share/zinit/zinit.zsh -- check the AUR zinit package"
fi

ok "Open a new terminal; zinit will fetch powerlevel10k and zsh-vi-mode on first run."

exit 0
