#!/usr/bin/env bash
# Render the git identity files and the p10k prompt table from the identity
# table in config.sh.
# Writes into dotfiles/ so 50-dotfiles.sh can symlink them like everything else.

GIT_PKG="$ROOT/dotfiles/git/.config/git"
ZSH_PKG="$ROOT/dotfiles/zsh/.config/zsh"
mkdir -p "$GIT_PKG/identities"

ssh_command_for() { printf 'ssh -i %s/.ssh/%s -o IdentitiesOnly=yes' "$TARGET_HOME" "$1"; }

default_email=""; default_key=""
missing_keys=()

for entry in "${GIT_IDENTITIES[@]}"; do
  IFS='|' read -r name email key color <<<"$entry"
  cat <<IDENT | write_user_file "$GIT_PKG/identities/$name" 644
[user]
	name = $name
	email = $email

[core]
	sshCommand = "$(ssh_command_for "$key")"
IDENT
  if [[ $name == "$GIT_DEFAULT_IDENTITY" ]]; then
    default_email=$email; default_key=$key
  fi
  [[ -f "$TARGET_HOME/.ssh/$key" ]] || missing_keys+=("$key")
done

[[ -n $default_email ]] || die "GIT_DEFAULT_IDENTITY '$GIT_DEFAULT_IDENTITY' is not in GIT_IDENTITIES"

cat <<GITCFG | write_user_file "$GIT_PKG/config" 644
[core]
	sshCommand = "$(ssh_command_for "$default_key")"

[init]
	defaultBranch = "main"

[user]
	email = "$default_email"
	name = "$GIT_DEFAULT_IDENTITY"
GITCFG

# The three lookup tables prompt.zsh reads, followed by prompt.zsh itself.
{
  printf 'typeset -gA _git_identity_name _git_identity_key _git_identity_color\n\n'
  printf '_git_identity_name=(\n'
  for entry in "${GIT_IDENTITIES[@]}"; do
    IFS='|' read -r name email key color <<<"$entry"
    printf '  %s %s\n' "$email" "$name"
  done
  printf ')\n\n_git_identity_key=(\n'
  for entry in "${GIT_IDENTITIES[@]}"; do
    IFS='|' read -r name email key color <<<"$entry"
    printf '  %s %s/.ssh/%s\n' "$name" "$TARGET_HOME" "$key"
  done
  printf ')\n\n_git_identity_color=(\n'
  for entry in "${GIT_IDENTITIES[@]}"; do
    IFS='|' read -r name email key color <<<"$entry"
    printf '  %s %s\n' "$name" "$color"
  done
  printf ')\n\n'
  cat "$ROOT/src/prompt.zsh"
} | write_user_file "$ZSH_PKG/git-identity.zsh" 644

if [[ ${#missing_keys[@]} -gt 0 ]]; then
  warn "SSH keys not found under $TARGET_HOME/.ssh:"
  printf '       %s\n' "${missing_keys[@]}" >&2
  warn "Copy them over from the old machine; git pushes will fail until you do."
fi
