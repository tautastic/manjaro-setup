# manjaro-setup

A re-runnable installer that turns a clean **Manjaro `gnome-minimal`** install
into a deliberately minimal desktop: GDM on Wayland, GNOME stripped back to the
handful of apps I actually use, and a zsh / powerlevel10k / kitty / vis / yazi /
zathura / librewolf setup.

Package management is **pacman + yay**.

## Usage

```sh
git clone <this repo> ~/.config/manjaro-setup
cd ~/.config/manjaro-setup

sudo pacman -S age                        # redact needs it
cp /path/to/key.txt ~/.config/age/        # carried from the old machine
./bin/redact hydrate  # fills config.local.sh

./install.sh --dry-run                    # read this before the real run
./install.sh
reboot
```

`redact` ships in this repo at `bin/redact`, so the first hydrate runs it by
path. Module `35-local-bin` then symlinks everything in `bin/` into
`~/.local/bin`, after which it is on `$PATH` as plain `redact`.

Without the age key, `redact hydrate` prompts for each `@@<NAME>@@` and saves the
answers, so a from-scratch setup works too. `install.sh` refuses to run while
`config.local.sh` is missing rather than silently installing the placeholder
identities from `config.sh`.

### Real values vs. committed values

This repo is public, so `config.sh` ships placeholder identities
(`gituser1`, `gituser2`) and a generic hostname. Real names, emails and key
filenames live in **`secrets.age`** -- committed, but encrypted to the age key
at `~/.config/age/key.txt`. `redact hydrate` decrypts it and fills
`config.local.sh.tmpl` into `config.local.sh`, which is gitignored and sourced
at the end of `config.sh`, overriding anything it sets.

On a machine without the key, `redact hydrate` prompts for each `@@<NAME>@@` and
saves the answers, so first-run doubles as guided setup.

The three files `45-identities` generates from that table --
`dotfiles/git/.config/git/config`, `dotfiles/git/.config/git/identities/*` and
`dotfiles/zsh/.config/zsh/git-identity.zsh` -- are gitignored for the same
reason. They are produced at install time, so a fresh clone does not need them.

`redact check` enforces this. Its deny list *is* the map, so it needs no
separate maintenance -- every value with a token is by definition something that
must not appear in the clear. It also catches structural secrets the map cannot
know about: password hashes, private keys, hardware UUIDs, public IPs, real
email addresses and hardcoded `/home/<user>` paths. Install it as a pre-commit
hook with `scripts/install-hooks.sh`:

```sh
redact check             # tracked + untracked files
redact check --staged    # what is about to be committed
redact check --history   # every commit
```

`.redactignore` lists paths exempt from scanning (vendored upstream code).

Run it as your normal user, not with sudo — it calls sudo where it needs to.

Every module is idempotent: re-running a finished install changes nothing and
exits 0. That makes `./install.sh` the way to re-apply the config after editing
it.

```sh
./install.sh --list                # what the modules are
./install.sh --only 20-gnome-prune # run one
./install.sh --skip 10-nvidia      # run everything but one
```

## Layout

| Path | What |
|---|---|
| `install.sh` | Orchestrator. Runs each module in its own subshell, stops at the first failure. |
| `config.sh` | Hostname, timezone, locales, keyboard, git identities, stow package list. |
| `lib/common.sh` | Logging, `pkg_install` / `aur_install`, `write_file`, `regen_grub`, dry-run plumbing. |
| `modules/` | Numbered, idempotent steps. |
| `packages/` | Plain-text manifests: what to install, what to remove, what must never be removed. |
| `dconf/gnome.ini` | All the GNOME settings, as a `dconf load /` keyfile. |
| `dotfiles/` | One GNU stow package per app, symlinked into `$HOME`. |
| `src/` | Source material the modules render: currently `prompt.zsh`. |
| `scripts/` | The pre-commit hook installer. |
| `bin/` | Standalone scripts linked onto `$PATH` by `35-local-bin`. |
| `secrets.age` | The token -> real value map, age-encrypted. Committed. |
| `config.local.sh` | Hydrated from the template. Gitignored, sourced by `config.sh`. |

### Modules

