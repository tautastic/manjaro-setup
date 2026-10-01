# manjaro-setup

A re-runnable installer that turns a clean **Manjaro `gnome-minimal`** install
into a deliberately minimal desktop: GDM on Wayland, GNOME stripped back to the
handful of apps I actually use, and a zsh / powerlevel10k / kitty / vis / yazi /
zathura / librewolf setup.

Package management is **pacman + yay**.

The repo is public and nothing identifying is committed: the one file that holds
private values is committed **tokenised** and hydrated in place on the machine.

## From a clean install

Order of operations, starting from a Manjaro live ISO:

1. `scripts/partition-disk.sh` — lay down the partition table (see **The disk
   layout** below).
2. Calamares — installs Manjaro onto it, creating the LUKS container and btrfs.
3. Everything below — run from the installed system, as the user the config
   expects.

```sh
git clone <this repo> ~/.config/manjaro-setup
cd ~/.config/manjaro-setup

sudo pacman -S age                 # redact needs it
cp /path/to/key.txt ~/.config/age/ # carried from the old machine
./bin/redact hydrate               # fills config.local.sh and pins it
./scripts/install-hooks.sh         # pre-commit secret scan

./install.sh --dry-run             # read this before the real run
./install.sh
reboot
```

Without the age key, `redact hydrate` prompts for each `@@<NAME>@@` and saves the
answer, so a from-scratch setup works too. Until it has run, every module stops
with a message naming the tokens that are still placeholders — there are
deliberately no placeholder identities in `config.sh` to fall back on.

```sh
./install.sh --list                 # what the modules are
./install.sh --only 60-dconf        # run one (repeatable)
./install.sh --skip 10-nvidia       # run everything but one
./install.sh --upgrade              # pacman -Syu first
./install.sh --prune                # also remove packages the manifest omits
./install.sh --yes                  # do not ask before removing
./modules/60-dconf.sh               # modules are ordinary scripts
```

A typo'd module name is rejected rather than silently doing nothing. Every
module is idempotent: re-running a finished install changes nothing. Nothing
upgrades the system unless you pass `--upgrade`.

## Layout

| Path | What |
|---|---|
| `install.sh` | Orchestrator. Runs each module as its own process, stops at the first failure. |
| `config.sh` | Timezone, locales, keyboard, stow package list, hardware switches. |
| `config.local.sh` | Hostname, git identities, ssh config. Committed tokenised, hydrated in place. |
| `.redacted` | Which files carry private values. |
| `lib/` | `common.sh` (logging, `pkg_install`, `write_file`, dry-run), `packages.sh` (the reconciler), `bootstrap.sh` (what each module sources). |
| `modules/` | Numbered, idempotent, independently runnable steps. |
| `packages/` | `want.txt`, `aur.txt`, `keep.txt` — see below. |
| `dconf/gnome.ini` | All the GNOME settings, as a `dconf load` keyfile. |
| `dotfiles/` | One GNU stow package per app, symlinked into `$HOME`. |
| `src/prompt.zsh` | Source material `45-identities` renders. |
| `bin/` | `redact`, `git-identity`, `dconf-sync` — linked onto `$PATH` by `35-local-bin`. |
| `scripts/partition-disk.sh` | Creates the same disk layout the NixOS laptop uses. Run from a live ISO. |
| `secrets.age` | The token -> real value map, age-encrypted. Committed. |

### Modules

| Module | Does |
|---|---|
| `00-base` | pacman.conf (color, parallel downloads, `[multilib]`), `yay`, then reconciles the whole package set. |
| `05-locale` | `Europe/Berlin`, `en_US.UTF-8` with nine `de_DE.UTF-8` `LC_*` categories, `KEYMAP=us`, X keyboard, hostname. |
| `10-nvidia` | `mhwd -a pci nonfree 0300`, `opencl-nvidia`, `lib32-nvidia-utils`, `nvidia_drm.modeset=1`, early KMS, the suspend/resume services. |
| `15-boot-menu` | Makes GRUB chainload the Windows install on the other drive. |
| `18-swapfile` | Creates the `@swap` subvolume and the swapfile Calamares does not make. |
| `22-manjaro-cleanup` | The files removed packages leave behind: shell rc files, system dconf defaults, gsettings overrides, autostart entries. Prunes its own old backups. |
| `25-gnome-core` | Enables GDM, bluetooth and the pipewire user units; turns cups off; re-enables Wayland if something disabled it. |
| `35-local-bin` | Symlinks `bin/` into `~/.local/bin` and removes links whose target is gone. |
| `40-services` | Docker (rootful **and** rootless), subuid/subgid ranges, sshd hardening, IP forwarding, firewall left off. |
| `45-identities` | Writes `~/.config/git/config`, `~/.config/git/identities/*` and `~/.config/zsh/git-identity.zsh`. |
| `47-ssh-config` | Writes `~/.ssh/config` from `SSH_CONFIG`. |
| `50-dotfiles` | Backs up colliding files, unstows packages dropped from `STOW_PACKAGES`, then `stow --restow`. |
| `60-dconf` | Backs up the dconf database, resets the paths `gnome.ini` owns, then loads it. |
| `70-shell` | `chsh` to zsh. |

