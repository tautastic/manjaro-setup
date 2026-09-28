#!/usr/bin/env bash
# Docker (rootful + rootless), sshd, and the services this setup deliberately
# leaves off.

### Docker, rootful and rootless
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

# rootless.enable -- subuid/subgid ranges plus the per-user daemon.
for f in /etc/subuid /etc/subgid; do
  if grep -q "^$TARGET_USER:" "$f" 2>/dev/null; then
    skip "$f already has a range for $TARGET_USER"
  else
    run sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$TARGET_USER"
    break
  fi
done

if [[ -x "$TARGET_HOME/bin/dockerd-rootless.sh" ]] || \
   as_user systemctl --user is-enabled --quiet docker.service 2>/dev/null; then
  skip "rootless docker already set up"
elif [[ $DRY_RUN != true ]]; then
  log "Setting up rootless Docker for $TARGET_USER"
  as_user dockerd-rootless-setuptool.sh install --skip-iptables \
    || warn "rootless setup failed -- run 'dockerd-rootless-setuptool.sh install' from a graphical login"
  as_user systemctl --user enable docker.service 2>/dev/null || true
  run sudo loginctl enable-linger "$TARGET_USER"
fi

### sshd
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

### firewall
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
