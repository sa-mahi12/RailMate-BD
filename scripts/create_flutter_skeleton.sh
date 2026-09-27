#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v flutter >/dev/null || { echo 'Flutter SDK missing; STOP' >&2; exit 2; }
if [ -e pubspec.yaml ] || [ -e lib/main.dart ] || [ -e android/app ]; then echo 'Existing Flutter scaffold detected; STOP, do not overwrite' >&2; exit 3; fi
if [ "$(git branch --show-current)" != main ]; then echo 'Must be on main' >&2; exit 4; fi
TMP="$ROOT/.bootstrap-tmp"
[ ! -e "$TMP" ] || { echo 'Stale temp skeleton; inspect manually' >&2; exit 5; }
mkdir -p "$TMP"
trap 'echo "Inspect $TMP if command failed; no automatic destructive cleanup"' ERR
flutter create --no-pub --platforms=android --project-name railmate_bd --org bd.railmate "$TMP"
for item in android lib test pubspec.yaml analysis_options.yaml .metadata; do
  if [ -e "$TMP/$item" ]; then cp -a "$TMP/$item" "$ROOT/"; fi
done
if [ -d "$TMP" ]; then rm -rf -- "$TMP"; fi
printf 'Flutter skeleton copied. Coordinator now review diff, install deps under heavy lock, test and commit.\n'
