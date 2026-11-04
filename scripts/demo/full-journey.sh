#!/usr/bin/env bash
# Full Phase 1 journey against the connected org, one transaction per step,
# exactly as users would do it: enquiry → conversion → application → offer →
# enrolment → timetable → attendance → assessment → invoice → gateway payment →
# reconciliation → documents → portal view.
#
# Every run creates its own learner, guardian and class (prefixed [KEM Demo]),
# so it never collides with earlier demo data. Requires the demo branch
# DEMO-01 and course KEM-DEMO-MATH (created in Phase 1).
#
# Usage: scripts/demo/full-journey.sh [run-tag]      e.g. scripts/demo/full-journey.sh R2
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

echo "Kasetti full-journey demo — run tag $TAG — org $ORG"

say "0. Set-up: a fresh class for this run (capacity 10, weekly pattern)"
apex "
Branch__c b = [SELECT Id FROM Branch__c WHERE Branch_Code__c = 'DEMO-01'];
LearningCourse c = [SELECT Id FROM LearningCourse WHERE External_ID__c = 'KEM-DEMO-MATH'];
Date monday = Date.today().addDays(1);
while (Datetime.newInstance(monday, Time.newInstance(12, 0, 0, 0)).format('E') != 'Mon') monday = monday.addDays(1);
CourseOffering o = new CourseOffering(Name = '[KEM Demo] Journey $TAG', LearningCourseId = c.Id, Branch__c = b.Id,
  EnrollmentCapacity = 10, Delivery_Mode__c = 'Classroom', Class_Status__c = 'Open',
  StartDate = Datetime.newInstance(Date.today().addDays(-1), Time.newInstance(8, 0, 0, 0)),
  EndDate = Datetime.newInstance(monday.addDays(14), Time.newInstance(20, 0, 0, 0)));
insert o;
insert new CourseOfferingSchedule(CourseOfferingId = o.Id, Description = 'Mondays 16:00', IsMonday = true,
  StartTime = Time.newInstance(16, 0, 0, 0), EndTime = Time.newInstance(17, 30, 0, 0), StartDate = monday);
System.debug('KEM::classId=' + o.Id);
System.debug('KEM::courseId=' + c.Id);
System.debug('KEM::branchId=' + b.Id);
"

say "1. Website enquiry with guardian"
apex "
insert new Lead(FirstName = 'Demo', LastName = 'Learner $TAG [KEM Demo]', Email = 'learner.$TAG@example.com',
  MobilePhone = '+919800000001', Branch__c = '{{branchId}}', Enquiry_Channel__c = 'Website',
  Interested_Course__c = '{{courseId}}', Guardian_First_Name__c = 'Demo', Guardian_Last_Name__c = 'Parent $TAG [KEM Demo]',
  Guardian_Email__c = 'parent.$TAG@example.com', Guardian_Phone__c = '+919800000002', Guardian_Relationship__c = 'Mother',
  Learner_Birthdate__c = Date.today().addYears(-11));
Lead l = [SELECT Id, Status, OwnerId FROM Lead WHERE LastName = 'Learner $TAG [KEM Demo]' LIMIT 1];
System.debug('KEM::leadId=' + l.Id);
System.debug('KEM::leadStatus=' + l.Status);
"
check "Enquiry captured" leadStatus "New"

say "2. Convert enquiry → learner, guardian, application"
apex "
EnquiryConversionService.ConversionRequest r = new EnquiryConversionService.ConversionRequest();
r.leadId = '{{leadId}}'; r.createGuardian = true; r.createApplication = true;
EnquiryConversionService.ConversionResult res = EnquiryConversionService.convert(r);
System.debug('KEM::learnerId=' + res.learnerId);
System.debug('KEM::guardianId=' + res.guardianId);
System.debug('KEM::applicationId=' + res.applicationId);
System.debug('KEM::converted=' + [SELECT IsConverted FROM Lead WHERE Id = '{{leadId}}'].IsConverted);
"
check "Enquiry converted" converted "true"

say "3. Checklist accepted/waived"
apex "
Integer n = 0;
for (DocumentChecklistItem i : [SELECT Id, IsRequired FROM DocumentChecklistItem WHERE ParentRecordId = '{{applicationId}}']) {
  ApplicationService.updateChecklistItem(i.Id, i.IsRequired ? 'Accepted' : 'Waived', 'Demo verification'); n++;
}
System.debug('KEM::checklistItems=' + n);
"

