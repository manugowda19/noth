#!/bin/bash
# Build NotchFlow and assemble it into a double-clickable .app bundle.
# No Xcode required — uses Swift Package Manager (swift build).
set -euo pipefail

CONFIG="${1:-release}"        # pass "debug" for a faster dev build
APP="Noth.app"
BUNDLE="$APP/Contents"

# Release builds are universal (Apple silicon + Intel); debug stays native
# for speed.
ARCH_FLAGS=()
[ "$CONFIG" = "release" ] && ARCH_FLAGS=(--arch arm64 --arch x86_64)

echo "==> swift build ($CONFIG ${ARCH_FLAGS[*]:-native})"
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}

BIN="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/NotchFlow"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$BUNDLE/MacOS" "$BUNDLE/Resources"
cp "$BIN" "$BUNDLE/MacOS/NotchFlow"
cp Resources/Info.plist "$BUNDLE/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE/Resources/AppIcon.icns"

# Now Playing for any player (browsers too): the vendored mediaremote-adapter
# framework + Perl script, run via Apple-entitled /usr/bin/perl at runtime.
# Bundled, not linked. Built once into .build/ (needs cmake); without it the
# app falls back to Music/Spotify AppleScript.
MRA_SRC="Vendor/mediaremote-adapter"
MRA_BUILD=".build/mediaremote-adapter"
if [ ! -d "$MRA_BUILD/MediaRemoteAdapter.framework" ] && command -v cmake >/dev/null; then
    echo "==> building mediaremote-adapter"
    cmake -S "$MRA_SRC" -B "$MRA_BUILD" -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "$MRA_BUILD" --target MediaRemoteAdapter >/dev/null
fi
if [ -d "$MRA_BUILD/MediaRemoteAdapter.framework" ]; then
    mkdir -p "$BUNDLE/Resources/MediaRemoteAdapter"
    cp -R "$MRA_BUILD/MediaRemoteAdapter.framework" "$BUNDLE/Resources/MediaRemoteAdapter/"
    cp "$MRA_SRC/bin/mediaremote-adapter.pl" "$BUNDLE/Resources/MediaRemoteAdapter/"
else
    echo "==> WARNING: no cmake — skipping mediaremote-adapter (Now Playing = Music/Spotify only)"
fi

# Sign with a stable self-signed identity if one exists, else fall back to
# ad-hoc. Ad-hoc signatures cannot hold an Accessibility (TCC) grant — macOS
# keys the grant on the code signature, and ad-hoc's identity is the cdhash,
# which changes every build, so the grant is forgotten each time. A stable
# self-signed cert keeps the identity constant, so you grant Accessibility
# ONCE and it sticks across rebuilds.
#
# One-time setup (no Apple account needed):
#   Keychain Access → Certificate Assistant → Create a Certificate…
#     Name: NotchFlow    Identity Type: Self Signed Root
#     Certificate Type: Code Signing
#   Override the identity name with:  export NOTCHFLOW_SIGN_ID="Your Cert Name"
# Try the stable identity first (a self-signed cert isn't listed by
# `find-identity -p codesigning` unless trusted, but codesign can still use it
# by name), fall back to ad-hoc. Ad-hoc's identity is the cdhash — changes
# every build — so its Accessibility grant is forgotten each time.
SIGN_ID="${NOTCHFLOW_SIGN_ID:-NotchFlow}"
if codesign --force --deep --sign "$SIGN_ID" "$APP" 2>/dev/null; then
    echo "==> signed with identity: $SIGN_ID (Accessibility grant persists)"
else
    echo "==> ad-hoc signing (no '$SIGN_ID' identity — Accessibility grant will NOT persist)"
    codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo "==> done: $(pwd)/$APP"
echo "    launch with:  open $APP"
