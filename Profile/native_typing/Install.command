#!/bin/bash
# Apply the local executable only to the matching installed nightly. No downloads.
set -euo pipefail
cd -- "$(dirname -- "$0")"
typing_assets=$PWD
typing_work=$(mktemp -d /private/tmp/squirrel-typing-install.XXXXXXXX)
trap 'rm -rf -- "$typing_work"' EXIT
typing_target='/Library/Input Methods/Squirrel.app'

python3 - "$typing_assets" "$typing_target" <<'PY'
import hashlib,json,plistlib,sys
from pathlib import Path
assets,app=map(Path,sys.argv[1:])
base=json.loads((assets/'nightly-base.txt').read_text())
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
actual=hashlib.sha256((app/'Contents/MacOS/Squirrel').read_bytes()).hexdigest()
assert info['CFBundleIdentifier']=='im.rime.inputmethod.Squirrel'
assert info['CFBundleVersion']==base['bundle_version'], 'A different Squirrel version is installed.'
assert actual in [base['original_sha256'],base['modified_sha256']] or info.get('AcademicTypingBase')==base['revision'], 'The installed nightly has changed; rebuild the local extension first.'
assert hashlib.sha256((app/'Contents/Frameworks/librime.1.dylib').read_bytes()).hexdigest()==base['librime_sha256'], 'The Rime engine has changed; rebuild first.'
assert hashlib.sha256((assets/'Squirrel.local').read_bytes()).hexdigest()==base['modified_sha256'], 'Local executable does not match its build record.'
PY

/usr/bin/ditto "$typing_target" "$typing_work/Squirrel.app"
/bin/cp "$typing_assets/Squirrel.local" "$typing_work/Squirrel.app/Contents/MacOS/Squirrel"
/bin/chmod 755 "$typing_work/Squirrel.app/Contents/MacOS/Squirrel"
python3 - "$typing_work/Squirrel.app/Contents/Info.plist" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1]); info=plistlib.loads(p.read_bytes())
info['AcademicTypingVersion']='1.2'
info['AcademicTypingFeatures']=['smart_space','smart_space_digit']
info['AcademicTypingBase']='d220b92'
# Keep this local nightly until the user explicitly chooses a replacement.
info['SUEnableAutomaticChecks']=False
info['SUAutomaticallyUpdate']=False
p.write_bytes(plistlib.dumps(info))
PY
/usr/bin/codesign --force --sign - --options runtime --entitlements "$typing_assets/entitlements.txt" "$typing_work/Squirrel.app"
/usr/bin/codesign --verify --deep --strict "$typing_work/Squirrel.app"

cat > "$typing_work/install-root.sh" <<'ROOT'
#!/bin/bash
set -euo pipefail
source_app=$1
target='/Library/Input Methods/Squirrel.app'
backup='/Library/Application Support/Squirrel Typing/Original-Squirrel.zip'
[[ -d "$source_app" && -d "$target" && ! -L "$target" ]]
/usr/bin/codesign --verify --deep --strict "$source_app"
/usr/bin/install -d -m 755 '/Library/Application Support/Squirrel Typing'
if [[ ! -e "$backup" ]]; then
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$target" "$backup"
  /usr/bin/unzip -tq "$backup"
fi
stage=$(/usr/bin/mktemp -d '/Library/Input Methods/.Squirrel-typing.XXXXXXXX')
/usr/bin/ditto "$source_app" "$stage/Squirrel.app"
/usr/sbin/chown -R root:wheel "$stage/Squirrel.app"
/usr/bin/codesign --verify --deep --strict "$stage/Squirrel.app"
# Preserve the app-directory identity so macOS permission/file references remain
# valid. Swap the executable atomically rather than overwriting a running image.
/bin/cp -p "$target/Contents/MacOS/Squirrel" "$stage/previous-executable"
/bin/cp -p "$target/Contents/Info.plist" "$stage/previous-info"
/bin/cp -p "$target/Contents/_CodeSignature/CodeResources" "$stage/previous-resources"
# Recover all three files after any interrupted/failed replacement, not only
# when the final signature check fails. Keep recovery files if rollback fails.
finish_install() {
  result=$?
  trap - EXIT HUP INT TERM
  if [[ "$result" != 0 ]]; then
    /bin/mv "$stage/previous-executable" "$target/Contents/MacOS/Squirrel" &&
      /bin/mv "$stage/previous-info" "$target/Contents/Info.plist" &&
      /bin/mv "$stage/previous-resources" "$target/Contents/_CodeSignature/CodeResources" || {
        printf 'Restore failed; recovery files remain in %s\n' "$stage" >&2
        exit "$result"
      }
  fi
  /bin/rm -rf -- "$stage"
  exit "$result"
}
trap finish_install EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
/bin/mv "$stage/Squirrel.app/Contents/MacOS/Squirrel" "$target/Contents/MacOS/Squirrel"
/bin/mv "$stage/Squirrel.app/Contents/Info.plist" "$target/Contents/Info.plist"
/bin/mv "$stage/Squirrel.app/Contents/_CodeSignature/CodeResources" "$target/Contents/_CodeSignature/CodeResources"
/usr/bin/codesign --verify --deep --strict "$target"
ROOT

/usr/bin/osascript - "$typing_work/install-root.sh" "$typing_work/Squirrel.app" <<'APPLESCRIPT'
on run argv
  do shell script "/bin/bash " & quoted form of item 1 of argv & " " & quoted form of item 2 of argv with administrator privileges
end run
APPLESCRIPT

# Refresh macOS app lookups for the active nightly.
typing_register='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
"$typing_register" -f "$typing_target"
"$typing_target/Contents/MacOS/Squirrel" --quit
for attempt in {1..20}; do
  if ! /usr/bin/pgrep -x Squirrel >/dev/null; then break; fi
  /bin/sleep 0.1
done
typing_opened=false
for attempt in {1..5}; do
  if /usr/bin/open -g "$typing_target" 2>"$typing_work/open-error.txt"; then typing_opened=true; break; fi
  /bin/sleep 0.2
done
if [[ "$typing_opened" != true ]]; then /bin/cat "$typing_work/open-error.txt" >&2; exit 1; fi
printf '%s\n' 'Installed the locally modified d220b92 nightly. Original app retained for rollback.'
