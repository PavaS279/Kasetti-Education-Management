#!/usr/bin/env bash
# Seeds realistic KTEdutech data into the connected org (production-safe: additive, idempotent).
# Every stage can be re-run; stages that work in chunks are repeated until they report remaining=0.
#   scripts/seed/seed.sh            # all stages
#   scripts/seed/seed.sh 05 06      # chosen stages only
# Records carry hidden KT- external ids (KT-FAM-, KT-CRS-, KT-AS-, KT-ENQ-, section KT-...) for clean-up.
set -euo pipefail
cd "$(dirname "$0")/../.."
ORG="${SF_ORG_ALIAS:-edu-org}"
WORK="$(mktemp -d)"
FAMILY_BATCH=16
ENROL_BATCH=4

run() { # run <file> → prints the SEED summary line; fails on Apex errors
  local out
  out=$(sf apex run --file "$1" --target-org "$ORG" --json)
  python3 - "$out" <<'PY'
import json, re, sys
r = json.loads(sys.argv[1]); res = r.get("result") or r.get("data") or {}
logs = res.get("logs", "")
for line in re.findall(r"USER_DEBUG\|\[\d+\]\|DEBUG\|(SEED.*)", logs):
    print("   ", line)
if not res.get("success"):
    print("   FAILED:", r.get("message", "")[:400]); sys.exit(1)
PY
}

repeat() { # repeat <file> → re-runs while the stage reports remaining work or a pause
  for _ in $(seq 1 100); do
    local out; out=$(run "$1"); echo "$out" | tail -1
    echo "$out" | grep -qE "remaining=[1-9]|paused" || return 0
  done
}

stages=("$@"); [[ ${#stages[@]} -eq 0 ]] && stages=(01 02 03 04 05 06 07 08 09 10 11)
python3 scripts/seed/families.py >/dev/null
total=$(python3 -c "import json;print(len(json.load(open('scripts/seed/families.json'))))")
for s in "${stages[@]}"; do
  echo "== stage $s"
  case $s in
    01) run scripts/seed/01-setup.apex ;;
    02) repeat scripts/seed/02-classes.apex; run scripts/seed/02-classes.apex ;;
    03) for ((i = 0; i < total; i += FAMILY_BATCH)); do
          python3 scripts/seed/render.py scripts/seed/03-families.apex.tpl $i $FAMILY_BATCH "$WORK/03.apex" >/dev/null; run "$WORK/03.apex"
        done ;;
    04) for ((i = 0; i < total; i += ENROL_BATCH)); do
          python3 scripts/seed/render.py scripts/seed/04-enrolments.apex.tpl $i $ENROL_BATCH "$WORK/04.apex" >/dev/null; repeat "$WORK/04.apex"
        done ;;
    05) repeat scripts/seed/05-attendance.apex ;;
    06) repeat scripts/seed/06-assessments.apex ;;
    07) repeat scripts/seed/07-invoices.apex ;;
    08) repeat scripts/seed/08-payments.apex ;;
    09) repeat scripts/seed/09-enquiries.apex ;;
    10) for _ in 1 2 3 4 5 6; do run scripts/seed/10-operations.apex; done ;;
    11) for _ in 1 2 3 4; do run scripts/seed/11-extras.apex; done ;;
  esac
done
echo "Seed complete."
