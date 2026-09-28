#!/usr/bin/env bash
# Symlink dotfiles/ into $TARGET_HOME with GNU stow.

pkg_install stow

log "Creating directories the configs expect"
for d in .local/bin .local/care .local/go .local/share/zsh/site-functions .cache/zsh .config; do
  run mkdir -p "$TARGET_HOME/$d"
done

# A fresh Manjaro install ships real files at some of these paths; stow refuses
# to overwrite them, so move them aside first.
stamp=$(date +%Y%m%d-%H%M%S)
log "Checking for files stow would collide with"
collisions=0
while read -r rel; do
  target="$TARGET_HOME/$rel"
  [[ -e $target && ! -L $target ]] || continue
  warn "backing up $target -> $target.bak.$stamp"
  run mv "$target" "$target.bak.$stamp"
  collisions=$((collisions + 1))
done < <(cd "$ROOT/dotfiles" && find . -mindepth 2 -type f | sed 's|^\./[^/]*/||')
[[ $collisions -eq 0 ]] && skip "no collisions"

# --no-folding keeps every directory a real directory and symlinks only files.
# Otherwise stow would symlink whole trees, and
# runtime files -- .zcompdump under $ZDOTDIR, ssh known_hosts -- would be written
# into the repo. It also keeps ~/.ssh a real directory so it can be chmod 700.
log "Stowing: ${STOW_PACKAGES[*]}"
run stow --dir "$ROOT/dotfiles" --target "$TARGET_HOME" --no-folding --restow "${STOW_PACKAGES[@]}"

[[ -d "$TARGET_HOME/.ssh" && $DRY_RUN != true ]] && chmod 700 "$TARGET_HOME/.ssh" || true

# xdg.userDirs.createDirectories = true. The stowed user-dirs.conf carries
# `enabled=False`, so xdg-user-dirs-update deliberately leaves the file alone
# -- create the directories it names directly instead.
log "Creating XDG user directories"
while IFS= read -r dir; do
  [[ -d $dir ]] && continue
  run mkdir -p "$dir"
done < <(sed -nE 's/^XDG_[A-Z]+_DIR="(.*)"$/\1/p' "$ROOT/dotfiles/xdg/.config/user-dirs.dirs" \
         | sed "s|^\$HOME|$TARGET_HOME|")
