#!/usr/bin/env bash
set -euo pipefail
ROOT=${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"

svc_enable gdm.service bluetooth.service

if [[ $DRY_RUN != true ]]; then
  as_user systemctl --user enable pipewire.service pipewire-pulse.service wireplumber.service \
    || warn "could not enable the pipewire user units (no user session yet?) -- they are socket-activated anyway"
fi

svc_disable cups.service cups.socket

if pkg_installed gvfs; then
  ok "gvfs present (D-Bus activated, no unit to enable)"
else
  warn "gvfs is not installed; Nautilus will not mount anything"
fi

if [[ -f /etc/udev/rules.d/61-gdm.rules ]]; then
  warn "/etc/udev/rules.d/61-gdm.rules exists and may be forcing GDM onto X11"
fi
if grep -qE '^\s*WaylandEnable\s*=\s*false' /etc/gdm/custom.conf 2>/dev/null; then
  log "Re-enabling Wayland in /etc/gdm/custom.conf"
  run sudo sed -i -E 's/^\s*WaylandEnable\s*=\s*false/#WaylandEnable=false/' /etc/gdm/custom.conf
fi

exit 0
