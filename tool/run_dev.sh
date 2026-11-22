#!/usr/bin/env bash
# Run ChordPlane with the cloud/auth configuration compiled in.
#
# Cloud credentials are compile-time defines (see lib/core/config/app_config.dart),
# so a bare `flutter run` builds a local-only app: Settings shows "Local mode"
# and the sign-in sheet is never reachable. Hot reload cannot change that.
# This wrapper always passes --dart-define-from-file, so cloud share links and
# email/password (plus Google, when a client ID is set) are available.
#
#   tool/run_dev.sh                    # dart_defines.json, else the example
#   tool/run_dev.sh -d <device-id>     # extra arguments go to `flutter run`
#   DART_DEFINES_FILE=other.json tool/run_dev.sh
#
# Copy dart_defines.example.json to dart_defines.json to override the public
# defaults (for example to point at your own Supabase project).
set -eo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v flutter >/dev/null 2>&1; then
  echo "error: flutter is not on PATH." >&2
  exit 1
fi

defines="${DART_DEFINES_FILE:-}"
if [[ -z "$defines" ]]; then
  if [[ -f dart_defines.json ]]; then
    defines="dart_defines.json"
  else
    defines="dart_defines.example.json"
  fi
fi

if [[ ! -f "$defines" ]]; then
  echo "error: defines file not found: $defines" >&2
  echo "       copy dart_defines.example.json to dart_defines.json and edit it." >&2
  exit 1
fi

echo "ChordPlane: compiling with --dart-define-from-file=$defines"
exec flutter run --dart-define-from-file="$defines" "$@"
