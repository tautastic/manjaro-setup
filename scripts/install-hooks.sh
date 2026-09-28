#!/usr/bin/env bash
# Install the pre-commit hook that runs `redact check --staged`.
#
# Nothing here is specific to this repo: it locates redact inside the working
# tree if it is vendored here, and otherwise leaves the hook to find it on
# PATH. Safe to run again at any time.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
[[ -d .git ]] || { echo "install-hooks: $PWD is not a git repository" >&2; exit 1; }

# Where redact lives inside this repo, if it is vendored at all.
vendored=$(find . -type f -name redact -perm -u+x -not -path './.git/*' -print -quit 2>/dev/null || true)
vendored=${vendored#./}

mkdir -p .git/hooks
{
  cat <<'HEAD'
#!/usr/bin/env bash
# Installed by scripts/install-hooks.sh.
# Blocks any commit containing a secret or identifying value.
# Fails closed: if the scanner cannot run the commit is refused, rather than
# allowed through unchecked.
set -euo pipefail

root=$(git rev-parse --show-toplevel)

if command -v redact >/dev/null 2>&1; then
  exec redact check --staged "$root"
fi
HEAD

  if [[ -n $vendored ]]; then
    cat <<HERE

if [[ -x \$root/$vendored ]]; then
  exec "\$root/$vendored" check --staged "\$root"
fi
HERE
  fi

  cat <<'TAIL'

if [[ -x $HOME/.local/bin/redact ]]; then
  exec "$HOME/.local/bin/redact" check --staged "$root"
fi

echo "pre-commit: redact not found on PATH or in this repo" >&2
echo "pre-commit: refusing to commit without a secret scan" >&2
exit 1
TAIL
} > .git/hooks/pre-commit

chmod +x .git/hooks/pre-commit
echo "pre-commit hook installed${vendored:+ (repo copy: $vendored)}"
