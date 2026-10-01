#!/usr/bin/env bash
# Installs the pre-commit secret scan.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
[[ -d .git ]] || { echo "install-hooks: $PWD is not a git repository" >&2; exit 1; }

mkdir -p .git/hooks
cat > .git/hooks/pre-commit <<'HOOK'
#!/usr/bin/env bash
# Installed by scripts/install-hooks.sh.
#
# Scans what is about to be committed -- the index, not the working tree, since
# the working tree holds real values on purpose. Fails closed: if the scanner
# cannot run, the commit is refused rather than allowed through unchecked.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
redact="$root/bin/redact"

if [[ ! -x $redact ]]; then
  echo "pre-commit: $redact is missing or not executable" >&2
  echo "pre-commit: refusing to commit without a secret scan" >&2
  exit 1
fi

exec "$redact" check --staged "$root"
HOOK

chmod +x .git/hooks/pre-commit
echo "pre-commit hook installed (runs bin/redact check --staged)"
