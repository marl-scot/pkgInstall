# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org/).

## [0.1.0] - 2026-11-05

### Added

- `pkg-install`: installs packages with the native package manager (apt,
  dnf, yum, zypper, pacman, apk, brew), detecting which one the system uses.
- Generic package names are translated per manager by a built-in table, and
  by an optional user map (`~/.config/pkg-install/packages.map`).
- Asks before installing (on the terminal, so it works piped over ssh), uses
  sudo when not root, and checks the package is installed afterwards.
- `--yes`, `--dry-run`, `--check`, `--manager`, `--print-manager`,
  `--print-name`.
