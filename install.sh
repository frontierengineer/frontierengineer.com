#!/bin/sh
# Frontier's install command, as https://frontierengineer.com/install.sh serves it:
#
#   curl -fsSL https://frontierengineer.com/install.sh | sh                        start a new installation
#   curl -fsSL https://frontierengineer.com/install.sh | sh -s -- --join <code>    join one with its pairing code
#
# It downloads Frontier 26.11.25.0855, the build stable named when this script
# was made, for this machine; checks it against the checksum below, taken from
# stable's Channel Manifest once its signature verified; puts frontierctl in
# the Frontier Directory's bin; and runs `frontierctl install` with the
# arguments given. frontierctl then fetches stable's current build and checks
# it with the key built into it. Nothing else on the machine is changed. On a
# failure it names the step and removes what it made, so a retry starts clean.
#
# FRONTIER_HOME names the Frontier Directory (~/.frontier when not set), and
# FRONTIER_RELEASES a releases repository of your own; frontierctl reads both.
set -u

BUILD_ID='280026dae72e259750d2a3d28635e4aa1f63de6f'
VERSION='26.11.25.0855'
BUILDS='darwin-arm64 build-darwin-arm64.tar.gz 50756725d2c4542756d678b46b0cc942074b73e0897af539a7a1fa8bed2f5610 129747997
linux-amd64 build-linux-amd64.tar.gz 9dde381a621de3ab461dde157994ce8b0ba658ce24c086e0f5e8977caa385c99 137986355'
RELEASES="${FRONTIER_RELEASES:-https://github.com/frontierengineer/releases/releases/download}"

step=''
work=''
placed=''
kept=''

say() {
  printf '%s\n' "$*"
}

clean() {
  [ -n "$work" ] && rm -rf "$work"
  work=''
}

fail() {
  printf 'Frontier was not installed: %s failed: %s\n' "$step" "$1" >&2
  if [ -n "$placed" ]; then
    rm -f "$placed"
    if [ -n "$kept" ]; then mv -f "$kept" "$placed"; else rmdir "${placed%/*}" 2>/dev/null; fi
  fi
  clean
  exit 1
}

platform() {
  case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=darwin ;;
    *) fail "stable publishes no build for $(uname -s), so nothing was downloaded or run: the machines it has a build for, and their downloads, are at https://frontierengineer.com/#install" ;;
  esac
  arch="$(uname -m)"
  if [ "$os" = darwin ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then arch=arm64; fi
  case "$arch" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
  esac
  printf '%s-%s' "$os" "$arch"
}

fetch() {
  case "$RELEASES" in
    /*) cp "$RELEASES/$1" "$2" ;;
    *)
      if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --connect-timeout 30 --speed-limit 1 --speed-time 30 --progress-bar -o "$2" "$RELEASES/$1"
      elif command -v wget >/dev/null 2>&1; then
        wget -O "$2" --tries=3 --timeout=30 "$RELEASES/$1"
      else
        fail "neither curl nor wget is on this machine to download with"
      fi
      ;;
  esac
}

digest() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d ' ' -f 1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d ' ' -f 1
  else
    openssl dgst -sha256 -r "$1" | cut -d ' ' -f 1
  fi
}

main() {
  step='finding this machine'
  machine="$(platform)" || exit 1
  found="$(printf '%s\n' "$BUILDS" | awk -v machine="$machine" '$1 == machine { print $2, $3, $4 }')"
  [ -n "$found" ] || fail "stable publishes no build for $machine, so nothing was downloaded or run: Frontier $VERSION is built for $(printf '%s\n' "$BUILDS" | awk '{ printf "%s%s", gap, $1; gap = " and " }'), and their downloads are at https://frontierengineer.com/#install"
  asset="${found%% *}"
  rest="${found#* }"
  sha256="${rest%% *}"
  size="${rest#* }"
  directory="${FRONTIER_HOME:-${HOME:-}/.frontier}"
  [ -n "${FRONTIER_HOME:-}${HOME:-}" ] || fail "neither FRONTIER_HOME nor HOME is set, so there is no Frontier Directory to install into"

  step='downloading Frontier'
  megabytes=$(( (size + 999999) / 1000000 ))
  say "Frontier $VERSION for $machine: downloading $megabytes MB once, about $(( megabytes * 8 / 50 + 1 )) seconds at 50 Mbit/s, to take frontierctl from it."
  work="$(mktemp -d "${TMPDIR:-/tmp}/frontier-install.XXXXXX")" || fail "no temporary directory could be made"
  fetch "build-$BUILD_ID/$asset" "$work/$asset" || fail "$RELEASES/build-$BUILD_ID/$asset could not be downloaded"

  step='checking the download'
  got="$(digest "$work/$asset")"
  [ "$got" = "$sha256" ] || fail "$asset has the checksum $got, and stable's signed manifest names $sha256, so it is not Frontier's build and was discarded"

  step='placing frontierctl'
  tar -xzOf "$work/$asset" bin/frontierctl >"$work/frontierctl" || fail "frontierctl could not be taken out of $asset"
  mkdir -p "$directory/bin" || fail "$directory/bin could not be made"
  target="$directory/bin/frontierctl"
  if [ -e "$target" ]; then
    cp -p "$target" "$work/frontierctl.before" || fail "the frontierctl already at $target could not be kept aside"
    kept="$work/frontierctl.before"
  fi
  if ! { cp "$work/frontierctl" "$target.incoming" && chmod 755 "$target.incoming" && mv -f "$target.incoming" "$target"; }; then
    rm -f "$target.incoming"
    fail "frontierctl could not be written to $target"
  fi
  placed="$target"
  say "frontierctl is at $placed"

  step='frontierctl install'
  if [ -t 0 ]; then
    "$placed" install "$@"
  elif (: </dev/tty) 2>/dev/null; then
    "$placed" install "$@" </dev/tty
  else
    "$placed" install "$@" </dev/null
  fi
  status=$?
  [ "$status" -eq 0 ] || fail "it exited $status, and said why above"
  clean
}

main "$@"
