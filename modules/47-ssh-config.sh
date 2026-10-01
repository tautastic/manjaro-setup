#!/usr/bin/env bash
set -euo pipefail
ROOT=${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"

[[ -n ${SSH_CONFIG:-} ]] || warn "SSH_CONFIG is empty -- writing a ~/.ssh/config with no hosts"

if [[ $DRY_RUN != true ]]; then
  mkdir -p "$TARGET_HOME/.ssh"
  chmod 700 "$TARGET_HOME/.ssh"
fi

cat <<SSHCFG | write_user_file "$TARGET_HOME/.ssh/config" 600
# Written by manjaro-setup (47-ssh-config.sh) from SSH_CONFIG in
# config.local.sh. Edit it there; this file is regenerated on every run.

${SSH_CONFIG:-}
SSHCFG

exit 0
