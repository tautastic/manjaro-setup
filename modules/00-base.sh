#!/usr/bin/env bash
# pacman configuration, multilib, yay, and the base system package set.

log "Configuring /etc/pacman.conf"
run sudo sed -i -E 's/^#(Color)$/\1/' /etc/pacman.conf
if grep -qE '^#?ParallelDownloads' /etc/pacman.conf; then
  run sudo sed -i -E 's/^#?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
else
  run sudo sed -i '/^\[options\]/a ParallelDownloads = 10' /etc/pacman.conf
fi

# multilib is required for lib32-nvidia-utils and lib32-pipewire
# and lib32-pipewire.
if grep -qE '^\[multilib\]' /etc/pacman.conf; then
  skip "[multilib] already enabled"
else
  log "Enabling [multilib]"
  run sudo sed -i -E '/^#\[multilib\]/,+1 s/^#//' /etc/pacman.conf
  grep -qE '^\[multilib\]' /etc/pacman.conf || \
    run sudo sh -c 'printf "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n" >> /etc/pacman.conf'
fi

log "Refreshing package databases"
run sudo pacman -Syu --noconfirm

pkg_install base-devel git

# Manjaro ships yay in its own repos, so no manual bootstrap is needed.
if command -v yay >/dev/null; then
  skip "yay already present"
else
  pkg_install yay
fi

log "Installing base system packages"
# shellcheck disable=SC2046  # splitting the manifest into arguments is the point
pkg_install $(read_pkg_list "$ROOT/packages/repo.txt")
