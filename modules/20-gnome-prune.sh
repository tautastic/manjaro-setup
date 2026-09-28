#!/usr/bin/env bash
# Strip a stock Manjaro gnome-minimal install back to the surface this setup
# wants. See packages/remove.txt and packages/manjaro-remove.txt for what goes
# and why.

mapfile -t wanted_gone < <(read_pkg_list "$ROOT/packages/remove.txt"; read_pkg_list "$ROOT/packages/manjaro-remove.txt")
mapfile -t protected   < <(read_pkg_list "$ROOT/packages/protect.txt")

# Only consider packages that are actually installed.
present=()
for p in "${wanted_gone[@]}"; do
  pkg_installed "$p" && present+=("$p")
done

if [[ ${#present[@]} -eq 0 ]]; then
  ok "Nothing to remove -- already pruned"
  return 0 2>/dev/null || exit 0
fi

log "${#present[@]} of ${#wanted_gone[@]} listed packages are installed"

# Anything we intend to keep is marked explicitly installed first. Packages
# pulled in as dependencies of something being removed would otherwise become
# orphans and be swept away -- zsh is the obvious casualty, since it arrives as
# a dependency of manjaro-zsh-config.
log "Marking the keep set as explicitly installed"
keep=()
for f in repo.txt gnome-core.txt protect.txt; do
  while read -r k; do
    pkg_installed "$k" && keep+=("$k")
  done < <(read_pkg_list "$ROOT/packages/$f")
done
if [[ ${#keep[@]} -gt 0 ]]; then
  if [[ $DRY_RUN == true ]]; then
    printf '%s would run:%s pacman -D --asexplicit (%s packages)\n' "$DIM" "$RST" "${#keep[@]}"
  else
    sudo pacman -D --asexplicit "${keep[@]}" >/dev/null 2>&1 \
      && ok "${#keep[@]} packages marked explicit" \
      || warn "could not mark the keep set explicit"
  fi
fi

is_protected() {
  local candidate=$1 p
  for p in "${protected[@]}"; do
    [[ $candidate == "$p" ]] && return 0
  done
  return 1
}

# Ask pacman what the full removal set would be, including -s cascade and -n
# config files. Returns 1 if the set cannot be removed as a whole.
# `--nosave` and `--print` are mutually exclusive, so `-Rns --print` always
# errored out and produced nothing -- which made every package look unremovable
# and silently disabled the whole guard. `-Rs --print` gives the same removal
# set; --nosave only affects whether config files are backed up on the real run.
# It reads the local database only, so it needs no root and works in a dry run.
# Deliberately -R, not -Rs. Recursing into now-unneeded dependencies is far too
# blunt here: manjaro-zsh-config pulls in zsh, zsh-completions,
# zsh-syntax-highlighting and powerlevel10k as dependencies, so -Rs proposes
# removing the login shell along with it. Remove exactly what is listed, and let
# the guarded orphan sweep below deal with genuine leftovers.
preview_removal() {
  pacman -R --print --print-format '%n' "$@" 2>/dev/null
}

check_cascade() {
  local cascade=("$@") victim hits=()
  for victim in "${cascade[@]}"; do
    is_protected "$victim" && hits+=("$victim")
  done
  if [[ ${#hits[@]} -gt 0 ]]; then
    printf '%s\n' "${hits[@]}"
    return 1
  fi
  return 0
}

batch=()
if mapfile -t batch < <(preview_removal "${present[@]}") && [[ ${#batch[@]} -gt 0 ]]; then
  log "pacman would remove ${#batch[@]} packages:"
  printf '%s\n' "${batch[@]}" | sort | column -c "${COLUMNS:-100}" 2>/dev/null \
    || printf '     %s\n' "${batch[@]}"

  if ! protected_hits=$(check_cascade "${batch[@]}"); then
    die "removal would cascade into protected packages:
$(printf '  - %s\n' $protected_hits)
Nothing was removed. Adjust packages/remove.txt or packages/protect.txt."
  fi
  ok "No protected package is in the cascade"

  if [[ $DRY_RUN == true ]]; then
    skip "dry run -- stopping before the actual removal"
    return 0 2>/dev/null || exit 0
  fi
  run sudo pacman -Rns --noconfirm "${present[@]}"
else
  # At least one package is a hard dependency of something we keep, so the
  # batch cannot be removed atomically. Fall back to one at a time and report
  # what had to stay rather than failing the whole run.
  warn "Some packages cannot be removed as a batch; falling back to one at a time"
  kept=()
  for p in "${present[@]}"; do
    if ! mapfile -t one < <(preview_removal "$p") || [[ ${#one[@]} -eq 0 ]]; then
      kept+=("$p"); continue
    fi
    if ! protected_hits=$(check_cascade "${one[@]}"); then
      warn "keeping $p -- removing it would take out: $(printf '%s ' $protected_hits)"
      kept+=("$p"); continue
    fi
    if [[ $DRY_RUN == true ]]; then
      printf '%s would remove:%s %s\n' "$DIM" "$RST" "${one[*]}"
    else
      sudo pacman -Rns --noconfirm "$p" >/dev/null 2>&1 \
        && ok "removed $p" \
        || { warn "keeping $p -- pacman refused"; kept+=("$p"); }
    fi
  done
  [[ ${#kept[@]} -gt 0 ]] && warn "Left installed: ${kept[*]}"
fi

[[ $DRY_RUN == true ]] && { return 0 2>/dev/null || exit 0; }

log "Sweeping orphaned dependencies"
orphans=$(pacman -Qdtq || true)
if [[ -n $orphans ]]; then
  if ! protected_hits=$(check_cascade $orphans); then
    warn "skipping orphan sweep -- it would remove: $(printf '%s ' $protected_hits)"
  else
    printf '%s\n' "$orphans" | sed 's/^/     /'
    sudo pacman -Rns --noconfirm $orphans
  fi
else
  skip "no orphans"
fi
