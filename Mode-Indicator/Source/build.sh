#!/bin/bash
set -eu
root=$(cd -P -- "$(dirname -- "$0")" && pwd)
[[ $# == 1 && -d "$1" ]] || { echo 'Usage: build.sh /existing/output-directory' >&2; exit 2; }
app="$1/Squirrel Mode Indicator.app"
[[ ! -e "$app" && ! -L "$app" ]]
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/Info.plist" "$app/Contents/"
cp "$root/Chinese.svg" "$root/English.svg" "$app/Contents/Resources/"
/usr/bin/xcrun clang -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -Werror \
  -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 -framework Cocoa -framework Carbon \
  "$root/Indicator.m" -o "$app/Contents/MacOS/SquirrelModeIndicator"
/usr/bin/codesign --force --sign - --timestamp=none --options runtime --entitlements "$root/entitlements.plist" "$app"
/usr/bin/codesign --verify --strict "$app"
