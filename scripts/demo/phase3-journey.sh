#!/usr/bin/env bash
# Phase 3 journey against the connected org: a new centre is opened from the
# demo branch and runs end to end — LMS sync and grades through the API, an
# invoice in the ERP journal, online-payment safeguards, retention scoring,
# a library loan, analytics, the branch comparison and the operations console.
#
# Every run opens its own centre "[KEM Demo] Centre <tag>" (code D3-<tag>)
# with its own learner, so runs never collide. Requires the demo branch
# DEMO-01. Online payments stay Off and email delivery as configured, so no
# money moves and no email leaves the org.
#
# Usage: scripts/demo/phase3-journey.sh [run-tag]      e.g. scripts/demo/phase3-journey.sh P3A
set -euo pipefail

TAG="${1:-$(date +%H%M%S)}"
ORG="${SF_ORG_ALIAS:-edu-org}"
WORK="$(mktemp -d)"
STATE="$WORK/state"
PASS=0
FAIL=0
: > "$STATE"

say() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✔\033[0m %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '  \033[31m✘\033[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }
get() { grep "^$1=" "$STATE" | tail -1 | cut -d= -f2-; }

# Runs anonymous Apex; lines printed as System.debug('KEM::key=value') are saved
# to the state file and shown. Placeholders {{key}} are filled from the state.
apex() {
  local file="$WORK/step.apex" body="$1" key
  for key in $(grep -o '{{[a-zA-Z]*}}' <<<"$body" | tr -d '{}' | sort -u); do
    body="${body//\{\{$key\}\}/$(get "$key")}"
  done
  printf '%s\n' "$body" > "$file"
  local out
  if ! out=$(sf apex run --file "$file" --target-org "$ORG" 2>&1); then
    echo "$out" | grep -E "Error|Exception|line" | head -5
    bad "step failed"
    return 1
  fi
  echo "$out" | grep 'USER_DEBUG' | grep -o 'KEM::.*$' | sed 's/^KEM:://' | while IFS= read -r line; do
    echo "$line" >> "$STATE"
    echo "    $line"
  done
}

check() { # check <description> <key> <expected>
  local actual
  actual="$(get "$2")"
  if [[ "$actual" == "$3" ]]; then ok "$1 ($actual)"; else bad "$1: expected '$3', got '$actual'"; fi
}

rest() { # rest <method> <path> [body] → prints the JSON response
  if [[ $# -ge 3 ]]; then
    sf api request rest "$2" --method "$1" --body "$3" --target-org "$ORG" 2>/dev/null
  else
    sf api request rest "$2" --method "$1" --target-org "$ORG" 2>/dev/null
  fi
}
put() { echo "$1=$2" >> "$STATE"; echo "    $1=$2"; }

echo "Kasetti Phase 3 journey — run tag $TAG — org $ORG"

say "1. Open a new centre from [KEM Demo] Bengaluru Central"
apex "
BranchTemplateService.CloneRequest r = new BranchTemplateService.CloneRequest();
r.sourceBranchId = [SELECT Id FROM Branch__c WHERE Branch_Code__c = 'DEMO-01'].Id;
r.name = '[KEM Demo] Centre $TAG';
r.code = 'D3-$TAG';
r.invoicePrefix = 'D3$TAG';
r.city = 'Bengaluru';
r.includeRooms = true; r.includePrices = true; r.includeDiscounts = true; r.includeClosures = true; r.includeClasses = true;
r.classStartDate = Date.today().toStartOfWeek().addDays(1);
BranchTemplateService.CloneResult res = BranchTemplateService.cloneBranch(r);
System.debug('KEM::branchId=' + res.branchId);
System.debug('KEM::classesCopied=' + (res.classes > 0));
System.debug('KEM::roomsCopied=' + res.rooms);
"
check "Classes copied as Planned" classesCopied "true"
check "Rooms copied" roomsCopied "2"

say "2. Open a copied class and enrol a learner"
apex "
CourseOffering c = [SELECT Id, Name FROM CourseOffering WHERE Branch__c = '{{branchId}}' AND Name LIKE '%Coding Club%' LIMIT 1];
update new CourseOffering(Id = c.Id, Class_Status__c = 'Open', EnrollmentCapacity = 10);
Account learner = PersonAccountService.buildPerson('Learner', '$TAG [KEM Demo] Centre', 'learner.$TAG.centre@example.com', null, '{{branchId}}', 'Learner');
insert learner;
EnrolmentService.EnrolmentRequest e = new EnrolmentService.EnrolmentRequest();
e.learnerAccountId = learner.Id;
e.offeringId = c.Id;
Id enrolmentId = EnrolmentService.enrol(e).enrolmentId;
System.debug('KEM::classId=' + c.Id);
System.debug('KEM::learnerId=' + learner.Id);
System.debug('KEM::learnerContactId=' + [SELECT PersonContactId FROM Account WHERE Id = :learner.Id].PersonContactId);
System.debug('KEM::enrolmentId=' + enrolmentId);
System.debug('KEM::lmsEvents=' + ([SELECT COUNT() FROM Integration_Event__c WHERE Target__c = 'LMS' AND Branch__c = '{{branchId}}' AND Event_Type__c IN ('class.updated', 'enrolment.updated')] >= 2));
"
check "Class and enrolment events in the LMS outbox" lmsEvents "true"

say "3. LMS API: classes, roster, grades"
put lmsClasses "$(rest GET "/services/apexrest/kem/v1/lms/classes?branch=D3-$TAG&status=Open" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["classes"]))')"
check "Open class listed for the centre" lmsClasses "1"
put rosterHasLearner "$(rest GET "/services/apexrest/kem/v1/lms/classes/$(get classId)/roster" | python3 -c 'import json,sys; print(any((l.get("email") or "").lower()=="learner.'"$TAG"'.centre@example.com".lower() for l in json.load(sys.stdin)["learners"]))')"
check "Learner on the roster" rosterHasLearner "True"
GRADES="{\"classId\":\"$(get classId)\",\"assessment\":{\"externalId\":\"demo-$TAG-quiz\",\"name\":\"LMS Quiz $TAG\",\"type\":\"Quiz\",\"maxScore\":20},\"results\":[{\"learnerEmail\":\"learner.$TAG.centre@example.com\",\"score\":16}]}"
put gradesFirst "$(rest POST /services/apexrest/kem/v1/lms/grades "$GRADES" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("created"), d.get("status"))')"
check "Grades created as draft" gradesFirst "True Draft"
put gradesAgain "$(rest POST /services/apexrest/kem/v1/lms/grades "$GRADES" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("created"))')"
check "Re-sent grades update the same assessment" gradesAgain "False"
NUMS="$(rest GET '/services/apexrest/kem/v1/lms/events?limit=500' | python3 -c 'import json,sys; print(json.dumps([e["eventNumber"] for e in json.load(sys.stdin)["events"]]))')"
put lmsAcked "$(rest POST /services/apexrest/kem/v1/lms/events/ack "{\"events\": $NUMS, \"success\": true}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["acknowledged"] > 0)')"
check "LMS events acknowledged" lmsAcked "True"

say "4. Invoice and the ERP journal"
apex "
Id invoiceId = BillingService.createInvoice('{{enrolmentId}}', true);
Student_Invoice__c inv = [SELECT Name, Total__c FROM Student_Invoice__c WHERE Id = :invoiceId];
System.debug('KEM::invoiceName=' + inv.Name);
System.debug('KEM::invoiceTotal=' + inv.Total__c.setScale(2));
System.debug('KEM::invoicePrefix=' + inv.Name.startsWith('D3$TAG'));
FinanceExportService.Journal j = FinanceExportService.journal(Date.today(), Date.today(), '{{branchId}}');
System.debug('KEM::journalBalanced=' + j.balanced);
System.debug('KEM::journalDocuments=' + j.documents);
System.debug('KEM::erpEvent=' + [SELECT COUNT() FROM Integration_Event__c WHERE Target__c = 'ERP' AND Record_Id__c = :invoiceId]);
"
check "Invoice numbered with the centre's prefix" invoicePrefix "true"
check "Journal of the centre balanced" journalBalanced "true"
check "One document in the centre's journal" journalDocuments "1"
check "invoice.issued event for the ERP" erpEvent "1"
put apiJournal "$(rest GET "/services/apexrest/kem/v1/erp/journal?from=$(date +%F)&to=$(date +%F)&branch=D3-$TAG" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["balanced"] and abs(d["totalDebit"] - '"$(get invoiceTotal)"') < 0.005)')"
check "ERP API journal balanced at the invoice total" apiJournal "True"

say "5. Online payments stay off until a gateway is connected"
apex "
try { PaymentLinkService.createForStaff([SELECT Id FROM Student_Invoice__c WHERE Name = '{{invoiceName}}'].Id); System.debug('KEM::paymentsOff=false'); }
catch (AppException e) { System.debug('KEM::paymentsOff=' + e.getMessage().contains('not available')); }
"
check "Payment links refused while Off" paymentsOff "true"
put webhook "$(rest POST /services/apexrest/kem/v1/payments/webhook '{"token":"x","transactionId":"y"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["error"])')"
check "Webhook refuses calls without a secret" webhook "The payment webhook is not configured."

say "6. Retention scoring and desk"
apex "
RetentionService.assess(new Set<Id>{ '{{enrolmentId}}' });
CourseOfferingParticipant e = [SELECT Risk_Level__c, Risk_Score__c FROM CourseOfferingParticipant WHERE Id = '{{enrolmentId}}'];
System.debug('KEM::riskLevel=' + e.Risk_Level__c);
System.debug('KEM::deskLoads=' + (RetentionService.desk('{{branchId}}', 'All') != null));
"
check "New learner scored Low" riskLevel "Low"
check "Retention desk for the centre" deskLoads "true"

say "7. Library loan at the centre"
apex "
Library_Item__c item = new Library_Item__c(Name = '[KEM Demo] Atlas $TAG', Item_Code__c = 'D3-$TAG-B1', Branch__c = '{{branchId}}', Copies_Total__c = 1, Loan_Days__c = 14);
insert item;
Id loanId = LibraryService.issue(item.Id, '{{learnerId}}');
System.debug('KEM::loanStatus=' + [SELECT Status__c FROM Library_Loan__c WHERE Id = :loanId].Status__c);
System.debug('KEM::returnFine=' + LibraryService.returnLoan(loanId, 'Good'));
System.debug('KEM::portalLoans=' + LibraryService.learnerLoans('{{learnerContactId}}').size());
"
check "Book issued" loanStatus "On Loan"
check "Returned on time, no fine" returnFine "0"
check "Loan visible to the family" portalLoans "1"

say "8. Analytics and branch comparison"
apex "
AnalyticsService.Dashboard d = AnalyticsService.dashboard('{{branchId}}', 6);
System.debug('KEM::analyticsInvoiced=' + d.invoicedTotal.setScale(2));
System.debug('KEM::analyticsNew=' + d.newEnrolmentsTotal);
Boolean listed = false;
for (BranchTemplateService.BranchKpi k : BranchTemplateService.overview().branches) {
  listed |= k.code == 'D3-$TAG' && k.learners == 1 && k.activeClasses == 1;
}
System.debug('KEM::comparison=' + listed);
"
check "Analytics: invoiced at the centre" analyticsInvoiced "$(get invoiceTotal)"
check "Analytics: one new enrolment" analyticsNew "1"
check "Centre in the branch comparison (1 learner, 1 class)" comparison "true"

say "9. Operations console"
apex "
OpsService.Console c = OpsService.console();
Integer missing = 0;
for (OpsService.Schedule s : c.schedules) if (s.missing) missing++;
System.debug('KEM::schedules=' + c.schedules.size());
System.debug('KEM::schedulesMissing=' + missing);
System.debug('KEM::adminsNotInGroup=' + c.administratorsNotInGroup);
System.debug('KEM::consoleHealth=' + c.health);
"
check "All nine recurring jobs listed" schedules "9"
check "Every recurring job scheduled" schedulesMissing "0"
check "Administrators in the KEM Administrators group" adminsNotInGroup "0"
printf '    console health: %s (attention means work is waiting in a queue)\n' "$(get consoleHealth)"

printf '\n\033[1m%s passed, %s failed\033[0m — centre "[KEM Demo] Centre %s" (D3-%s), invoice %s\n' \
  "$PASS" "$FAIL" "$TAG" "$TAG" "$(get invoiceName)"
rm -rf "$WORK"
[[ "$FAIL" -eq 0 ]]
