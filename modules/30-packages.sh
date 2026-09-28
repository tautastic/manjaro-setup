#!/usr/bin/env bash
# The user package set, minus what the base and GNOME modules already cover.
# repo.txt is installed in 00-base; this module handles the AUR half and
# refreshes the font cache.

log "Installing AUR packages"
# shellcheck disable=SC2046  # splitting the manifest into arguments is the point
aur_install $(read_pkg_list "$ROOT/packages/aur.txt")

if [[ $DRY_RUN != true ]]; then
  log "Rebuilding the font cache"
  as_user fc-cache -f
fi
