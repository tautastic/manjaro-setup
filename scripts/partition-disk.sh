#!/usr/bin/env bash
#
# Partition a disk for this Manjaro install, from a live ISO:
#
#   GPT
#    p1  1 GiB   ESP,  vfat, label EFI,  name disk-main-ESP   -> /boot/efi
#    p2  2 GiB   boot, ext4, label BOOT, name disk-main-boot  -> /boot
#    p3  rest    LUKS2,                  name disk-main-luks
#          └─ cryptroot: btrfs, label ROOT
#               @      -> /       (compress=zstd)
#               @home  -> /home   (compress=zstd)
#               @swap  -> /swap   (16 GiB swapfile)
#
# /boot and /boot/efi are deliberately outside the LUKS container: GRUB reads the
# kernel and initramfs from /boot before anything is unlocked, and Calamares
# expects the ESP at /boot/efi.
#
# THIS ERASES THE TARGET DISK. It asks for the LUKS passphrase and for the
# device path, typed out in full, before it writes anything.
#
#   ./scripts/partition-disk.sh --dry-run /dev/sdX
#   ./scripts/partition-disk.sh /dev/sdX
#   ./scripts/partition-disk.sh --keep-mounted /dev/sdX   # for a pacstrap install

set -euo pipefail

ESP_SIZE=1GiB
BOOT_SIZE=2GiB
SWAP_SIZE=16G
ESP_LABEL=disk-main-ESP
BOOT_LABEL=disk-main-boot
LUKS_LABEL=disk-main-luks
MAPPER=cryptroot
FS_LABEL_EFI=EFI
FS_LABEL_BOOT=BOOT
FS_LABEL_ROOT=ROOT
SUBVOLS=("@:/" "@home:/home" "@swap:/swap")

DRY_RUN=false
KEEP_MOUNTED=false
TARGET=/mnt

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
    --keep-mounted) KEEP_MOUNTED=true; shift ;;
    --target)  TARGET=${2:?--target needs a path}; shift 2 ;;
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

for c in sfdisk cryptsetup mkfs.btrfs mkfs.fat mkfs.ext4 btrfs lsblk findmnt; do
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

if lsblk -no FSTYPE "$DEV" | grep -q crypto_LUKS; then
  warn "$DEV already contains a LUKS container; it will be destroyed"
fi

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
printf '  %-14s %-9s %s\n' "$P3" "rest" "LUKS2, name $LUKS_LABEL"
printf '  %-14s %-9s %s\n' "  $MAPPER" "" "btrfs, label $FS_LABEL_ROOT"
for s in "${SUBVOLS[@]}"; do printf '  %-14s %-9s %s\n' "    ${s%%:*}" "" "-> ${s##*:}"; done
printf '  %-14s %-9s %s\n' "    swapfile" "$SWAP_SIZE" "in @swap"
printf '%sEverything on %s will be destroyed.%s\n\n' "$RED" "$DEV" "$RST"


if [[ $DRY_RUN != true ]]; then
  printf 'Type the device path to confirm: '
  IFS= read -r confirm </dev/tty
  [[ $confirm == "$DEV" ]] || die "got '$confirm', expected '$DEV' -- nothing was changed"
fi

pass=""
if [[ $DRY_RUN != true ]]; then
  while :; do
    printf 'LUKS passphrase: ' >&2;  IFS= read -rs pass  </dev/tty; printf '\n' >&2
    printf 'Confirm:         ' >&2;  IFS= read -rs pass2 </dev/tty; printf '\n' >&2
    [[ -n $pass ]] || { warn "empty passphrase"; continue; }
    [[ $pass == "$pass2" ]] && break
    warn "passphrases do not match"
  done
  unset pass2
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

log "Creating the LUKS2 container"
if [[ $DRY_RUN == true ]]; then
  printf '%s would run:%s cryptsetup luksFormat --type luks2 %s\n' "$DIM" "$RST" "$P3"
  printf '%s would run:%s cryptsetup open %s %s\n' "$DIM" "$RST" "$P3" "$MAPPER"
else
  printf '%s' "$pass" | cryptsetup luksFormat --type luks2 --batch-mode --key-file - "$P3" \
    || die "luksFormat failed"
  printf '%s' "$pass" | cryptsetup open --key-file - "$P3" "$MAPPER" \
    || die "could not open the new container"
fi
unset pass
ok "LUKS2 container ready at /dev/mapper/$MAPPER"

log "Creating the btrfs filesystem"
run mkfs.btrfs -f -L "$FS_LABEL_ROOT" "/dev/mapper/$MAPPER"

