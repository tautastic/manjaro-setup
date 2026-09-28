#!/usr/bin/env bash
# Ensure the GNOME surface this setup actually uses is present and enabled.

log "Installing the GNOME core set"
# shellcheck disable=SC2046  # splitting the manifest into arguments is the point
pkg_install $(read_pkg_list "$ROOT/packages/gnome-core.txt")

svc_enable gdm.service bluetooth.service

# pipewire, with ALSA and PulseAudio compatibility
if [[ $DRY_RUN != true ]]; then
  as_user systemctl --user enable pipewire.service pipewire-pulse.service wireplumber.service \
    || warn "could not enable the pipewire user units (no user session yet?) -- they are socket-activated anyway"
fi

# printing is not used
svc_disable cups.service cups.socket

# gvfs has no unit of its own; it is D-Bus activated.
pkg_installed gvfs && ok "gvfs present (D-Bus activated, no unit to enable)"
