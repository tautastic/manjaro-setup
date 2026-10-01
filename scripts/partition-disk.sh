#!/usr/bin/env bash
#
# Lay down the partition table this Manjaro install expects, from a live ISO:
#
#   GPT
#    p1  1 GiB   ESP,  vfat, label EFI,  name disk-main-ESP   -> /boot/efi
#    p2  2 GiB   boot, ext4, label BOOT, name disk-main-boot  -> /boot
#    p3  rest    left empty,             name disk-main-luks  -> / (LUKS + btrfs)
#
# p3 is deliberately left unformatted. Calamares creates the LUKS container, the
# btrfs filesystem and the subvolumes itself, and its mount module runs
# `btrfs subvolume create` unconditionally -- so a pre-made @ makes the install
# fail with "Bad main script file". Its defaults are @ and @home, which is what
# we want anyway; modules/18-swapfile adds @swap afterwards.
#
# /boot and /boot/efi stay outside the encryption: GRUB reads the kernel and
# initramfs before anything is unlocked, and Calamares only offers /boot/efi as
# a mountpoint for an ESP.
#
# THIS ERASES THE TARGET DISK. It asks for the device path, typed out in full,
# before it writes anything.
#
#   ./scripts/partition-disk.sh --dry-run /dev/nvme0n1
#   ./scripts/partition-disk.sh /dev/nvme0n1

set -euo pipefail

ESP_SIZE=1GiB
BOOT_SIZE=2GiB
ESP_LABEL=disk-main-ESP
BOOT_LABEL=disk-main-boot
LUKS_LABEL=disk-main-luks
FS_LABEL_EFI=EFI
FS_LABEL_BOOT=BOOT

DRY_RUN=false

if [[ -t 1 ]]; then
  RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; BLU=$'\033[34m'; DIM=$'\033[2m'; RST=$'\033[0m'
else
  RED=""; GRN=""; YLW=""; BLU=""; DIM=""; RST=""
fi
log()  { printf '%s==>%s %s\n' "$BLU" "$RST" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '%s warn%s %s\n' "$YLW" "$RST" "$*" >&2; }
die()  { printf '%sfail%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }

run() {
  if [[ $DRY_RUN == true ]]; then
    printf '%s would run:%s %s\n' "$DIM" "$RST" "$*"
  else
    "$@" || die "command failed: $*"
  fi
}

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; }

DEV=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        die "unknown option: $1 (try --help)" ;;
    *)         [[ -z $DEV ]] || die "give exactly one device"; DEV=$1; shift ;;
  esac
done
[[ -n $DEV ]] || { usage; exit 2; }

partdev() {
  if [[ $1 =~ (nvme[0-9]+n[0-9]+|mmcblk[0-9]+|loop[0-9]+)$ ]]; then printf '%sp%s' "$1" "$2"
  else printf '%s%s' "$1" "$2"; fi
}
P1=$(partdev "$DEV" 1)
P2=$(partdev "$DEV" 2)
P3=$(partdev "$DEV" 3)

for c in sfdisk mkfs.fat mkfs.ext4 wipefs lsblk findmnt; do
  command -v "$c" >/dev/null || die "$c is not installed"
done
[[ $DRY_RUN == true || $EUID -eq 0 ]] || die "run this as root from a live ISO"
[[ -b $DEV ]] || die "$DEV is not a block device"

log "Checking $DEV is safe to erase"

