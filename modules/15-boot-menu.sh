#!/usr/bin/env bash
# Windows lives on its own drive with its own EFI System Partition. Teach the
# Manjaro drive's GRUB to chainload it, so picking an OS is a menu entry at
# boot rather than a trip into the BIOS boot device menu.

pkg_install os-prober ntfs-3g

grub_changed=false

# os-prober is disabled by default in current GRUB for security reasons.
set_grub_var GRUB_DISABLE_OS_PROBER false && grub_changed=true
# A hidden menu would defeat the point of having a Windows entry.
set_grub_var GRUB_TIMEOUT_STYLE menu && grub_changed=true
if [[ "$(grep -E '^GRUB_TIMEOUT=' /etc/default/grub | cut -d= -f2 | tr -d '"')" == "0" ]]; then
  set_grub_var GRUB_TIMEOUT 5 && grub_changed=true
fi

CUSTOM_ENTRY=/etc/grub.d/40_custom

# Locate the Windows EFI loader ourselves. os-prober usually finds it, but it
# silently misses ESPs that are not mounted, which is exactly the case here:
# the Windows ESP is on a separate disk and nothing mounts it at boot.
find_windows_esp() {
  local dev mnt tmp hit
  while read -r dev; do
    [[ -b $dev ]] || continue
    mnt=$(findmnt -rn -o TARGET --source "$dev" 2>/dev/null | head -1)
    if [[ -n $mnt ]]; then
      [[ -f "$mnt/EFI/Microsoft/Boot/bootmgfw.efi" ]] && { printf '%s\n' "$dev"; return 0; }
      continue
    fi
    tmp=$(mktemp -d); hit=0
    if sudo mount -o ro "$dev" "$tmp" 2>/dev/null; then
      [[ -f "$tmp/EFI/Microsoft/Boot/bootmgfw.efi" ]] && hit=1
      sudo umount "$tmp" 2>/dev/null || true
    fi
    rmdir "$tmp" 2>/dev/null || true
    [[ $hit == 1 ]] && { printf '%s\n' "$dev"; return 0; }
  done < <(sudo blkid -t TYPE=vfat -o device 2>/dev/null)
  return 1
}

log "Probing for other operating systems"
osprober_out=$(sudo os-prober 2>/dev/null || true)
[[ -n $osprober_out ]] && printf '%s\n' "$osprober_out" | sed 's/^/     /'

if printf '%s' "$osprober_out" | grep -qi 'windows'; then
  ok "os-prober found Windows; GRUB will generate the entry itself"
  # Drop a chainloader entry written by an earlier run, or Windows appears twice.
  if [[ -f $CUSTOM_ENTRY ]] && grep -q 'manjaro-setup' "$CUSTOM_ENTRY"; then
    log "Removing the now-redundant chainloader entry"
    run sudo rm -f "$CUSTOM_ENTRY"
    grub_changed=true
  fi
  win_found=true
else
  win_dev=$(find_windows_esp || true)
  if [[ -z ${win_dev:-} ]]; then
    win_found=false
    warn "No Windows EFI loader found on any FAT partition."
    warn "If the Windows disk is disconnected or powered down, reconnect it and re-run:"
    warn "  ./install.sh --only 15-boot-menu"
  else
    win_found=true
    win_uuid=$(sudo blkid -s UUID -o value "$win_dev")
    ok "Found Windows Boot Manager on $win_dev (UUID $win_uuid)"
    log "os-prober missed it; writing an explicit chainloader entry"
    cat <<GRUBENTRY | write_file "$CUSTOM_ENTRY" 755
#!/bin/sh
exec tail -n +3 \$0
# Written by manjaro-setup (15-boot-menu.sh). Do not edit by hand.
menuentry "Windows Boot Manager" --class windows --class os {
    insmod part_gpt
    insmod fat
    insmod chain
    search --no-floppy --fs-uuid --set=root $win_uuid
    chainloader /EFI/Microsoft/Boot/bootmgfw.efi
}
GRUBENTRY
    grub_changed=true
  fi
fi

if [[ $grub_changed == true ]]; then
  regen_grub
else
  skip "GRUB configuration already up to date"
fi

if [[ ${win_found:-false} == true ]] && [[ $DRY_RUN != true ]]; then
  # grub.cfg is 0600 root, so this must go through sudo -- a plain grep always
  # fails for the invoking user and reported a missing entry that was there.
  if sudo grep -qi 'windows' /boot/grub/grub.cfg 2>/dev/null; then
    ok "grub.cfg contains a Windows entry"
  else
    warn "grub.cfg still has no Windows entry -- inspect 'sudo os-prober' by hand"
  fi
fi

# Windows keeps the RTC in local time by default; Linux keeps it in UTC. Left
# alone, the clock jumps by the UTC offset on every switch.
if [[ ${RTC_LOCAL_TIME:-false} == true ]]; then
  if [[ "$(timedatectl show -p LocalRTC --value)" == "yes" ]]; then
    skip "RTC already in local time"
  else
    log "Switching the RTC to local time to match Windows"
    run sudo timedatectl set-local-rtc 1 --adjust-system-clock
  fi
elif [[ ${win_found:-false} == true ]]; then
  warn "Clock: Linux keeps the RTC in UTC, Windows uses local time by default."
  warn "  Preferred fix, in an elevated Windows command prompt:"
  warn '    reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f'
  warn "  Or set RTC_LOCAL_TIME=true in config.sh to make Linux match Windows instead."
fi
