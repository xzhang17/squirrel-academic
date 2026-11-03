#!/bin/bash
# Restore the SVG indicator for the signed-in user.
set -euo pipefail
umask 077
fail() { printf '%s\n' "$*" >&2; exit 1; }
[[ $(id -u) != 0 ]] || fail "Run this as the account that uses Squirrel."
base=$(cd -P -- "$(dirname -- "$0")" && pwd)
label=local.squirrel.ModeIndicator
gui="gui/$(id -u)"
support="$HOME/Library/Application Support/Squirrel Mode Indicator"
agent="$HOME/Library/LaunchAgents/$label.plist"
app="$support/Squirrel Mode Indicator.app"
sq="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
profile="$HOME/Library/Rime/squirrel.custom.yaml"
[[ -x "$sq" && -f "$profile" && ! -L "$profile" ]] || fail "Restore your Squirrel profile first."
for dir in "$HOME/Library/Application Support" "$support" "$HOME/Library/LaunchAgents"; do
  [[ ! -L "$dir" ]] || fail "Unexpected linked directory: $dir"
done
mkdir -p "$support" "$HOME/Library/LaunchAgents"
work=$(mktemp -d "$support/.install.XXXXXXXX")
previous="$work/previous.app"
cleanup() {
  if [[ -d "$previous" ]]; then
    printf 'Kept the previous indicator at %s\n' "$previous" >&2
  else
    rm -rf -- "$work"
  fi
}
trap cleanup EXIT
(cd "$base" && /usr/bin/shasum -a 256 -c SHA256SUMS)
/usr/bin/ditto -x -k "$base/Squirrel Mode Indicator.zip" "$work"
unpacked="$work/Squirrel Mode Indicator.app"
/usr/bin/codesign --verify --strict -R='identifier "local.squirrel.ModeIndicator"' "$unpacked"
upgrade=no
if [[ -e "$app" || -L "$app" ]]; then
  [[ -d "$app" && ! -L "$app" ]] || fail "Unexpected app at $app"
  if ! /usr/bin/diff -qr "$app" "$unpacked" >/dev/null; then
    /usr/bin/codesign --verify --strict -R='identifier "local.squirrel.ModeIndicator"' "$app"
    # Accept only the indicator builds previously installed for this profile.
    digest=$(/usr/bin/shasum -a 256 "$app/Contents/MacOS/SquirrelModeIndicator")
    case ${digest%% *} in
      109c694b067de224d0702412a5bdb42537a8156ccdcdc39c8cfa4df446e1699e|\
      4c09fbbec9913c712a89716ac706ea499acb59984f12cd4e66d06e64a6fb14a0|\
      223679b53af05ace312d2b5d0ae81a5eaf12ef56992ea057002c140e2a92bc03|\
      2dcfd4ff755d7077b296251166a19db72ba4c5415fb179a68716fed7802dbfc5) ;;
      *) fail "A different indicator app is already installed." ;;
    esac
    upgrade=yes
  fi
fi
plist="$work/agent.plist"
/usr/bin/plutil -create xml1 "$plist"
/usr/bin/plutil -insert Label -string "$label" "$plist"
/usr/bin/plutil -insert ProgramArguments -json '[]' "$plist"
/usr/bin/plutil -insert ProgramArguments.0 -string "$app/Contents/MacOS/SquirrelModeIndicator" "$plist"
/usr/bin/plutil -insert RunAtLoad -bool YES "$plist"
/usr/bin/plutil -insert KeepAlive -json '{"SuccessfulExit":false}' "$plist"
/usr/bin/plutil -insert LimitLoadToSessionType -string Aqua "$plist"
logBase=$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)
[[ $logBase == /* ]] || fail "Cannot locate the Squirrel log directory."
cp "$plist" "$work/legacy.plist"
/usr/bin/plutil -insert EnvironmentVariables -json '{}' "$plist"
/usr/bin/plutil -insert EnvironmentVariables.SQUIRREL_LOG_FOLDER -string "${logBase%/}/rime.squirrel" "$plist"
agentChange=no
if [[ -e "$agent" || -L "$agent" ]]; then
  [[ -f "$agent" && ! -L "$agent" ]] || fail "Unexpected login item at $agent."
  if ! cmp -s "$plist" "$agent"; then
    cmp -s "$work/legacy.plist" "$agent" || fail "A different login item already uses $label."
    cp "$agent" "$work/previous.plist"
    agentChange=yes
  fi
else
  agentChange=yes
fi
if [[ $upgrade == yes || $agentChange == yes ]]; then
  if /bin/launchctl print "$gui/$label" >/dev/null 2>&1; then
    /bin/launchctl bootout "$gui/$label"
  fi
fi
if [[ $agentChange == yes ]]; then mv "$plist" "$agent"; fi
if [[ $upgrade == yes ]]; then
  mv "$app" "$previous"
fi
start_indicator() {
  if ! /bin/launchctl print "$gui/$label" >/dev/null 2>&1; then
    /bin/launchctl bootstrap "$gui" "$agent" || return 1
  fi
  /bin/launchctl kickstart "$gui/$label"
}
if { [[ -d "$app" ]] || mv "$unpacked" "$app"; } && start_indicator; then
  if [[ -d "$previous" ]]; then rm -rf -- "$previous"; fi
else
  /bin/launchctl bootout "$gui/$label" >/dev/null 2>&1 || true
  if [[ -f "$work/previous.plist" ]]; then mv "$work/previous.plist" "$agent"; fi
  if [[ -d "$previous" ]]; then
    if [[ -d "$app" ]]; then mv "$app" "$work/failed.app"; fi
    mv "$previous" "$app"
  fi
  if [[ -d "$app" && -f "$agent" ]]; then start_indicator; fi
  fail "Could not start the new indicator."
fi
# Keep the original status label until the first installation has been tested.
[[ ${1:-} != --stage ]] || exit 0
before='  status_icon/show: true'
after='  status_icon/show: false'
if /usr/bin/grep -Fxq "$before" "$profile"; then
  [[ $(/usr/bin/grep -Fxc "$before" "$profile") == 1 ]] || fail "Ambiguous status setting."
  /usr/bin/sed 's/^  status_icon\/show: true$/  status_icon\/show: false/' "$profile" > "$work/skin"
  chmod "$(stat -f '%OLp' "$profile")" "$work/skin"
  mv "$work/skin" "$profile"
elif ! /usr/bin/grep -Fxq "$after" "$profile"; then
  fail "The image indicator is installed. Check the status_icon/show setting in your Squirrel profile."
fi
"$sq" --reload
printf '%s\n' "SVG indicator ready. Squirrel will sync the updated skin with your next native backup."
