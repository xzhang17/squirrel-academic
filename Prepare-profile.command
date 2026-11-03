#!/bin/bash
# Build a new Rime profile without changing the active input source.
set -euo pipefail
umask 077
export PATH=/usr/bin:/bin
repo=$(cd -P -- "$(dirname -- "$0")" && pwd)
source="$repo/Profile"
parent="${1:-$HOME/Library}"
[[ -d "$parent" && -f "$source/academic_profile_files.txt" ]] || exit 1
profile=$(mktemp -d "$parent/Rime-restored.XXXXXXXX")
trap '[[ -z "$profile" ]] || rm -rf -- "$profile"' EXIT
while IFS= read -r name || [[ -n "$name" ]]; do
  case "$name" in
    ''|'#'*) continue ;;
    /*|../*|*/../*|*/..|*//*) echo "Invalid profile path" >&2; exit 1 ;;
    academic_preferences.txt) : > "$profile/$name"; continue ;;
    custom_phrase.txt)
      printf '# Rime table\n#@/db_name\tcustom_phrase\n#@/db_type\ttabledb\n' > "$profile/$name"
      continue ;;
  esac
  [[ -f "$source/$name" && ! -L "$source/$name" ]] || { echo "Missing resource: $name" >&2; exit 1; }
  mkdir -p "$(dirname -- "$profile/$name")"
  cp -- "$source/$name" "$profile/$name"
done < "$source/academic_profile_files.txt"
cp -- "$source/academic_profile.txt" "$source/academic_profile_files.txt" "$profile/"
/bin/bash "$profile/academic_profile.txt" prepare >&2
sync_path=$(/usr/bin/ruby -rjson -e 'print JSON.generate(File.expand_path("~/Squirrel-Backup/sync"))')
printf 'installation_id: "%s"\nsync_dir: %s\n' "$(uuidgen | tr 'A-F' 'a-f')" "$sync_path" > "$profile/installation.yaml"
printf '%s\n' "$profile"
profile=''
