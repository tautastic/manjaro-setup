# shellcheck shell=bash

_keep_patterns() { read_pkg_list "$ROOT/packages/keep.txt"; }

_auto_protected() {
  local g
  for g in base base-devel; do
    pacman -Qqg "$g" 2>/dev/null || true
  done
}

is_protected() {
  local name=$1 pat
  while IFS= read -r pat; do
    [[ -z $pat ]] && continue
    # shellcheck disable=SC2053
    [[ $name == $pat ]] && return 0
  done < <(_keep_patterns)
  _auto_protected | grep -qxF "$name"
}

want_repo() { read_pkg_list "$ROOT/packages/want.txt" | sort -u; }
want_aur()  { read_pkg_list "$ROOT/packages/aur.txt"  | sort -u; }
want_all()  { { want_repo; want_aur; } | sort -u; }

explicit_now() { pacman -Qqe 2>/dev/null | sort -u; }

install_missing() {
  local missing repo=() aur=() p
  missing=$(comm -23 <(want_all) <(explicit_now))
  if [[ -z $missing ]]; then
    skip "every wanted package is already installed"
    return 0
  fi
  while IFS= read -r p; do
    [[ -z $p ]] && continue
    if want_aur | grep -qxF "$p"; then aur+=("$p"); else repo+=("$p"); fi
  done <<< "$missing"
  [[ ${#repo[@]} -gt 0 ]] && pkg_install "${repo[@]}"
  [[ ${#aur[@]} -gt 0 ]] && aur_install "${aur[@]}"
  return 0
}

report_extraneous() {
  local extra
  extra=$(comm -13 <(want_all) <(explicit_now))
  [[ -z $extra ]] && { skip "nothing installed that the manifest does not list"; return 0; }
  printf '%s\n' "$extra"
}

prune_extraneous() {
  [[ -n $(_auto_protected) ]] \
    || die "pacman -Qqg base returned nothing, so the automatic protection of essential packages is not working -- refusing to prune"
  local extra demote=() protected=() p removal
  extra=$(report_extraneous)
  [[ -z $extra ]] && return 0

  while IFS= read -r p; do
    [[ -z $p ]] && continue
    if is_protected "$p"; then protected+=("$p"); else demote+=("$p"); fi
  done <<< "$extra"

  [[ ${#protected[@]} -gt 0 ]] && {
    log "keeping ${#protected[@]} guarded package(s):"
    printf '       %s\n' "${protected[@]}"
  }
  [[ ${#demote[@]} -eq 0 ]] && { skip "nothing to prune"; return 0; }

  log "${#demote[@]} package(s) are installed explicitly but not wanted:"
  printf '       %s\n' "${demote[@]}"

  run sudo pacman -D --asdeps "${demote[@]}"

  sweep_orphans
}

sweep_orphans() {
  local round=0 orphans hits p removal
  while (( round < 5 )); do
    round=$((round + 1))
    mapfile -t orphans < <(pacman -Qdtq 2>/dev/null || true)
    [[ ${#orphans[@]} -eq 0 ]] && { skip "no orphans left"; return 0; }

    removal=$(pacman -Rns --print --print-format '%n' "${orphans[@]}" 2>/dev/null || true)
    if [[ -z $removal ]]; then
      warn "pacman would not remove ${orphans[*]}; stopping the sweep"
      return 0
    fi

    hits=()
    while IFS= read -r p; do
      [[ -z $p ]] && continue
      is_protected "$p" && hits+=("$p")
    done <<< "$removal"
    if [[ ${#hits[@]} -gt 0 ]]; then
      warn "refusing the sweep: it would remove guarded package(s): ${hits[*]}"
      warn "add whatever pulled them in to packages/want.txt, or relax packages/keep.txt"
      return 1
    fi

    log "round $round would remove $(printf '%s\n' "$removal" | grep -c .) package(s):"
    printf '%s\n' "$removal" | sed 's/^/       /'

    if [[ $DRY_RUN == true ]]; then
      skip "dry run -- stopping before the removal"
      return 0
    fi
    confirm "Remove them?" || { warn "left installed"; return 0; }
    run sudo pacman -Rns --noconfirm "${orphans[@]}"
  done
  warn "orphan sweep did not settle after $round rounds"
  return 0
}
