#!/usr/bin/env bash
set -euo pipefail
ROOT=${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"

if ! command -v mhwd >/dev/null; then
  die "mhwd not found -- this module expects Manjaro"
fi

log "Checking which GPU drives the display"
dgpu_has_display=false
for conn in /sys/class/drm/card*-*; do
  [[ -e $conn/status ]] || continue
  [[ $(cat "$conn/status") == connected ]] || continue
  card=${conn%%-*}
  drv=$(basename "$(readlink -f "$card/device/driver" 2>/dev/null)" 2>/dev/null || true)
  ok "display on $(basename "$conn") (driver: ${drv:-unknown})"
  [[ $drv == nvidia* || $drv == nouveau ]] && dgpu_has_display=true
done

if [[ $dgpu_has_display == false ]]; then
  warn "No display is attached to the NVIDIA card."
  warn "  MHWD_VIDEO_CONFIG is '$MHWD_VIDEO_CONFIG'. If your monitor is on the"
  warn "  motherboard instead, you probably want video-hybrid-intel-nvidia-prime."
fi

if mhwd -li | grep -qw "$MHWD_VIDEO_CONFIG"; then
  skip "mhwd $MHWD_VIDEO_CONFIG already installed"
else
  log "Installing $MHWD_VIDEO_CONFIG via mhwd"
  run sudo mhwd -i pci "$MHWD_VIDEO_CONFIG"
fi

log "Installing NVIDIA userspace extras"
pkg_install opencl-nvidia lib32-nvidia-utils

log "Adding NVIDIA kernel parameters to GRUB"
current=$(grub_value GRUB_CMDLINE_LINUX_DEFAULT || true)
wanted="$current"
for param in nvidia_drm.modeset=1 nvidia_drm.fbdev=1; do
  [[ " $wanted " == *" $param "* ]] || wanted="$wanted $param"
done
wanted=$(printf '%s' "$wanted" | tr -s ' ' | sed -E 's/^ | $//g')
if [[ "$wanted" == "$current" ]]; then
  skip "GRUB_CMDLINE_LINUX_DEFAULT already has the NVIDIA parameters"
else
  grub_write GRUB_CMDLINE_LINUX_DEFAULT "$wanted"
  regen_grub
fi

log "Configuring early KMS in mkinitcpio"
mods_current=$(grep -E '^MODULES=' /etc/mkinitcpio.conf | sed -E 's/^MODULES=\((.*)\)$/\1/')
mods_wanted="$mods_current"
for m in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
  [[ " $mods_wanted " == *" $m "* ]] || mods_wanted="$mods_wanted $m"
done
mods_wanted=$(printf '%s' "$mods_wanted" | tr -s ' ' | sed -E 's/^ | $//g')
initrd_changed=false
if [[ "$mods_wanted" != "$mods_current" ]]; then
  run sudo sed -i -E "s|^MODULES=\(.*\)|MODULES=($mods_wanted)|" /etc/mkinitcpio.conf
  initrd_changed=true
fi
if grep -E '^HOOKS=' /etc/mkinitcpio.conf | grep -qw kms; then
  run sudo sed -i -E '/^HOOKS=/ s/\bkms\b *//; /^HOOKS=/ s/  +/ /g' /etc/mkinitcpio.conf
  initrd_changed=true
fi
if [[ $initrd_changed == true ]]; then
  run sudo mkinitcpio -P
else
  skip "mkinitcpio already configured"
fi

printf 'options nvidia NVreg_PreserveVideoMemoryAllocations=1\n' \
  | write_file /etc/modprobe.d/nvidia-power.conf 644
svc_enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service

exit 0