| Module | Does |
|---|---|
| `00-base` | pacman.conf (color, parallel downloads, `[multilib]`), `yay`, the base + CLI + GUI package set. |
| `05-locale` | `Europe/Berlin`, `en_US.UTF-8` with nine `de_DE.UTF-8` `LC_*` categories, `KEYMAP=us`, X keyboard, hostname. |
| `10-nvidia` | `mhwd -a pci nonfree 0300`, `opencl-nvidia`, `lib32-nvidia-utils`, `nvidia_drm.modeset=1`, early KMS in mkinitcpio, the suspend/resume services. |
| `15-boot-menu` | Makes GRUB chainload the Windows install on the other drive. |
| `20-gnome-prune` | Removes GNOME core apps, developer tools, games, and Manjaro's additions — with a dependency guard, see below. |
| `22-manjaro-cleanup` | The files those packages leave behind: shell rc files, system dconf defaults, gsettings overrides, autostart entries. |
| `25-gnome-core` | Reinstates/holds the GNOME set that stays, plus pipewire, bluez, portals. |
| `30-packages` | The AUR half of the package set, then `fc-cache`. |
| `35-local-bin` | Symlinks `bin/` into `~/.local/bin`. |
| `40-services` | Docker (rootful **and** rootless), sshd hardening, firewall left off. |
| `45-identities` | Renders the git identity files and the p10k prompt table from `config.sh`. |
| `50-dotfiles` | Backs up colliding files, then `stow --restow` everything. |
| `60-dconf` | Backs up the current dconf database, then loads `dconf/gnome.ini`. |
| `70-shell` | `chsh` to zsh. |

## Design notes

**Dotfiles are checked in as finished files**, not generated from a higher-level
config. `dotfiles/` holds exactly what lands in `$HOME`, so what you read is what
runs. The only generated files are the git identity artifacts, which come from
the identity table (see above).

**Vendored, so first run needs no network**: the `full-border` yazi plugin, the
`flexoki-dark` yazi flavor, and kitty's `Earthsong` theme all live in the repo
rather than being fetched.

**Toolchains are global.** `gcc`, `make`, `go`, `node`, `pnpm` and `biome` are
installed system-wide rather than per-project. `~/.local/care` and the `lcar`
bookmark are scratch space for throwaway projects.

**Deliberately absent**: PostgreSQL, JetBrains IDEs, and `xdot` — which means
the yazi `*.dot` opener rule and the `text/vnd.graphviz` line in `mimeapps.list`
are inert. `pacman -S xdot` fixes that if it ever matters.

## The removal guard

`20-gnome-prune` will not blindly `pacman -Rns` a 90-package list. It:

1. Intersects the manifests with what is actually installed.
2. Asks pacman for the full removal set with `--print`, including cascades.
3. Aborts if anything in `packages/protect.txt` appears in that set, printing
   what pulled it in. Nothing is removed.
4. Falls back to removing one package at a time, skipping and reporting any that
   pacman refuses, when the batch cannot be removed atomically.
5. Sweeps orphans with the same guard.

`./install.sh --only 20-gnome-prune --dry-run` stops after step 3, so the removal
set can be reviewed before it happens.

## Windows on the other drive

Windows has its own disk with its own EFI System Partition. `15-boot-menu`:

1. Sets `GRUB_DISABLE_OS_PROBER=false` and forces a visible menu.
2. Runs `os-prober`.
3. If os-prober misses it — the usual outcome when the other ESP is never
   mounted — mounts every FAT partition read-only, looks for
   `EFI/Microsoft/Boot/bootmgfw.efi`, and writes an explicit chainloader entry
   into `/etc/grub.d/40_custom` keyed on that partition's filesystem UUID.
4. Regenerates `grub.cfg` and verifies a Windows entry landed in it.

If the entry is missing, check the Windows disk is connected and re-run
`./install.sh --only 15-boot-menu`.

**Clock skew:** Linux keeps the RTC in UTC, Windows uses local time, so the clock
jumps by the UTC offset on every switch. Preferred fix, in an elevated Windows
command prompt:

```
reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f
```

Or set `RTC_LOCAL_TIME=true` in `config.sh` to make Linux match Windows instead.

## Things the script cannot do for you

- **SSH keys.** The key files named in `secrets.age` have to be copied from
  the old machine into `~/.ssh`. `45-identities` warns when they are missing;
  git pushes fail until they are there.
- **`~/.ssh/config`.** Not managed here on purpose: it names real hosts, and this
  repo is public. Copy it over with the keys.
- **Disk layout.** LUKS + btrfs subvolumes are a Calamares decision at install
  time, before this script runs.
- **Anki collection, LibreWolf profile data.**

## Editing afterwards

Dotfiles are symlinks into this repo, so editing `~/.config/kitty/kitty.conf`
edits `dotfiles/kitty/.config/kitty/kitty.conf` and `git status` shows the drift.
The `cf*` bookmarks in `dotfiles/zsh/.config/zsh/bookmarks.zsh` jump straight to
the repo copies.

Changing GNOME settings through the UI writes to the live dconf database, not to
`dconf/gnome.ini`. To capture them: `dconf dump / > /tmp/now.ini`, diff, and fold
the wanted keys back in by hand.
