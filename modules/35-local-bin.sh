#!/usr/bin/env bash
# Everything that belongs on ~/.local/bin.
#
# These are standalone scripts in this repo rather than packages, so they are
# symlinked -- editing bin/<name> takes effect immediately and `git status`
# shows the drift, the same contract the stowed dotfiles have.

log "Linking $ROOT/bin into $TARGET_HOME/.local/bin"
run mkdir -p "$TARGET_HOME/.local/bin"

for src in "$ROOT"/bin/*; do
  [[ -f $src ]] || continue
  name=$(basename "$src")
  dest="$TARGET_HOME/.local/bin/$name"

  run chmod 755 "$src"

  if [[ -L $dest && $(readlink -f "$dest") == "$(readlink -f "$src")" ]]; then
    skip "$name already linked"
    continue
  fi
  if [[ -e $dest && ! -L $dest ]]; then
    warn "backing up $dest -> $dest.bak.$(date +%Y%m%d-%H%M%S)"
    run mv "$dest" "$dest.bak.$(date +%Y%m%d-%H%M%S)"
  fi
  run ln -sfn "$src" "$dest"
  ok "linked $name"
done

# redact needs age; it is in packages/repo.txt, but say so plainly if missing.
command -v age >/dev/null || warn "age is not installed -- redact cannot read secrets.age"