descendants() {
  local line name mp
  while IFS= read -r line; do
    name=${line#NAME=\"}; name=${name%%\"*}
    mp=${line##*MOUNTPOINT=\"}; mp=${mp%\"}
    printf '%s\t%s\n' "$name" "$mp"
  done < <(lsblk -nPo NAME,MOUNTPOINT "$1")
}

root_src=$(findmnt -no SOURCE / | sed 's/\[.*//')
root_name=${root_src#/dev/}; root_name=${root_name#mapper/}
while IFS=$'\t' read -r name _; do
  [[ $name == "$root_name" ]] && die "$DEV carries the running root filesystem"
done < <(descendants "$DEV")

while IFS=$'\t' read -r name mp; do
  [[ -n $mp ]] && die "/dev/$name is mounted at $mp -- unmount everything on $DEV first"
done < <(descendants "$DEV")
ok "nothing on $DEV is mounted"

log "Looking for a Windows EFI partition on $DEV"
found_windows=false
while IFS=$'\t' read -r name _; do
  [[ $name == "$(basename "$DEV")" ]] && continue
  [[ $(lsblk -no FSTYPE --nodeps "/dev/$name" 2>/dev/null) == vfat ]] || continue
  probe=$(mktemp -d)
  if mount -o ro "/dev/$name" "$probe" 2>/dev/null; then
    [[ -e $probe/EFI/Microsoft/Boot/bootmgfw.efi ]] && found_windows=true
    umount "$probe" 2>/dev/null || true
  fi
  rmdir "$probe" 2>/dev/null || true
done < <(descendants "$DEV")
[[ $found_windows == true ]] && die "$DEV contains a Windows boot manager -- refusing. Pick the other disk."
ok "no Windows boot manager on $DEV"

size=$(lsblk -bno SIZE --nodeps "$DEV" 2>/dev/null || echo 0)
printf '\n%sPlan for %s (%s)%s\n' "$YLW" "$DEV" "$( [[ $size -gt 0 ]] && numfmt --to=iec "$size" || echo unknown )" "$RST"
printf '  %-14s %-9s %s\n' "$P1" "$ESP_SIZE" "ESP, vfat, label $FS_LABEL_EFI, name $ESP_LABEL -> /boot/efi"
printf '  %-14s %-9s %s\n' "$P2" "$BOOT_SIZE" "ext4, label $FS_LABEL_BOOT, name $BOOT_LABEL -> /boot"
printf '  %-14s %-9s %s\n' "$P3" "rest" "empty, name $LUKS_LABEL -> Calamares makes this LUKS + btrfs"
printf '%sEverything on %s will be destroyed.%s\n\n' "$RED" "$DEV" "$RST"

if [[ $DRY_RUN != true ]]; then
  printf 'Type the device path to confirm: '
  IFS= read -r confirm </dev/tty
  [[ $confirm == "$DEV" ]] || die "got '$confirm', expected '$DEV' -- nothing was changed"
fi

log "Partitioning $DEV"
if [[ $DRY_RUN == true ]]; then
  printf '%s would run:%s sfdisk --wipe always --label gpt %s <<layout\n' "$DIM" "$RST" "$DEV"
else
  sfdisk --wipe always --wipe-partitions always --label gpt "$DEV" <<LAYOUT
start=1MiB, size=$ESP_SIZE, type=uefi, name="$ESP_LABEL"
size=$BOOT_SIZE, type=linux, name="$BOOT_LABEL"
type=linux, name="$LUKS_LABEL"
LAYOUT
  udevadm settle 2>/dev/null || true
fi
ok "partition table written"

log "Creating the ESP and /boot"
run mkfs.fat -F32 -n "$FS_LABEL_EFI" "$P1"
run mkfs.ext4 -F -L "$FS_LABEL_BOOT" "$P2"

# Any leftover LUKS or btrfs signature here makes Calamares think there is an
# encrypted volume to mount, and it then tries to mount a mapper that is not open.
log "Clearing any filesystem signature from $P3"
run wipefs -a "$P3"
ok "$P3 is empty, with partition name $LUKS_LABEL"

if [[ $DRY_RUN != true ]]; then
  log "Layout"
  lsblk -o NAME,PARTLABEL,FSTYPE,LABEL,SIZE "$DEV"
fi

cat <<NEXT

Next
  Nothing is mounted and nothing is encrypted yet -- Calamares does that part.

  In Calamares pick manual partitioning and set:

    $P1  ->  /boot/efi   keep, do not format   (vfat, flagged esp)
    $P2  ->  /boot       keep, do not format   (ext4)
    $P3  ->  /           FORMAT as btrfs, and tick encrypt

  Give the encryption passphrase when it asks. Calamares creates the LUKS
  container, the btrfs filesystem, and the @ and @home subvolumes itself.

  Then, from the installed system:

    ./install.sh

  modules/18-swapfile creates the @swap subvolume and the 16 GiB swapfile, since
  Calamares only makes @swap when it is doing the partitioning itself.
NEXT
