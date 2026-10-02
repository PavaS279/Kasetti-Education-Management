#!/usr/bin/env bash
# Deploys force-app (or the given paths) to the default org and runs every
# local test class in this project (*Test.cls). Usage:
#   scripts/deploy.sh                     # deploy all of force-app
#   scripts/deploy.sh path/a path/b       # deploy specific paths
#   CHECK_ONLY=1 scripts/deploy.sh        # validate without saving
set -euo pipefail
cd "$(dirname "$0")/.."
export SF_DISABLE_TELEMETRY=true
target="${SF_TARGET_ORG:-edu-org}"

tests=()
while IFS= read -r file; do
  tests+=(--tests "$(basename "$file" .cls)")
done < <(find force-app -name '*Test.cls' | sort)

sources=()
if [[ $# -eq 0 ]]; then
  sources=(--source-dir force-app)
else
  for path in "$@"; do sources+=(--source-dir "$path"); done
fi

command=(sf project deploy start)
[[ "${CHECK_ONLY:-}" == "1" ]] && command=(sf project deploy validate)

# Production blocks deploying Apex that scheduled jobs depend on: pause KEM jobs,
# deploy, then reschedule them (KemJobs.scheduleAll is idempotent).
if [[ "${CHECK_ONLY:-}" != "1" ]]; then
  sf apex run --file scripts/apex/unschedule-kem-jobs.apex --target-org "$target" >/dev/null 2>&1 || true
fi

status=0
"${command[@]}" "${sources[@]}" --target-org "$target" \
  --test-level RunSpecifiedTests "${tests[@]}" --wait 60 --json | node scripts/tooling/deploy-summary.js || status=$?

if [[ "${CHECK_ONLY:-}" != "1" ]]; then
  if sf apex run --file scripts/apex/schedule-kem-jobs.apex --target-org "$target" >/dev/null 2>&1; then
    echo "KEM scheduled jobs: ensured"
  else
    echo "WARNING: could not reschedule KEM jobs; run scripts/apex/schedule-kem-jobs.apex" >&2
  fi
fi
exit $status