say "4. Review → ready for decision → Admit"
apex "
Id a = '{{applicationId}}';
ApplicationService.submitForReview(a);
ApplicationService.markReadyForDecision(a);
ApplicationService.decide(a, 'Admit', null, 14);
IndividualApplication app = [SELECT Name, Eligibility_Status__c, Offer_Status__c FROM IndividualApplication WHERE Id = :a];
System.debug('KEM::applicationName=' + app.Name);
System.debug('KEM::eligibility=' + app.Eligibility_Status__c);
System.debug('KEM::offer=' + app.Offer_Status__c);
"
check "Offer made" offer "Offered"

say "5. Family accepts the offer"
apex "
ApplicationService.respondToOffer('{{applicationId}}', true);
System.debug('KEM::offerResponse=' + [SELECT Offer_Status__c FROM IndividualApplication WHERE Id = '{{applicationId}}'].Offer_Status__c);
"
check "Offer accepted" offerResponse "Accepted"

say "6. Enrol in the class at the agreed price"
apex "
EnrolmentService.EnrolmentRequest r = new EnrolmentService.EnrolmentRequest();
r.learnerAccountId = '{{learnerId}}'; r.offeringId = '{{classId}}'; r.applicationId = '{{applicationId}}';
Id e = EnrolmentService.enrol(r).enrolmentId;
CourseOfferingParticipant p = [SELECT ParticipationStatus, Agreed_Total__c FROM CourseOfferingParticipant WHERE Id = :e];
System.debug('KEM::enrolmentId=' + e);
System.debug('KEM::enrolment=' + p.ParticipationStatus);
System.debug('KEM::agreedTotal=' + p.Agreed_Total__c);
System.debug('KEM::applicationStatus=' + [SELECT Status FROM IndividualApplication WHERE Id = '{{applicationId}}'].Status);
"
check "Enrolled" enrolment "Enrolled"
check "Application closed" applicationStatus "Enrolled"

say "7. Generate the timetable and add a session happening now"
apex "
SessionService.GenerationResult g = SessionService.generate('{{classId}}');
Id s = SessionService.addSession('{{classId}}', System.now().addMinutes(-5), System.now().addMinutes(55), 'Make-up', null);
System.debug('KEM::sessionsGenerated=' + g.created);
System.debug('KEM::sessionId=' + s);
"

say "8. Mark attendance"
apex "
AttendanceService.Register reg = AttendanceService.getRegister('{{sessionId}}');
for (AttendanceService.RegisterRow row : reg.rows) row.status = 'Present';
AttendanceService.saveRegister('{{sessionId}}', reg.rows, 'Present');
System.debug('KEM::attendanceRate=' + [SELECT Attendance_Rate__c FROM CourseOfferingParticipant WHERE Id = '{{enrolmentId}}'].Attendance_Rate__c.intValue());
"
check "Attendance recorded" attendanceRate "100"

say "9. Assessment: enter score and publish"
apex "
Course_Assessment__c a = new Course_Assessment__c(Name = '[KEM Demo] Quiz $TAG', Course_Offering__c = '{{classId}}',
  Assessment_Type__c = 'Quiz', Max_Score__c = 20, Assessment_Date__c = Date.today(), Grade_Scale__c = 'Standard');
insert a;
AssessmentService.Gradebook book = AssessmentService.getGradebook(a.Id);
for (AssessmentService.ResultRow r : book.rows) { r.score = 17; r.feedback = 'Well done.'; }
AssessmentService.saveResults(a.Id, book.rows);
AssessmentService.publish(a.Id);
System.debug('KEM::grade=' + [SELECT Grade__c FROM Assessment_Result__c WHERE Course_Assessment__c = :a.Id LIMIT 1].Grade__c);
"
check "Result published (17/20 = 85%)" grade "A"

