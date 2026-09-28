#!/usr/bin/env bash
# NVIDIA RTX 4060 Ti via Manjaro's mhwd, plus everything GNOME/Wayland needs.

if ! command -v mhwd >/dev/null; then
  die "mhwd not found -- this module expects Manjaro"
fi

# Install a named config rather than `mhwd -a pci nonfree 0300`. On a board with
# an active iGPU there are two class-0300 devices, and auto-select takes the
# first match -- which is video-hybrid-intel-nvidia-prime, a PRIME setup that
# makes the iGPU primary. That is wrong whenever the monitor is plugged into the
# discrete card.
log "Checking which GPU drives the display"
dgpu_has_display=false
for conn in /sys/class/drm/card*-*; do
  [[ -e $conn/status ]] || continue
  [[ $(cat "$conn/status") == connected ]] || continue
  card=${conn%%-*}                    # card0-DP-5 -> card0, not card0-DP
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

# OpenCL, and the 32-bit libraries Steam and Wine need
log "Installing NVIDIA userspace extras"
pkg_install opencl-nvidia lib32-nvidia-utils

# GNOME on Wayland needs DRM modesetting. fbdev gives a working console.
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
  # Each module runs in its own subshell, so this cannot be handed to
  # 15-boot-menu through a variable. Regenerate here; that module regenerates
  # again if it has its own changes, and update-grub is idempotent.
  regen_grub
fi

# Early KMS: load the modules from the initramfs so the console comes up right.
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
# The kms hook loads nouveau/simpledrm and fights the NVIDIA modules.
if grep -E '^HOOKS=' /etc/mkinitcpio.conf | grep -qw kms; then
  run sudo sed -i -E '/^HOOKS=/ s/\bkms\b *//; /^HOOKS=/ s/  +/ /g' /etc/mkinitcpio.conf
  initrd_changed=true
fi
if [[ $initrd_changed == true ]]; then
  run sudo mkinitcpio -P
else
  skip "mkinitcpio already configured"
fi

# Without this, suspend/resume corrupts the framebuffer on NVIDIA.
printf 'options nvidia NVreg_PreserveVideoMemoryAllocations=1\n' \
  | write_file /etc/modprobe.d/nvidia-power.conf 644
svc_enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service

# Needed for Docker bridge networking.
printf 'net.ipv4.ip_forward = 1\n' | write_file /etc/sysctl.d/99-local.conf 644

# Older GDM shipped a rule that disables Wayland whenever the nvidia driver is
# loaded. With modeset=1 that is no longer wanted.
if [[ -f /etc/udev/rules.d/61-gdm.rules ]]; then
  warn "/etc/udev/rules.d/61-gdm.rules exists and may be forcing GDM onto X11"
fi
if grep -qE '^\s*WaylandEnable\s*=\s*false' /etc/gdm/custom.conf 2>/dev/null; then
  log "Re-enabling Wayland in /etc/gdm/custom.conf"
  run sudo sed -i -E 's/^\s*WaylandEnable\s*=\s*false/#WaylandEnable=false/' /etc/gdm/custom.conf
fi
