#!/usr/bin/env bash
set -euo pipefail
ROOT=${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"

log "Installing Docker"
pkg_install docker docker-compose docker-buildx fuse-overlayfs slirp4netns
svc_enable docker.service

if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
  skip "$TARGET_USER already in the docker group"
else
  log "Adding $TARGET_USER to the docker group"
  run sudo usermod -aG docker "$TARGET_USER"
  warn "group change takes effect at the next login"
fi

if grep -q "^$TARGET_USER:" /etc/subuid 2>/dev/null \
   && grep -q "^$TARGET_USER:" /etc/subgid 2>/dev/null; then
  skip "/etc/subuid and /etc/subgid already have ranges for $TARGET_USER"
else
  subid_args=()
  grep -q "^$TARGET_USER:" /etc/subuid 2>/dev/null || subid_args+=(--add-subuids 100000-165535)
  grep -q "^$TARGET_USER:" /etc/subgid 2>/dev/null || subid_args+=(--add-subgids 100000-165535)
  run sudo usermod "${subid_args[@]}" "$TARGET_USER"
fi

rootless_ready=false
if [[ $DRY_RUN != true ]] && as_user systemctl --user is-enabled --quiet docker.service 2>/dev/null; then
  rootless_ready=true
fi

if [[ $rootless_ready == true ]]; then
  skip "rootless docker already set up"
elif [[ $DRY_RUN != true ]]; then
  log "Setting up rootless Docker for $TARGET_USER"
  as_user dockerd-rootless-setuptool.sh install --skip-iptables \
    || warn "rootless setup failed -- run 'dockerd-rootless-setuptool.sh install' from a graphical login"
  as_user systemctl --user enable docker.service 2>/dev/null || true
  run sudo loginctl enable-linger "$TARGET_USER"
fi

log "Configuring sshd"
cat <<SSHD | write_file /etc/ssh/sshd_config.d/10-hardening.conf 644
# Written by manjaro-setup (40-services.sh). Do not edit by hand.
Port 22
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers $TARGET_USER
SSHD
svc_enable sshd.service

if [[ ${ENABLE_FIREWALL:-false} == true ]]; then
  log "Enabling the firewall"
  pkg_install ufw
  run sudo ufw --force enable
  run sudo ufw allow 22/tcp
else
  svc_disable ufw.service firewalld.service
  warn "Firewall is off, by choice."
  warn "  sshd on :22 is reachable from the LAN -- key-only, $TARGET_USER only."
fi

svc_enable acpid.service NetworkManager.service

printf 'net.ipv4.ip_forward = 1\n' | write_file /etc/sysctl.d/99-ip-forward.conf 644

exit 0
