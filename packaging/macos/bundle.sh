#!/usr/bin/env bash
#
# packaging/macos/bundle.sh - wrap a player build of `warcraft-survivors` in `Azeroth Survivors.app`
# and pack it into a `.dmg`. macOS only: it needs `iconutil`, `codesign` and `hdiutil`.
#
#   packaging/macos/bundle.sh --bin target/release/warcraft-survivors --out dist \
#     --version 0.2.0 --build-number 0.2.0.17 --build-id v0.2.0-12-gb17be27
#
# What comes out, under --out:
#   Azeroth Survivors.app   the bundle, ad-hoc signed
#   Azeroth Survivors.dmg   that bundle, a README and an /Applications link
#
# The bundle carries no game data: the repo ships no Blizzard content, and the client reads a
# WoW 1.12.1 install the player supplies. Inside a `.app` it looks for that install (and keeps its
# settings) under `~/Library/Application Support/Azeroth Survivors`, or in a `Data` folder beside
# the app, never inside the bundle: a write there would break the code signature, and macOS
# refuses to open a bundle whose signature does not match. `crates/warcraft-survivors/src/
# bundle.rs` is that rule; this script only has to produce the layout it reads.
#
# Signing is ad-hoc (`-`): an Apple Silicon Mac will not run an unsigned binary at all, and the
# dmg then opens on Intel too. It is not notarized, so Gatekeeper asks the player to confirm the
# first launch once. Set MACOS_SIGN_IDENTITY to a Developer ID Application identity to sign for
# real; notarization (`xcrun notarytool submit --wait`, then `xcrun stapler staple`) is the step
# after that, and needs an Apple Developer account.
set -euo pipefail

APP_NAME="Azeroth Survivors"
BIN_NAME="warcraft-survivors"
BUNDLE_ID="io.github.yoyooyooo.azeroth-survivors"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"

bin=""
out="dist"
version=""
build_number=""
build_id=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bin) bin="${2:?--bin needs a path}"; shift 2 ;;
    --out) out="${2:?--out needs a path}"; shift 2 ;;
    --version) version="${2:?--version needs a version}"; shift 2 ;;
    --build-number) build_number="${2:?--build-number needs a number}"; shift 2 ;;
    --build-id) build_id="${2:?--build-id needs a string}"; shift 2 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || { echo "bundle.sh builds a macOS app; this is $(uname -s)" >&2; exit 1; }
[ -n "$bin" ] || { echo "--bin <path to the built $BIN_NAME> is required" >&2; exit 1; }
[ -x "$bin" ] || { echo "not an executable: $bin" >&2; exit 1; }
if [ -z "$version" ]; then
  version="$(sed -n 's/^version = "\(.*\)"$/\1/p' "$root/Cargo.toml" | head -1)"
fi
[ -n "$version" ] || { echo "no version: pass --version" >&2; exit 1; }
build_number="${build_number:-$version}"

work="$out/work"
app="$out/$APP_NAME.app"
rm -rf "$app" "$work" "$out/$APP_NAME.dmg"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$work"

# ── The executable ──────────────────────────────────────────────────────────────────────────────
# `CFBundleExecutable` names it, and the client's own bundle rule (`bundle.rs`) reads the
# `Contents/MacOS` layout back, so the name carries no spaces.
cp "$bin" "$app/Contents/MacOS/$BIN_NAME"
chmod +x "$app/Contents/MacOS/$BIN_NAME"

# ── Info.plist ──────────────────────────────────────────────────────────────────────────────────
# `CFBundleVersion` is the build number macOS orders builds by, so it is dotted integers;
# `CFBundleShortVersionString` is what the Finder shows. `AZBuildId` carries the git describe, for
# a report that has to name the commit behind a dmg. `LSMinimumSystemVersion` is a floor, not a
# measurement: Bevy 0.18 and wgpu 27 need Metal 3, which every macOS that runs the game has.
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>CFBundleExecutable</key>
	<string>$BIN_NAME</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$version</string>
	<key>CFBundleVersion</key>
	<string>$build_number</string>
	<key>AZBuildId</key>
	<string>${build_id:-$version}</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
</dict>
</plist>
PLIST
plutil -lint "$app/Contents/Info.plist" >/dev/null

# ── The icon ───────────────────────────────────────────────────────────────────────────────────
# `icon-1024.png` is committed, rendered once from `icon.svg` by `rsvg-convert`, so a runner needs
# no SVG renderer; `iconutil` assembles the `.icns` macOS reads.
iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size "$here/icon-1024.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$here/icon-1024.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

# ── Sign ──────────────────────────────────────────────────────────────────────────────────────
# Over the finished bundle, before the image is made: anything added afterwards would invalidate
# the signature, and the check below is what proves it did not happen.
codesign --force --timestamp=none --sign "${MACOS_SIGN_IDENTITY:--}" "$app"
codesign --verify --strict --verbose=2 "$app"

# ── The dmg ───────────────────────────────────────────────────────────────────────────────────
# A plain HFS+ image holding the app, a README and an `/Applications` link for the usual drag
# install. No Finder layout step: a background picture and icon positions would need a mounted
# volume and AppleScript in CI and buy a window nobody has to see. `ditto`, not `cp -R`, is what
# copies a signed bundle without disturbing its signature.
stage="$work/stage"
mkdir -p "$stage"
ditto "$app" "$stage/$APP_NAME.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/README.txt" <<README
$APP_NAME $version
$(printf '=%.0s' $(seq 1 $((${#APP_NAME} + ${#version} + 1))))

A fan-made WoW roguelike by Aethus (https://wow.aethus.pl/), running on a from-scratch
WoW 1.12.1 client engine (Rust + Bevy). No server, no login, no account.

 1. Drag "$APP_NAME.app" onto the Applications folder in this window.
 2. This app ships no Blizzard content. It reads a World of Warcraft 1.12.1
    (build 5875) client's Data folder, which you supply. Copy the client's *.MPQ
    files into:

      ~/Library/Application Support/$APP_NAME/Data/

    Create that folder if it does not exist (Finder: Go > Go to Folder, paste the
    line above). A "Data" folder next to the app works too, for a portable copy.
    A folder inside the app never does: it breaks the app's signature.

 3. Launch $APP_NAME. The first launch asks for confirmation once: this build is
    ad-hoc signed and not notarized (System Settings > Privacy & Security >
    "Open Anyway").

Settings, macros and screenshots live in ~/Library/Application Support/$APP_NAME/.

Controls: WASD to move, Space to jump, F for your class's movement spell, the
mouse wheel to zoom, C to unlock the camera, Esc to pause, 1/2/3 to pick a
level-up card.

Licenses: MIT or Apache-2.0 (the engine code). World of Warcraft is a trademark of
Blizzard Entertainment, Inc.; $APP_NAME is not affiliated with or endorsed by
Blizzard. The art the game renders comes from your own client.
README

hdiutil create -volname "$APP_NAME" -srcfolder "$stage" -ov -format UDZO -fs HFS+ \
  "$out/$APP_NAME.dmg" >/dev/null
hdiutil verify "$out/$APP_NAME.dmg" >/dev/null

# The signature has to survive the trip through the image: mount it and ask the bundle inside.
mkdir -p "$work/mnt"
hdiutil attach -nobrowse -readonly -mountpoint "$work/mnt" "$out/$APP_NAME.dmg" >/dev/null
codesign --verify --strict --verbose=2 "$work/mnt/$APP_NAME.app"
hdiutil detach "$work/mnt" >/dev/null

echo "built $out/$APP_NAME.dmg"
ls -lh "$out/$APP_NAME.dmg"
