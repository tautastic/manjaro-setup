#!/usr/bin/env bash
set -euo pipefail
ROOT=${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"

SWAPFILE=/swap/swapfile

fstab_has_mount() {
  awk -v m="$1" '$1 !~ /^#/ && $2 == m { found = 1 } END { exit !found }' /etc/fstab
}

if swapon --show=NAME --noheadings 2>/dev/null | grep -qxF "$SWAPFILE"; then
  skip "$SWAPFILE is already active"
  exit 0
fi

[[ $(findmnt -no FSTYPE /) == btrfs ]] || die "/ is not btrfs; this module assumes the btrfs layout"
root_src=$(findmnt -no SOURCE / | sed 's/\[.*//')
[[ -n $root_src ]] || die "could not determine the device behind /"

if mountpoint -q /swap; then
  skip "/swap is already mounted"
else
  log "Making sure the @swap subvolume exists"
  top=$(mktemp -d)
  cleanup_top() { sudo umount "$top" 2>/dev/null || true; rmdir "$top" 2>/dev/null || true; }
  trap cleanup_top EXIT
  run sudo mount -o subvolid=5 "$root_src" "$top"
  if [[ -e $top/@swap ]]; then
    skip "@swap already exists"
  else
    run sudo btrfs subvolume create "$top/@swap"
    ok "created @swap"
  fi
  cleanup_top
  trap - EXIT

  if fstab_has_mount /swap; then
    skip "/etc/fstab already mounts /swap"
  else
    append_line /etc/fstab "$root_src /swap btrfs subvol=@swap,noatime,nofail 0 0"
  fi
  run sudo mkdir -p /swap
  [[ $DRY_RUN == true ]] || mountpoint -q /swap || run sudo mount /swap
fi

if [[ -f $SWAPFILE ]]; then
  skip "$SWAPFILE already exists"
else
  log "Creating the $SWAP_SIZE swapfile"
  run sudo btrfs filesystem mkswapfile --size "$SWAP_SIZE" --uuid clear "$SWAPFILE"
fi

if grep -qE "^[^#]*${SWAPFILE}[[:space:]]+none[[:space:]]+swap" /etc/fstab 2>/dev/null; then
  skip "/etc/fstab already has the swap entry"
else
  append_line /etc/fstab "$SWAPFILE none swap defaults 0 0"
fi

run sudo swapon "$SWAPFILE"
ok "swap is active"

exit 0
