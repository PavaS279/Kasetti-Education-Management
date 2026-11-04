#!/usr/bin/env bash
# KT College demo data: runs the idempotent stages in order against the target org.
# Usage: scripts/seed/college/seed-college.sh [org-alias]   (default: ktedu)
set -euo pipefail
cd "$(dirname "$0")"
org="${1:-ktedu}"
for stage in 01-catalogue 02-rules-fees-documents 03-curriculum-sections 04-demo-applicants; do
  echo "== $stage"
  sf apex run --file "$stage.apex" --target-org "$org" | grep -E "Executed|KT College|Error" || true
done
