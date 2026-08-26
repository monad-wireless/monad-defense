#!/usr/bin/env bash
# Capture the app's screenshots deterministically.
#
# Uses the DEBUG-only launch-argument router (Views/DebugRouter.swift) to open
# a chosen card straight from launch, so a screenshot is reproducible rather
# than the result of somebody tapping in the right order.
#
#   ./design/screenshots.sh [simulator-udid]
#
# Requires an iOS 26 simulator; the app targets iOS 26.
set -euo pipefail

SIM="${1:-$(xcrun simctl list devices available | awk '/-- iOS 26/{f=1} f&&/iPhone 17 Pro \(/{gsub(/[()]/,"");print $4;exit}')}"
OUT="$(cd "$(dirname "$0")" && pwd)/screenshots"
DD="${DERIVED_DATA:-$(mktemp -d)}"

# Read the bundle id out of the build rather than hardcoding it: it comes from
# Configuration/Base.xcconfig, which Configuration/Local.xcconfig may override.
APP_ID="$(xcodebuild -project MonadDefense.xcodeproj -scheme MonadDefense \
  -destination "id=$SIM" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER = /{print $2; exit}')"

mkdir -p "$OUT"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcodebuild -project MonadDefense.xcodeproj -scheme MonadDefense \
  -destination "id=$SIM" -derivedDataPath "$DD" build >/dev/null
xcrun simctl install "$SIM" "$DD/Build/Products/Debug-iphonesimulator/MonadDefense.app"

shot() {  # shot <name> [launch args...]
  local name="$1"; shift
  xcrun simctl terminate "$SIM" "$APP_ID" 2>/dev/null || true
  xcrun simctl launch "$SIM" "$APP_ID" "$@" >/dev/null
  sleep 4
  xcrun simctl io "$SIM" screenshot "$OUT/$name.png"
}

# Figure-bearing cards are long. Shrinking the content size fits the picture
# on one screen without cropping it, which a README screenshot needs and a
# reader on a phone gets by scrolling.
xcrun simctl ui "$SIM" appearance light
xcrun simctl ui "$SIM" content_size large
shot 01-today
shot 05-committee -DemoCards trap-0001 -DemoReveal

xcrun simctl ui "$SIM" content_size extra-small
shot 02-formula   -DemoCards form-0003 -DemoReveal
shot 03-diagram   -DemoCards abbr-0003 -DemoReveal
shot 04-real-data -DemoCards abbr-0011 -DemoReveal
shot 06-graph     -DemoReader abbr-0011

# One dark capture: the theme has to be right in both, and a screenshot set
# that only shows light hides half the work.
xcrun simctl ui "$SIM" appearance dark
shot 07-dark      -DemoCards form-0008 -DemoReveal
xcrun simctl ui "$SIM" appearance light
shot 08-interactive -DemoFigures form-0003
shot 09-table       -DemoFigures abbr-0014
shot 10-sequence    -DemoFigures abbr-0017
shot 11-iot         -DemoFigures abbr-0020

xcrun simctl ui "$SIM" appearance light
xcrun simctl ui "$SIM" content_size large
xcrun simctl terminate "$SIM" "$APP_ID" 2>/dev/null || true
echo "→ $OUT"
