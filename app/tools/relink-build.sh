#!/usr/bin/env bash
# Points app/build at a folder outside iCloud Drive.
#
# When the project lives in an iCloud-synced folder (~/Documents), iCloud adds
# extended attributes that make codesign fail on Flutter.framework ("resource
# fork, Finder information, or similar detritus not allowed"). Run this once
# after every `flutter clean`.
#
# Usage: cd app && bash tools/relink-build.sh
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REAL_BUILD="$HOME/Library/Developer/SafeTrackBuild"

mkdir -p "$REAL_BUILD"

if [ -L "$APP_DIR/build" ] && [ "$(readlink "$APP_DIR/build")" = "$REAL_BUILD" ]; then
  echo "app/build already points to $REAL_BUILD"
  exit 0
fi

rm -rf "$APP_DIR/build"
ln -s "$REAL_BUILD" "$APP_DIR/build"
echo "app/build -> $REAL_BUILD"