log "Creating subvolumes"
if [[ $DRY_RUN == true ]]; then
  for s in "${SUBVOLS[@]}"; do printf '%s would run:%s btrfs subvolume create <top>/%s\n' "$DIM" "$RST" "${s%%:*}"; done
else
  top=$(mktemp -d)
  mount "/dev/mapper/$MAPPER" "$top"
  for s in "${SUBVOLS[@]}"; do btrfs subvolume create "$top/${s%%:*}" >/dev/null; ok "created ${s%%:*}"; done
  umount "$top"; rmdir "$top"
fi

log "Mounting at $TARGET"
run mkdir -p "$TARGET"
run mount -o "subvol=@,compress=zstd" "/dev/mapper/$MAPPER" "$TARGET"
run mkdir -p "$TARGET/home" "$TARGET/swap" "$TARGET/boot"
run mount -o "subvol=@home,compress=zstd" "/dev/mapper/$MAPPER" "$TARGET/home"
run mount -o "subvol=@swap,noatime"       "/dev/mapper/$MAPPER" "$TARGET/swap"
run mount "$P2" "$TARGET/boot"
run mkdir -p "$TARGET/boot/efi"
run mount -o "fmask=0077,dmask=0077" "$P1" "$TARGET/boot/efi"

log "Creating the $SWAP_SIZE swapfile"
if [[ $DRY_RUN == true ]]; then
  printf '%s would run:%s btrfs filesystem mkswapfile --size %s --uuid clear %s/swap/swapfile\n' \
    "$DIM" "$RST" "$SWAP_SIZE" "$TARGET"
else
  btrfs filesystem mkswapfile --size "$SWAP_SIZE" --uuid clear "$TARGET/swap/swapfile" \
    || die "could not create the swapfile"
  swapon "$TARGET/swap/swapfile" || warn "could not activate the swapfile yet"
fi
ok "swapfile ready"

if [[ $DRY_RUN != true && $KEEP_MOUNTED != true ]]; then
  log "Unmounting, so the installer can mount the layout itself"
  swapoff "$TARGET/swap/swapfile" 2>/dev/null || true
  umount -R "$TARGET" || warn "could not unmount $TARGET cleanly"
  ok "layout left in place; LUKS still open at /dev/mapper/$MAPPER"
fi

if [[ $DRY_RUN != true ]]; then
  log "Layout"
  lsblk -o NAME,PARTLABEL,FSTYPE,LABEL,SIZE,MOUNTPOINT "$DEV"
fi

cat <<NEXT

Next
  The layout is on the disk and the LUKS container is open as
  /dev/mapper/$MAPPER. Nothing is mounted, so the installer can mount it itself.
  (Pass --keep-mounted if you want it left mounted at $TARGET for a pacstrap
  install instead.)

  In Calamares choose manual partitioning and assign these mountpoints, with
  "keep"/no reformat on every one:

    $P1  ->  /boot/efi   (vfat)
    $P2  ->  /boot       (ext4)
    $P3  ->  /           (luks -> btrfs, subvolume @)

  Calamares only offers /boot/efi for a partition flagged esp, which $P1 is.

  The installed fstab should end up as:

    /dev/mapper/$MAPPER  /          btrfs  subvol=@,compress=zstd      0 0
    /dev/mapper/$MAPPER  /home      btrfs  subvol=@home,compress=zstd  0 0
    /dev/mapper/$MAPPER  /swap      btrfs  subvol=@swap,noatime,nofail 0 0
    /dev/disk/by-partlabel/$BOOT_LABEL  /boot      ext4  defaults              0 2
    /dev/disk/by-partlabel/$ESP_LABEL   /boot/efi  vfat  fmask=0077,dmask=0077 0 2
    /swap/swapfile  none  swap  defaults  0 0

  and /etc/crypttab should open $LUKS_LABEL as $MAPPER:

    $MAPPER  /dev/disk/by-partlabel/$LUKS_LABEL  none  luks

  If Calamares will not let you pick the btrfs subvolumes, let it install and
  then fix /etc/fstab to the above and run: sudo mkinitcpio -P && sudo update-grub

  Check afterwards that /etc/default/grub has
    cryptdevice=/dev/disk/by-partlabel/$LUKS_LABEL:$MAPPER root=/dev/mapper/$MAPPER
  and that /etc/mkinitcpio.conf HOOKS contains "encrypt" before "filesystems".

  Then run ./install.sh from the installed system, as the user the config expects.
NEXT
