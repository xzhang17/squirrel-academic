#!/bin/bash
# Build a new Rime profile without changing the active input source.
set -euo pipefail
umask 077
export PATH=/usr/bin:/bin
repo=$(cd -P -- "$(dirname -- "$0")" && pwd)
source="$repo/Profile"
parent="${1:-$HOME/Library}"
[[ -d "$parent" && -f "$source/zenfire_profile_files.txt" ]] || exit 1
[[ -s "$source/wanxiang-lts-zh-hans.gram" ]] || {
  echo 'Missing Wanxiang model. Use the complete installer, or copy its installed wanxiang-lts-zh-hans.gram into Profile/ for source setup.' >&2
  exit 1
}
(cd "$source" && /usr/bin/shasum -a 256 -c "$repo/Model.sha256") >&2
profile=$(mktemp -d "$parent/Rime-restored.XXXXXXXX")
trap '[[ -z "$profile" ]] || rm -rf -- "$profile"' EXIT
while IFS= read -r name || [[ -n "$name" ]]; do
  case "$name" in
    ''|'#'*) continue ;;
    /*|../*|*/../*|*/..|*//*) echo "Invalid profile path" >&2; exit 1 ;;
    zenfire_preferences.txt) : > "$profile/$name"; continue ;;
    custom_phrase.txt)
      printf '# Rime table\n#@/db_name\tcustom_phrase\n#@/db_type\ttabledb\n' > "$profile/$name"
      continue ;;
  esac
  [[ -f "$source/$name" && ! -L "$source/$name" ]] || { echo "Missing resource: $name" >&2; exit 1; }
  mkdir -p "$(dirname -- "$profile/$name")"
  cp -p -- "$source/$name" "$profile/$name"
  chmod 600 "$profile/$name"
done < "$source/zenfire_profile_files.txt"
cp -p -- "$source/zenfire_profile.txt" "$source/zenfire_profile_files.txt" "$profile/"
chmod 600 "$profile/zenfire_profile.txt" "$profile/zenfire_profile_files.txt"
/bin/bash "$profile/zenfire_profile.txt" prepare >&2
sync_path=$(/usr/bin/ruby -rjson -e 'print JSON.generate(File.expand_path("~/Squirrel-Backup/sync"))')
printf 'installation_id: "%s"\nsync_dir: %s\n' "$(uuidgen | tr 'A-F' 'a-f')" "$sync_path" > "$profile/installation.yaml"
printf '%s\n' "$profile"
profile=''