say "10. Invoice issued to the fee-paying guardian"
apex "
Id i = BillingService.createInvoice('{{enrolmentId}}', true);
Student_Invoice__c inv = [SELECT Name, Total__c, Bill_To__r.Name, Status__c FROM Student_Invoice__c WHERE Id = :i];
System.debug('KEM::invoiceId=' + i);
System.debug('KEM::invoiceNumber=' + inv.Name);
System.debug('KEM::invoiceStatus=' + inv.Status__c);
System.debug('KEM::billTo=' + inv.Bill_To__r.Name);
System.debug('KEM::invoiceMatchesAgreed=' + (inv.Total__c == {{agreedTotal}}));
"
check "Invoice issued" invoiceStatus "Issued"
check "Invoice equals agreed price" invoiceMatchesAgreed "true"

say "11. Payment gateway notifications (pending → success → retry)"
pay() {
  sf api request rest /services/apexrest/kem/v1/payments --method POST --target-org "$ORG" --include \
    --body "{\"transactionId\":\"kem_demo_$TAG\",\"invoiceNumber\":\"$(get invoiceNumber)\",\"amount\":$(get agreedTotal),\"status\":\"$1\",\"method\":\"Online Gateway\"}" 2>/dev/null |
    grep -E '^HTTP/|"status"' | tr -d '\n' | sed -E 's/.*HTTP\/[0-9.]+ ([0-9]+).*"status" *: *"([A-Za-z]+)".*/\1 \2/'
}
r1=$(pay pending); echo "    pending → $r1"
r2=$(pay success); echo "    success → $r2"
r3=$(pay success); echo "    retry   → $r3"
[[ "$r1" == "201 Pending" ]] && ok "Pending payment recorded (201)" || bad "pending: $r1"
[[ "$r2" == "201 Confirmed" ]] && ok "Payment confirmed (201)" || bad "success: $r2"
[[ "$r3" == "200 Confirmed" ]] && ok "Retry is idempotent (200, no second payment)" || bad "retry: $r3"

say "12. Reconciliation, documents and the family's portal view"
sleep 20 # background jobs file the PDFs
apex "
Student_Invoice__c i = [SELECT Status__c, Balance_Due__c, Enrolment__r.Billing_Status__c, Bill_To__c, Learner__c FROM Student_Invoice__c WHERE Id = '{{invoiceId}}'];
Student_Payment__c p = [SELECT Id, Reconciliation_Status__c, Receipt_Number__c FROM Student_Payment__c WHERE Gateway_Transaction_Id__c = 'kem_demo_$TAG'];
System.debug('KEM::invoiceFinal=' + i.Status__c);
System.debug('KEM::balanceDue=' + i.Balance_Due__c.intValue());
System.debug('KEM::enrolmentBilling=' + i.Enrolment__r.Billing_Status__c);
System.debug('KEM::reconciliation=' + p.Reconciliation_Status__c);
System.debug('KEM::receipt=' + p.Receipt_Number__c);
System.debug('KEM::offerLetter=' + (DocumentService.existing('{{applicationId}}', DocumentService.OFFER_LETTER) != null));
System.debug('KEM::invoicePdf=' + (DocumentService.existing(i.Id, DocumentService.INVOICE) != null));
System.debug('KEM::receiptPdf=' + (DocumentService.existing(p.Id, DocumentService.RECEIPT) != null));
PortalService.Home h = PortalService.homeFor(i.Bill_To__c);
PortalService.LearnerDetail d = PortalService.learnerFor(i.Bill_To__c, i.Learner__c);
System.debug('KEM::portalLearners=' + h.learners.size());
System.debug('KEM::portalDue=' + h.totalDue.intValue());
System.debug('KEM::portalResults=' + d.results.size());
"
check "Invoice paid" invoiceFinal "Paid"
check "Nothing due" balanceDue "0"
check "Enrolment billing" enrolmentBilling "Paid"
check "Payment reconciled" reconciliation "Reconciled"
check "Offer letter PDF filed" offerLetter "true"
check "Invoice PDF filed" invoicePdf "true"
check "Receipt PDF filed" receiptPdf "true"
check "Guardian sees the learner in the portal" portalLearners "1"
check "Portal shows nothing due" portalDue "0"
check "Portal shows the published result" portalResults "1"

printf '\n\033[1m%s passed, %s failed\033[0m — learner "Demo Learner %s [KEM Demo]", application %s, invoice %s, receipt %s\n' \
  "$PASS" "$FAIL" "$TAG" "$(get applicationName)" "$(get invoiceNumber)" "$(get receipt)"
rm -rf "$WORK"
[[ "$FAIL" -eq 0 ]]