## Packages are declarative

`packages/want.txt` is the **authoritative** explicit package set from the
official repos, and `packages/aur.txt` the same for the AUR. Dependencies are
not listed — pacman tracks those.

`00-base` reconciles it:

1. Anything wanted but missing gets installed.
2. Anything installed **explicitly** that the manifest does not list is
   reported. With `--prune` it is marked as a dependency (`pacman -D --asdeps`)
   rather than removed outright, and then the orphan sweep decides what actually
   goes — so nothing still needed is taken out.
3. The sweep previews with the *same* flags it removes with (`pacman -Rns
   --print`), and aborts if anything matching `packages/keep.txt` shows up in
   that set. It asks before removing, unless `--yes`.

`keep.txt` entries are globs, and the `base` and `base-devel` groups are
protected automatically — so versioned kernels (`linux[0-9]*`), the graphics
driver `mhwd` installed (`nvidia-*`), and Manjaro's own tooling cannot be pruned
even though this repo never asks for them by name.

Pruning GNOME back to a minimal set is therefore a *consequence* of the manifest
rather than a separate list of things to remove.

## GNOME settings round-trip

`dconf load` merges, so a key deleted from `dconf/gnome.ini` would otherwise stay
set forever. `60-dconf` resets each path the file has a `[section]` for before
loading it, which makes the file authoritative.

Going the other way, `dconf-sync` folds the live database back into
`gnome.ini` — only for paths the file already manages:

```sh
dconf-sync                  # then: git diff dconf/gnome.ini
```

To start managing a new path, add an empty `[section]` for it first.

## Real values vs. committed values

`config.local.sh` is **tracked**, and what is committed is the tokenised form:

```sh
HOSTNAME_NEW="@@SYS_HOSTNAME@@"
```

`redact hydrate` rewrites those tokens in place from `secrets.age` and sets
git's `skip-worktree` bit, so the working tree holds the real values, `git
status` stays clean, and `git add -A` cannot stage them.

| command | when |
|---|---|
| `redact hydrate` | after a clone, or after changing a value in the map |
| `redact edit` | change the map itself |
| `redact stage` | tokenise the working copy into the index, ready to commit |
| `redact check [--staged\|--history]` | scan for a value that should have been tokenised |

`redact check`'s deny list *is* the map. It also catches structural secrets the
map cannot know about: password hashes, private keys, hardware UUIDs, public IPs
and real email addresses. `scripts/install-hooks.sh` installs `--staged` as a
pre-commit hook that fails closed. `.redactignore` lists vendored files that are
exempt from scanning.

Nothing is generated into the repo any more: the git identity files and
`~/.ssh/config` are written straight to `$HOME`, so a fresh clone has no
untracked build output and `redact check` can scan all of it.

## Design notes

**Dotfiles are checked in as finished files.** `dotfiles/` holds exactly what
lands in `$HOME`, so what you read is what runs.

**Vendored, so first run needs no network**: the `full-border` yazi plugin, the
`flexoki-dark` yazi flavor, and kitty's `Earthsong` theme all live in the repo.

**Toolchains are global.** `gcc`, `make` and `go` are installed system-wide
rather than per-project. Node is via `nvm`; `pnpm` and `biome` are *not*
installed here, though `.zshrc` does put `~/.local/share/pnpm/bin` on `PATH`.
`~/.local/care` and the `lcar` bookmark are scratch space.

**Deliberately absent**: PostgreSQL and `xdot` — which means the yazi `*.dot`
opener rule and the `text/vnd.graphviz` line in `mimeapps.list` are inert.
JetBrains IDEs come from `jetbrains-toolbox` (`aur.txt`), so their plugins are
managed by hand rather than declared.

## Windows on the other drive

Windows has its own disk with its own EFI System Partition. `15-boot-menu`:

1. Sets `GRUB_DISABLE_OS_PROBER=false` and forces a visible menu.
2. Runs `os-prober`.
3. If os-prober misses it — the usual outcome when the other ESP is never
   mounted — mounts every FAT partition read-only, looks for
   `EFI/Microsoft/Boot/bootmgfw.efi`, and writes an explicit chainloader entry
   into `/etc/grub.d/41_manjaro-setup-windows`, keyed on that partition's UUID.
   The stock `40_custom` is left alone.
4. Regenerates `grub.cfg` and verifies a Windows entry landed in it.

**Clock skew:** Linux keeps the RTC in UTC, Windows uses local time. Preferred
fix, in an elevated Windows command prompt:

```
reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f
```

Or set `RTC_LOCAL_TIME=true` in `config.sh` to make Linux match Windows instead.

## The disk layout

`scripts/partition-disk.sh` lays down the partition table and the two
unencrypted filesystems. Calamares does the encrypted part.

```
GPT
 p1  1 GiB   ESP,  vfat, label EFI,  name disk-main-ESP   -> /boot/efi
 p2  2 GiB   boot, ext4, label BOOT, name disk-main-boot  -> /boot
 p3  rest    left empty,             name disk-main-luks  -> / (LUKS + btrfs)
