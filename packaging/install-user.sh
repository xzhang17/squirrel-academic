#!/bin/bash
# This part of installation belongs to the signed-in account.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[[ $EUID -ne 0 ]] || { echo 'Run account setup as the desktop user.' >&2; exit 1; }
setup=$(cd -P -- "$(dirname -- "$0")" && pwd)
app='/Library/Input Methods/Squirrel.app'
sq="$app/Contents/MacOS/Squirrel"
profile="$HOME/Library/Rime"
hans='im.rime.inputmethod.Squirrel.Hans'

/usr/bin/ruby "$setup/Install.command" --package-profile
cd -- "$profile"
"$app/Contents/MacOS/rime_deployer" --build "$profile" "$app/Contents/SharedSupport" "$profile/build"
[[ -s "$profile/build/academic_pinyin.schema.yaml" && -s "$profile/build/academic_pinyin.table.bin" ]] ||
  { echo 'The academic dictionary did not deploy.' >&2; exit 1; }

"$sq" --register-input-source
/usr/bin/open -g "$app"
for attempt in 1 2 3; do
  if "$setup/is-simplified-selected"; then break; fi
  "$sq" --enable-input-source "$hans"
  "$sq" --select-input-source "$hans"
  /bin/sleep 0.4
done
/bin/bash "$setup/Mode-Indicator/Restore.command"
if ! "$setup/is-simplified-selected"; then
  echo 'The keyboard is installed. Choose Squirrel – Simplified from the input menu after macOS makes it available.'
fi
