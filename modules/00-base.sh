#!/usr/bin/env bash
set -euo pipefail
ROOT=${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"

log "Configuring /etc/pacman.conf"
run sudo sed -i -E 's/^#(Color)$/\1/' /etc/pacman.conf
if grep -qE '^#?ParallelDownloads' /etc/pacman.conf; then
  run sudo sed -i -E 's/^#?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
else
  run sudo sed -i '/^\[options\]/a ParallelDownloads = 10' /etc/pacman.conf
fi

if grep -qE '^\[multilib\]' /etc/pacman.conf; then
  skip "[multilib] already enabled"
else
  log "Enabling [multilib]"
  run sudo sed -i -E '/^#\[multilib\]/,+1 s/^#//' /etc/pacman.conf
  grep -qE '^\[multilib\]' /etc/pacman.conf \
    || die "could not uncomment [multilib]; add it to /etc/pacman.conf by hand"
fi

pkg_install base-devel git
if command -v yay >/dev/null; then
  skip "yay already present"
else
  pkg_install yay
fi

log "Reconciling the explicit package set against the manifest"
install_missing

if [[ $PRUNE == true ]]; then
  prune_extraneous
else
  extra=$(report_extraneous)
  if [[ -n $extra ]]; then
    warn "installed explicitly but not in the manifest ($(printf '%s\n' "$extra" | grep -c .)):"
    printf '%s\n' "$extra" | sed 's/^/       /' >&2
    warn "add them to packages/want.txt, or remove them with ./install.sh --prune"
  else
    skip "nothing installed that the manifest does not list"
  fi
fi

if [[ $DRY_RUN != true ]]; then
  log "Rebuilding the font cache"
  as_user fc-cache -f || warn "font cache rebuild failed"
fi

exit 0