```

```sh
./scripts/partition-disk.sh --dry-run /dev/nvme0n1   # read this first
./scripts/partition-disk.sh /dev/nvme0n1
```

It erases the disk, so it asks for the device path typed out in full before
writing anything. It refuses outright if the disk carries the running root
filesystem, if anything on it is mounted, or if it finds a Windows boot manager
on it — Windows lives on the other drive.

Then in Calamares, manual partitioning:

| partition | mountpoint | what to tell Calamares |
|---|---|---|
| p1 | `/boot/efi` | keep, do not format |
| p2 | `/boot` | keep, do not format |
| p3 | `/` | **format as btrfs, tick encrypt** |

### Why p3 is left empty

An earlier version of this script created the LUKS container, the btrfs
filesystem and the `@`/`@home`/`@swap` subvolumes itself, and told Calamares to
keep everything. That cannot work. Calamares' `mount` module does:

```python
subprocess.check_call(["btrfs", "subvolume", "create", root_mount_point + s["subvolume"]])
```

unconditionally, with no existence check — so a pre-made `@` makes
`btrfs subvolume create` exit 1, which surfaces as the thoroughly unhelpful
`Bad main script file` from `/usr/lib/calamares/modules/mount/main.py`. A
pre-existing LUKS container causes a second failure before that one: Calamares
assigns it a mapper name but never opens it, then tries to mount
`/dev/mapper/cryptroot`, which does not exist.

Its defaults happen to be exactly what we want anyway:

```python
btrfs_subvolumes = [dict(mountPoint="/", subvolume="/@"), dict(mountPoint="/home", subvolume="/@home")]
```

so Calamares creates `@` and `@home`. It only adds `@swap` when it is doing the
partitioning itself, so `modules/18-swapfile` creates that subvolume and the
16 GiB swapfile after the install.

The partition table, the partition names and the two unencrypted filesystems are
still worth scripting: Calamares' manual partitioner makes exact sizes and GPT
names tedious, and those are what the rest of this repo keys off.

### Why /boot and /boot/efi sit outside the LUKS container

This is where the layout deliberately diverges from the NixOS laptop, which puts
a single large ESP at `/boot` and nothing else outside the encryption.

The two machines boot differently. NixOS uses systemd-boot, which loads the
kernel and initrd straight off the ESP; the initrd then unlocks LUKS. Manjaro
uses GRUB, which has to read the kernel and initramfs *before* anything is
unlocked, so they live on an unencrypted `/boot`. And Calamares will only offer
`/boot/efi` as a mountpoint for the ESP, so the ESP cannot double as `/boot`
here.

That costs one extra partition and leaves kernels and initramfs readable to
anyone with the disk. Everything in `/` and `/home` stays encrypted — the same
exposure any GRUB-plus-LUKS install has.

### Compression and swap

Calamares mounts `/` and `/home` with `compress=zstd:1`. The NixOS side uses
plain `compress=zstd` (level 3); both compress, and the level is a mount option
you can change in `/etc/fstab` afterwards.

`modules/18-swapfile` creates the `@swap` subvolume and a 16 GiB swapfile with
`btrfs filesystem mkswapfile`, which marks it `NOCOW` as btrfs requires. It is
not compressed — a `NOCOW` file never is. The dedicated subvolume keeps
snapshotting `@` possible later. Size comes from `SWAP_SIZE` in `config.sh`.

## The user and the hostname

The hostname is set by `05-locale` from `HOSTNAME_NEW` in `config.local.sh`, and
the account this repo configures is `EXPECTED_USER` from the same file. Both are
private values, so the committed form is tokenised (`@@SYS_HOSTNAME@@`,
`@@SYS_USER@@`) and `redact hydrate` fills them in.

Create that account in Calamares. Every module checks that the account running it
is the one the config expects, and stops with a message naming both if it is not,
so an install done under a different account fails immediately instead of
half-configuring the wrong home directory.

## Things the script cannot do for you

- **SSH keys.** The key files named in `secrets.age` have to be copied from the
  old machine into `~/.ssh`. `45-identities` warns when they are missing.
- **Anki collection, LibreWolf profile data.**

## Editing afterwards

Dotfiles are symlinks into this repo, so editing `~/.config/kitty/kitty.conf`
edits `dotfiles/kitty/.config/kitty/kitty.conf` and `git status` shows the drift.
The `cf*` bookmarks in `dotfiles/zsh/.config/zsh/bookmarks.zsh` jump to the repo
copies.
