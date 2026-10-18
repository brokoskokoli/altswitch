#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Signs, notarizes and packages a built macOS app: <dist>/<App>-<version>.dmg and .zip (+ .sha256).
#
#   tools/package_macos.sh <path/to/App.app> [--notarize]
#
# The .app must be built beforehand (unsigned is fine) - building is project specific.
# Steps: copy the app → (optional) write Sparkle keys into Info.plist → sign inside-out
# (no --deep) → verify → notarize + staple the app → ZIP → DMG → sign, notarize, staple the DMG
# → SHA-256 files.
#
# Environment:
#   SIGN_IDENTITY    "Developer ID Application: Name (TEAMID)"; empty or "-" = ad-hoc (local
#                    test only: no Hardened Runtime, no notarization, Gatekeeper rejects it elsewhere)
#   SIGN_KEYCHAIN    keychain that holds the identity (CI: the temporary keychain)
#   ENTITLEMENTS     entitlements file for the main app (optional; keep it minimal)
#   APP_VERSION      default: CFBundleShortVersionString of the app
#   DIST_DIR         default: dist
#   Notarization (--notarize), either:
#     NOTARY_PROFILE                          keychain profile (xcrun notarytool store-credentials)
#     NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER   App Store Connect API key (.p8)
#   Sparkle (optional; only if the app embeds Sparkle.framework):
#     SPARKLE_FEED_URL, SPARKLE_PUBLIC_ED_KEY → SUFeedURL, SUPublicEDKey, SURequireSignedFeed,
#     SUVerifyUpdateBeforeExtraction are written into Info.plist before signing.
#     REQUIRE_SPARKLE=1 fails if the framework, feed URL or key is missing (set it in the release).
set -euo pipefail

die() { echo "package_macos.sh: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

SRC_APP=${1:-}; shift || true
NOTARIZE=0
for a in "$@"; do
  case "$a" in --notarize) NOTARIZE=1 ;; *) die "unknown option $a" ;; esac
done
[[ -d "$SRC_APP" && "$SRC_APP" == *.app ]] || die "usage: $0 <App.app> [--notarize]"
[[ "$(uname -s)" == Darwin ]] || die "macOS only"

