#!/usr/bin/env bash
# MIT License - Copyright (c) 2026 Marl Scot
#
# Tests for pkg-install. Package managers are stubs on a private PATH that log
# their calls, so nothing is ever installed.
set -uo pipefail

ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fails=0
SETSID=$(command -v setsid)   # runs with no controlling terminal, so /dev/tty fails

check() {   # check NAME EXPECTED ACTUAL
    if [[ $2 == "$3" ]]; then echo "ok   - $1"
    else echo "FAIL - $1: expected [$2] got [$3]"; fails=$((fails + 1)); fi
}

# stubs MANAGER...: make a bin dir holding just these managers (plus the
# coreutils the script needs), print its path.
# Stubs log "name args" to $STUB_LOG. A package counts as installed when it
# appears in $STUB_INSTALLED (space separated); "install" adds to that list
# via $WORK/installed so the post-install check can see it.
stubs() {
    local dir; dir=$(mktemp -d "$WORK/bin.XXXX")
    local tool
    for tool in bash cat sed env; do ln -s "$(command -v "$tool")" "$dir/$tool"; done
    local manager query
    for manager in "$@"; do
        case $manager in
            apt) manager=apt-get; query=dpkg-query ;;
            dnf|yum|zypper) query=rpm ;;
            *) query='' ;;
        esac
        cat >"$dir/$manager" <<'STUB'
#!/usr/bin/env bash
echo "${0##*/} $*" >>"$STUB_LOG"
case " $* " in
    *" install "*|*" add "*|*" -S "*) [[ ${STUB_FAIL-} == 1 ]] && exit 1
        echo "${@: -1}" >>"$STUB_STATE" ;;
esac
# pacman -Q / apk info -e / brew list --versions: query mode
case "$1 $2" in
    "-Q "*|"info -e"|"list --versions")
        pkg=${@: -1}
        [[ " $STUB_INSTALLED $(cat "$STUB_STATE" 2>/dev/null) " == *" $pkg "* ]] || exit 1
        [[ $1 == list ]] && echo "$pkg 1.0" ;;
esac
exit 0
STUB
        chmod +x "$dir/$manager"
        if [[ -n $query ]]; then
            cat >"$dir/$query" <<'STUB'
#!/usr/bin/env bash
pkg=${@: -1}
[[ " $STUB_INSTALLED $(cat "$STUB_STATE" 2>/dev/null) " == *" $pkg "* ]] || exit 1
[[ ${0##*/} == dpkg-query ]] && printf 'install ok installed'
exit 0
STUB
            chmod +x "$dir/$query"
        fi
    done
    printf '#!/usr/bin/env bash\necho "sudo $*" >>"$STUB_LOG"\nexec "$@"\n' >"$dir/sudo"
    chmod +x "$dir/sudo"
    printf '%s\n' "$dir"
}

# run BIN [args...]: run pkg-install on PATH=BIN with no terminal, print
# "status output" on one line, then the logged calls.
run() {
    local bin=$1; shift
    : >"$WORK/log"; : >"$WORK/state"
    local out status
    out=$("$SETSID" env -i HOME="$WORK/home" PATH="$bin" STUB_LOG="$WORK/log" STUB_STATE="$WORK/state" \
        STUB_INSTALLED="${STUB_INSTALLED-}" STUB_FAIL="${STUB_FAIL-}" \
        PKG_INSTALL_MAP="${PKG_INSTALL_MAP-/nonexistent}" \
        bash "$ROOT/pkg-install" "$@" 2>&1 </dev/null)
    status=$?
    printf '%s %s' "$status" "$(tr '\n' '|' <<<"$out")"
}

APT=$(stubs apt)
check "detects apt" "0 apt|" "$(run "$APT" --print-manager)"
check "prefers dnf over yum" "0 dnf|" "$(run "$(stubs yum dnf)" --print-manager)"
check "brew comes after system managers" "0 pacman|" "$(run "$(stubs brew pacman)" --print-manager)"
check "no manager" "3 pkg-install: no supported package manager found (looked for: apt dnf yum zypper pacman apk brew)|" \
    "$(run "$(stubs)" --print-manager)"
check "unknown manager rejected" 2 "$(run "$APT" -m foo tmux | cut -c1)"

# --- name mapping --------------------------------------------------------------
check "unmapped name unchanged" "0 tmux|" "$(run "$APT" --print-name tmux)"
check "mapped name (apt)" "0 dnsutils|fd-find|" "$(run "$APT" --print-name dig fd)"
check "mapped name (pacman)" "0 openbsd-netcat|" "$(run "$APT" -m pacman --print-name nc)"
printf '# mine\ntmux  apt=tmux-next\nfd apt=fdclone\n' >"$WORK/my.map"
check "user map adds and overrides" "0 tmux-next|fdclone|" \
    "$(PKG_INSTALL_MAP=$WORK/my.map run "$APT" --print-name tmux fd)"
check "unavailable package" "4 pkg-install: not available via brew: pip|" \
    "$(run "$(stubs brew)" --yes pip)"

# --- check / install -------------------------------------------------------------
check "--check: installed" "0 |" "$(STUB_INSTALLED=tmux run "$APT" --check tmux)"
check "--check: missing" "1 not installed: dnsutils|" "$(STUB_INSTALLED=tmux run "$APT" --check tmux dig)"
check "already installed: nothing run" "0 already installed: tmux|" \
    "$(STUB_INSTALLED=tmux run "$APT" --yes tmux; tr '\n' ';' <"$WORK/log")"
check "--dry-run prints sudo commands" \
    "0 sudo apt-get update -qq|sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y tmux|" \
    "$(run "$APT" --dry-run tmux)"
check "no terminal and no --yes: refuses" \
    "1 pkg-install: not installed: tmux (no terminal to ask; re-run with --yes)|" \
    "$(run "$APT" tmux; tr '\n' ';' <"$WORK/log")"
check "--yes installs via sudo" \
    "sudo apt-get update -qq;apt-get update -qq;sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y tmux;apt-get install -y tmux;" \
    "$(run "$APT" --yes tmux >/dev/null; tr '\n' ';' <"$WORK/log")"
check "--yes reports success" "|installed: tmux|" "$(run "$APT" --yes tmux | grep -o '|installed: tmux|')"
check "brew: no sudo" "brew install tmux;" \
    "$(run "$(stubs brew)" --yes tmux >/dev/null; grep -v '^brew list' "$WORK/log" | tr '\n' ';')"
check "pacman install command" "pacman -S --needed --noconfirm tmux;" \
    "$(run "$(stubs pacman)" --yes tmux >/dev/null; grep -v -e '^sudo' -e '-Q' "$WORK/log" | tr '\n' ';')"
check "install failure" 4 "$(STUB_FAIL=1 run "$APT" --yes tmux | cut -c1)"

check "--version" "0 pkg-install 0.1.0|" "$(run "$APT" --version)"
check "--help shows usage" 1 "$(run "$APT" --help | grep -c 'Usage: pkg-install')"
check "passes bash -n" 0 "$(bash -n "$ROOT/pkg-install"; echo $?)"

echo
if (( fails )); then echo "$fails test(s) failed"; exit 1; fi
echo "all tests passed"
