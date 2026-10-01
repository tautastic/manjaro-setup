# shellcheck shell=bash

[[ -n ${ROOT:-} ]] || { echo "bootstrap: ROOT is not set" >&2; exit 2; }
export ROOT

# shellcheck source=/dev/null
source "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$ROOT/lib/packages.sh"
# shellcheck source=/dev/null
source "$ROOT/config.sh"

[[ $EUID -eq 0 ]] && die "run this as your normal user; it calls sudo where it needs to"
[[ -n ${TARGET_HOME:-} && -d $TARGET_HOME ]] || die "could not resolve the home directory of $TARGET_USER"
assert_hydrated
