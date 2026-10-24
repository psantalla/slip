#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN=.build/release/slip
APP=Slip.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/slip"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d.%H%M)" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# stable self-signed identity keeps the TCC (Accessibility/Input Monitoring) grant across rebuilds;
# fall back to ad-hoc if it is not set up
ID="Slip Self Signed"
if security find-identity -p codesigning | grep -q "$ID"; then
  codesign --force --deep --sign "$ID" "$APP"
  if codesign -dvv "$APP" 2>&1 | grep -q adhoc; then
    echo "error: cert signing did not take (still ad-hoc); TCC grants would reset. aborting." >&2
    exit 1
  fi
else
  echo "warning: '$ID' not in keychain; ad-hoc signing, TCC grants reset each build" >&2
  codesign --force --deep --sign - "$APP"
fi

# catch a half-written signature (e.g. sealed-but-missing .cstemp) before it ships
if ! codesign --verify --strict --verbose=2 "$APP"; then
  echo "error: signature invalid after signing; aborting." >&2
  exit 1
fi

echo "built $APP"

# optional: ./build.sh deploy  -> install to /Applications and ~/LFL safely.
# rm before ditto: ditto never prunes stale files, a leftover .cstemp = "sealed resource missing".
if [ "${1:-}" = "deploy" ]; then
  osascript -e 'quit app "Slip"' 2>/dev/null || true
  pkill -f "Slip.app/Contents/MacOS/slip" 2>/dev/null || true
  sleep 1
  for DST in /Applications/Slip.app "$HOME/LFL/Slip.app"; do
    rm -rf "$DST"
    ditto "$APP" "$DST"
    codesign --verify --strict "$DST" || { echo "error: $DST signature invalid; aborting." >&2; exit 1; }
    echo "deployed $DST"
  done
  open -a /Applications/Slip.app
fi
