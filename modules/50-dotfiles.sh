#!/usr/bin/env bash
set -euo pipefail
ROOT=${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"

STATE="$TARGET_HOME/.local/state/manjaro-setup"
STOWED="$STATE/stowed"

log "Creating directories the configs expect"
for d in .local/bin .local/care .local/go .local/share/zsh/site-functions .cache/zsh .config .ssh "${STATE#"$TARGET_HOME"/}"; do
  run mkdir -p "$TARGET_HOME/$d"
done
[[ $DRY_RUN == true ]] || chmod 700 "$TARGET_HOME/.ssh"

if [[ -f $STOWED ]]; then
  while IFS= read -r pkg; do
    [[ -z $pkg ]] && continue
    printf '%s\n' "${STOW_PACKAGES[@]}" | grep -qxF "$pkg" && continue
    if [[ -d "$ROOT/dotfiles/$pkg" ]]; then
      log "Unstowing $pkg (no longer in STOW_PACKAGES)"
      run stow --dir "$ROOT/dotfiles" --target "$TARGET_HOME" --no-folding -D "$pkg"
    else
      warn "$pkg was stowed but dotfiles/$pkg is gone; leftover symlinks may remain in \$HOME"
    fi
  done < "$STOWED"
fi

stamp=$(date +%Y%m%d-%H%M%S)
log "Checking for files stow would collide with"
collisions=0
for pkg in "${STOW_PACKAGES[@]}"; do
  [[ -d "$ROOT/dotfiles/$pkg" ]] || die "STOW_PACKAGES names $pkg, but dotfiles/$pkg does not exist"
  while IFS= read -r rel; do
    target="$TARGET_HOME/$rel"
    [[ -e $target && ! -L $target ]] || continue
    warn "backing up $target -> $target.bak.$stamp"
    run mv "$target" "$target.bak.$stamp"
    collisions=$((collisions + 1))
  done < <(cd "$ROOT/dotfiles/$pkg" && find . -type f | sed 's|^\./||')
done
[[ $collisions -eq 0 ]] && skip "no collisions"

log "Stowing: ${STOW_PACKAGES[*]}"
run stow --dir "$ROOT/dotfiles" --target "$TARGET_HOME" --no-folding --restow "${STOW_PACKAGES[@]}"

if [[ $DRY_RUN != true ]]; then
  printf '%s\n' "${STOW_PACKAGES[@]}" > "$STOWED"
  chmod 700 "$TARGET_HOME/.ssh"
fi

log "Creating XDG user directories"
while IFS= read -r dir; do
  [[ -d $dir ]] && continue
  run mkdir -p "$dir"
done < <(sed -nE 's/^XDG_[A-Z]+_DIR="(.*)"$/\1/p' "$ROOT/dotfiles/xdg/.config/user-dirs.dirs" \
         | sed "s|^\$HOME|$TARGET_HOME|")

exit 0
