#!/usr/bin/env bash
# Renames legacyCall to currentCall in the packages' source. It never touches
# the generated directory or the lockfile; both are regenerated, not edited.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
for dir in "$root"/packages/*/src; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.js; do
    [ -f "$f" ] || continue
    sed -i 's/\blegacyCall/currentCall/g' "$f"
  done
done
