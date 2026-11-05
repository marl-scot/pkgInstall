# pkgInstall

`pkg-install` installs packages with whatever native package manager the
system uses, so scripts can say "make sure `tmux` is installed" once instead of
carrying a `case` for every distribution. It also translates package names that
differ between managers (`dig` is `dnsutils` on apt, `bind-utils` on dnf).

It's one self-contained bash script with no dependencies, so it can be piped
to a host that doesn't have it.

## Usage

```bash
pkg-install tmux              # asks "Install tmux with apt? [y/N]", then installs
pkg-install --yes tmux git    # no question
pkg-install --check tmux      # exit 0 if installed, 1 if not; installs nothing
pkg-install --dry-run dig     # print the commands: sudo apt-get install -y dnsutils
pkg-install --print-manager   # apt
pkg-install --print-name nc   # netcat-openbsd (on apt)
pkg-install -m pacman --print-name nc   # openbsd-netcat
```

Piped over ssh to a host without it:

```bash
ssh -t HOST 'bash -s -- tmux' < pkg-install       # -t so it can ask
ssh HOST 'bash -s -- --yes tmux' < pkg-install    # no terminal: needs --yes
```

| Exit | Meaning |
|---|---|
| 0 | installed, or already installed |
| 1 | not installed: `--check` found it missing, or you declined |
| 2 | usage error |
| 3 | no supported package manager |
| 4 | install failed, or the package isn't available for this manager |

## How it works

1. **Detect the manager.** The first of `apt-get`, `dnf`, `yum`, `zypper`,
   `pacman`, `apk`, `brew` on `PATH`. On macOS only `brew` is considered;
   elsewhere it comes last, so a Linuxbrew install doesn't take over from the
   system manager. `--manager` overrides this.
2. **Translate names.** Each name is looked up in the built-in table, then in
   the user map. Unlisted names are used unchanged.
3. **Skip what's installed**, checked with the manager's own database
   (`dpkg-query`, `rpm -q`, `pacman -Q`, `apk info -e`, `brew list`).
4. **Ask**, reading the answer from `/dev/tty` rather than stdin, because piped
   over ssh stdin is the script. With no terminal it refuses unless `--yes`.
5. **Install** non-interactively, through `sudo` when not root (except brew,
   which refuses root). apt runs `apt-get update` first.
6. **Verify** each package is now installed.

## Package-name map

Lines are `generic-name manager=name ...`; `#` starts a comment line, and a
name of `-` means "not available for this manager":

```
dig   apt=dnsutils dnf=bind-utils yum=bind-utils pacman=bind apk=bind-tools brew=bind
pip   apt=python3-pip pacman=python-pip apk=py3-pip brew=-
```

The built-in table is `builtin_map` in `pkg-install`. Add your own entries in
`~/.config/pkg-install/packages.map` (or the file named by
`$PKG_INSTALL_MAP`); they are read after the built-in table, so they win. Send
generally useful entries back to the built-in table.

## Installation

```bash
git clone https://github.com/marl-scot/pkgInstall.git
ln -s "$PWD/pkgInstall/pkg-install" ~/.local/bin/pkg-install
```

Or copy just the script: `install -m755 pkg-install ~/.local/bin/`.

Used by [tmuxTerminal](https://github.com/marl-scot/tmuxTerminal)'s installer to
install tmux when it's missing.

## Tests

```bash
tests/run.sh
```

The package managers, `sudo` and the package databases are stubs on a private
`PATH`, so nothing is installed. Runs with no controlling terminal, to cover the
"can't ask" path.

## Licence

MIT, see [LICENSE](LICENSE).