IDENTITY=${SIGN_IDENTITY:--}
DIST=${DIST_DIR:-dist}
APP_BASENAME=$(basename "$SRC_APP" .app)
VERSION=${APP_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC_APP/Contents/Info.plist")}
[[ -n "$VERSION" ]] || die "no version"
if [[ $NOTARIZE == 1 && "$IDENTITY" == "-" ]]; then die "--notarize needs SIGN_IDENTITY (Developer ID)"; fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/package.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
APP="$WORK/$APP_BASENAME.app"
ditto "$SRC_APP" "$APP"
PLIST="$APP/Contents/Info.plist"

# ---- Sparkle keys -----------------------------------------------------------------
plist_set() { # plist_set key type value
  /usr/libexec/PlistBuddy -c "Set :$1 $3" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$PLIST"
}
HAS_SPARKLE=0; [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]] && HAS_SPARKLE=1
if [[ -n "${SPARKLE_FEED_URL:-}" && -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  [[ $HAS_SPARKLE == 1 ]] || die "SPARKLE_FEED_URL set, but the app has no Contents/Frameworks/Sparkle.framework"
  step "Sparkle: feed $SPARKLE_FEED_URL"
  plist_set SUFeedURL string "$SPARKLE_FEED_URL"
  plist_set SUPublicEDKey string "$SPARKLE_PUBLIC_ED_KEY"
  plist_set SURequireSignedFeed bool true
  plist_set SUVerifyUpdateBeforeExtraction bool true
elif [[ "${REQUIRE_SPARKLE:-0}" == 1 ]]; then
  die "REQUIRE_SPARKLE=1, but SPARKLE_FEED_URL/SPARKLE_PUBLIC_ED_KEY are not set"
fi

# ---- Sign (inside-out, no --deep) ------------------------------------------------
SIGN=(codesign --force --sign "$IDENTITY")
if [[ "$IDENTITY" == "-" ]]; then
  # Ad-hoc signatures have no Team ID; Hardened Runtime's library validation would reject
  # every embedded library, so local test builds go without it.
  SIGN+=(--timestamp=none)
else
  SIGN+=(--options runtime --timestamp)
fi
[[ -n "${SIGN_KEYCHAIN:-}" ]] && SIGN+=(--keychain "$SIGN_KEYCHAIN")

step "Code signing ($IDENTITY)"
# find -depth lists the contents of a directory before the directory itself: nested code is
# signed before the bundle that contains it. Everything nested keeps the entitlements it was
# shipped with (e.g. Sparkle's Downloader.xpc and its main executable) - re-signing a nested
# main executable without --preserve-metadata would drop them before its bundle is signed.
# Loose Mach-O files (dylibs, helpers) are signed as files.
while IFS= read -r -d '' p; do
  if [[ -d "$p" ]]; then
    case "$p" in
      *.framework|*.app|*.xpc|*.appex|*.bundle|*.plugin|*.systemextension)
        "${SIGN[@]}" --preserve-metadata=entitlements "$p" ;;
    esac
  elif [[ -f "$p" && "$(file -b "$p")" == *Mach-O* ]]; then
    "${SIGN[@]}" --preserve-metadata=entitlements "$p"
  fi
done < <(find "$APP/Contents" -depth \( -type d -o -type f \) -print0)
APP_SIGN=("${SIGN[@]}")
[[ -n "${ENTITLEMENTS:-}" ]] && APP_SIGN+=(--entitlements "$ENTITLEMENTS")
"${APP_SIGN[@]}" "$APP"

step "Verify signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier|Runtime|Timestamp)' || true

# ---- Notarization -------------------------------------------------------------------
AUTH=()
if [[ $NOTARIZE == 1 ]]; then
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    AUTH=(--keychain-profile "$NOTARY_PROFILE")
  elif [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
    [[ -f "$NOTARY_KEY_PATH" ]] || die "NOTARY_KEY_PATH missing: $NOTARY_KEY_PATH"
    AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
  else
    die "--notarize needs NOTARY_PROFILE or NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER"
  fi
fi

notarize() { # notarize <.app|.dmg>: submit, wait, show the log on failure, staple
  local target=$1 upload=$1 out id status
  if [[ "$target" == *.app ]]; then
    upload="$WORK/notarize-upload.zip"
    ditto -c -k --sequesterRsrc --keepParent "$target" "$upload"
  fi
  out=$(xcrun notarytool submit "$upload" "${AUTH[@]}" --wait --timeout 1h --output-format json) || true
  id=$(/usr/bin/python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("id",""))
except Exception: print("")' <<<"$out")
  status=$(/usr/bin/python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("status",""))
except Exception: print("")' <<<"$out")
  echo "notarytool: id=${id:-?} status=${status:-?}"
  if [[ "$status" != Accepted ]]; then
    echo "$out" >&2
    [[ -n "$id" ]] && xcrun notarytool log "$id" "${AUTH[@]}" >&2 || true
    die "notarization of $(basename "$target") failed"
  fi
  rm -f "$WORK/notarize-upload.zip"
  # The ticket can take a moment to appear and the runners' network drops now and then, sometimes
  # for several minutes: retry for up to ~14 minutes.
  local attempt attempts=8
  for (( attempt = 1; attempt <= attempts; attempt++ )); do
    xcrun stapler staple "$target" && xcrun stapler validate "$target" && return 0
    (( attempt < attempts )) || die "stapling $(basename "$target") failed"
    echo "stapler failed, retrying in $((attempt * 30))s"
    sleep $((attempt * 30))
  done
}

if [[ $NOTARIZE == 1 ]]; then
  step "Notarize app"
  notarize "$APP"
  spctl --assess --type execute -vvv "$APP"
fi

# ---- ZIP + DMG ------------------------------------------------------------------------
mkdir -p "$DIST"
ZIP="$DIST/$APP_BASENAME-$VERSION.zip"
DMG="$DIST/$APP_BASENAME-$VERSION.dmg"
rm -f "$ZIP" "$DMG" "$ZIP.sha256" "$DMG.sha256"
step "ZIP: $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

step "DMG: $DMG"
mkdir "$WORK/dmg"
ditto "$APP" "$WORK/dmg/$APP_BASENAME.app"
ln -s /Applications "$WORK/dmg/Applications"
hdiutil create -volname "$APP_BASENAME $VERSION" -srcfolder "$WORK/dmg" -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 -ov -quiet "$DMG"
if [[ "$IDENTITY" != "-" ]]; then
  DMG_SIGN=(codesign --force --sign "$IDENTITY" --timestamp)
  [[ -n "${SIGN_KEYCHAIN:-}" ]] && DMG_SIGN+=(--keychain "$SIGN_KEYCHAIN")
  "${DMG_SIGN[@]}" "$DMG"
  codesign --verify --strict --verbose=2 "$DMG"
fi
if [[ $NOTARIZE == 1 ]]; then
  step "Notarize DMG"
  notarize "$DMG"
fi

step "SHA-256"
(cd "$DIST" && for f in "$(basename "$ZIP")" "$(basename "$DMG")"; do shasum -a 256 "$f" > "$f.sha256"; cat "$f.sha256"; done)

if [[ $NOTARIZE == 1 ]]; then
  step "Gatekeeper"
  spctl --assess --type open --context context:primary-signature -vvv "$DMG"
fi
echo "Done: $DMG, $ZIP"
