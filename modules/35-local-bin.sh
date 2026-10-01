#!/usr/bin/env bash
set -euo pipefail
ROOT=${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
# shellcheck source=/dev/null
source "$ROOT/lib/bootstrap.sh"

BIN="$TARGET_HOME/.local/bin"
log "Linking $ROOT/bin into $BIN"
run mkdir -p "$BIN"

for src in "$ROOT"/bin/*; do
  [[ -f $src ]] || continue
  name=$(basename "$src")
  dest="$BIN/$name"

  [[ -x $src ]] || warn "$src is not executable; fix its mode in the repo"

  if [[ -L $dest && $(readlink -f "$dest") == "$(readlink -f "$src")" ]]; then
    skip "$name already linked"
    continue
  fi
  if [[ -e $dest && ! -L $dest ]]; then
    stamp=$(date +%Y%m%d-%H%M%S)
    warn "backing up $dest -> $dest.bak.$stamp"
    run mv "$dest" "$dest.bak.$stamp"
  fi
  run ln -sfn "$src" "$dest"
  ok "linked $name"
done

shopt -s nullglob
for dest in "$BIN"/*; do
  [[ -L $dest ]] || continue
  target=$(readlink -f "$dest" || true)
  case $target in
    "$ROOT"/bin/*) [[ -e $target ]] || { warn "removing dangling link $dest"; run rm -f "$dest"; } ;;
    "") [[ -e $dest ]] || { warn "removing dangling link $dest"; run rm -f "$dest"; } ;;
  esac
done

command -v age >/dev/null || warn "age is not installed -- redact cannot read secrets.age"

exit 0
