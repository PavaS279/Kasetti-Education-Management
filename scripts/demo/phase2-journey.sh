#!/usr/bin/env bash
# Phase 2 journey against the connected org, one transaction per step, as staff
# would do it: waitlist → held seat → accept → transfer → invoice with an
# overpayment → credit applied to the sibling → recurring month → instalments →
# withdrawal credit and refund → teacher absence and cover → grading and report
# card → the family's portal view → operations console.
#
# Every run creates its own guardian, two children and two classes (prefixed
# [KEM Demo]), so it never collides with earlier demo data. Requires the demo
# branch DEMO-01, the monthly course KEM-DEMO-CODING (F2.3) and Anjali Advisor
# as a Teacher at the branch (F2.6). Email delivery stays as configured (Off in
# this org), so no email leaves the org.
#
# Usage: scripts/demo/phase2-journey.sh [run-tag]      e.g. scripts/demo/phase2-journey.sh P2
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

echo "Kasetti Phase 2 journey — run tag $TAG — org $ORG"

say "0. Set-up: guardian with two children, a one-seat class (A) and a five-seat class (B)"
apex "
Branch__c b = [SELECT Id FROM Branch__c WHERE Branch_Code__c = 'DEMO-01'];
LearningCourse c = [SELECT Id FROM LearningCourse WHERE External_ID__c = 'KEM-DEMO-CODING'];
Datetime startAt = Datetime.newInstance(Date.today().addDays(-7), Time.newInstance(8, 0, 0, 0));
Datetime endAt = Datetime.newInstance(Date.today().addMonths(5), Time.newInstance(20, 0, 0, 0));
CourseOffering a = new CourseOffering(Name = '[KEM Demo] P2 Class A $TAG', LearningCourseId = c.Id, Branch__c = b.Id,
  EnrollmentCapacity = 1, Delivery_Mode__c = 'Classroom', Class_Status__c = 'Open', StartDate = startAt, EndDate = endAt,
  Teacher_User__c = UserInfo.getUserId());
CourseOffering bb = new CourseOffering(Name = '[KEM Demo] P2 Class B $TAG', LearningCourseId = c.Id, Branch__c = b.Id,
  EnrollmentCapacity = 5, Delivery_Mode__c = 'Classroom', Class_Status__c = 'Open', StartDate = startAt, EndDate = endAt);
insert new List<CourseOffering>{ a, bb };
List<Account> people = new List<Account>{
  PersonAccountService.buildPerson('Guardian $TAG', '[KEM Demo] Phase2', 'guardian.$TAG@example.com', null, b.Id, 'Guardian'),
  PersonAccountService.buildPerson('Elder $TAG', '[KEM Demo] Phase2', null, null, b.Id, 'Learner'),
  PersonAccountService.buildPerson('Younger $TAG', '[KEM Demo] Phase2', null, null, b.Id, 'Learner')
};
insert people;
Map<Id, Account> byId = new Map<Id, Account>([SELECT Id, PersonContactId FROM Account WHERE Id IN :people]);
List<GuardianRelationshipService.GuardianLink> links = new List<GuardianRelationshipService.GuardianLink>();
for (Integer i = 1; i <= 2; i++) {
  GuardianRelationshipService.GuardianLink l = new GuardianRelationshipService.GuardianLink();
  l.guardianContactId = byId.get(people[0].Id).PersonContactId;
  l.learnerContactId = byId.get(people[i].Id).PersonContactId;
  l.relationship = 'Mother';
  links.add(l);
}
GuardianRelationshipService.link(links);
EnrolmentService.EnrolmentRequest r = new EnrolmentService.EnrolmentRequest();
r.learnerAccountId = people[1].Id;
r.offeringId = a.Id;
Id elderEnrolment = EnrolmentService.enrol(r).enrolmentId;
Datetime s = Datetime.newInstance(Date.today().addDays(1), Time.newInstance(16, 0, 0, 0));
insert new Class_Session__c(Course_Offering__c = a.Id, Branch__c = b.Id, Teacher_User__c = UserInfo.getUserId(),
  Start__c = s, End__c = s.addHours(1), Status__c = 'Scheduled', Session_Type__c = 'Class');
System.debug('KEM::classA=' + a.Id);
System.debug('KEM::classB=' + bb.Id);
System.debug('KEM::guardian=' + byId.get(people[0].Id).PersonContactId);
System.debug('KEM::elder=' + people[1].Id);
System.debug('KEM::elderContact=' + byId.get(people[1].Id).PersonContactId);
System.debug('KEM::younger=' + people[2].Id);
System.debug('KEM::elderEnrolment=' + elderEnrolment);
System.debug('KEM::classAStatus=' + [SELECT Class_Status__c FROM CourseOffering WHERE Id = :a.Id].Class_Status__c);
"
check "Class A full with the elder child" classAStatus "Full"

say "1. Waitlist: the younger child queues; a second seat opens and is held for them"
apex "
WaitlistService.JoinRequest j = new WaitlistService.JoinRequest();
j.learnerAccountId = '{{younger}}';
j.offeringId = '{{classA}}';
Id entryId = WaitlistService.join(j);
update new CourseOffering(Id = '{{classA}}', EnrollmentCapacity = 2);
Waitlist_Entry__c e = [SELECT Status__c, Offer_Expires__c FROM Waitlist_Entry__c WHERE Id = :entryId];
System.debug('KEM::entry=' + entryId);
System.debug('KEM::entryStatus=' + e.Status__c);
System.debug('KEM::offerNotice=' + ([SELECT COUNT() FROM Message__c WHERE Related_Record_Id__c = :entryId AND Event__c = 'Waitlist_Offer' AND Channel__c = 'Portal'] > 0));
"
check "Seat offered and held" entryStatus "Offered"
check "Guardian notified in the portal" offerNotice "true"

say "2. The family accepts the offer"
apex "
Id enrolmentId = WaitlistService.accept('{{entry}}');
System.debug('KEM::youngerEnrolment=' + enrolmentId);
System.debug('KEM::entryFinal=' + [SELECT Status__c FROM Waitlist_Entry__c WHERE Id = '{{entry}}'].Status__c);
System.debug('KEM::classAFinal=' + [SELECT Class_Status__c FROM CourseOffering WHERE Id = '{{classA}}'].Class_Status__c);
"
check "Waitlist entry enrolled" entryFinal "Enrolled"
check "Class A full again" classAFinal "Full"

say "3. Transfer: the younger child moves to class B before anything is invoiced"
apex "
TransferService.TransferRequest t = new TransferService.TransferRequest();
t.enrolmentId = '{{youngerEnrolment}}';
t.targetOfferingId = '{{classB}}';
t.reason = '[KEM Demo] Weekday timing suits better';
TransferService.TransferPreview p = TransferService.preview(t);
Id newId = TransferService.transfer(t);
System.debug('KEM::transferOutcome=' + p.billingOutcome.substringBefore(':'));
System.debug('KEM::youngerEnrolment=' + newId);
System.debug('KEM::oldStatus=' + [SELECT ParticipationStatus FROM CourseOfferingParticipant WHERE Id = '{{youngerEnrolment}}'].ParticipationStatus);
System.debug('KEM::classAAfterTransfer=' + [SELECT Class_Status__c FROM CourseOffering WHERE Id = '{{classA}}'].Class_Status__c);
"
check "Not invoiced yet: billed at the new class's price" transferOutcome "Not invoiced yet"
check "Old enrolment closed" oldStatus "Withdrew"
check "Seat in class A released" classAAfterTransfer "Open"

say "4. First invoice for the elder child, overpaid by 500 and held as credit"
apex "
Id invoiceId = BillingService.createInvoice('{{elderEnrolment}}', true);
Student_Invoice__c i = [SELECT Name, Total__c FROM Student_Invoice__c WHERE Id = :invoiceId];
BillingService.PaymentRequest p = new BillingService.PaymentRequest();
p.invoiceId = invoiceId; p.amount = i.Total__c + 500; p.method = 'UPI'; p.reference = 'KEM-DEMO-P2-$TAG';
BillingService.PaymentResult paid = BillingService.recordPayment(p);
Id creditId = CreditService.holdOverpayment(paid.paymentId);
System.debug('KEM::firstInvoice=' + invoiceId);
System.debug('KEM::firstInvoiceName=' + i.Name);
System.debug('KEM::firstTotal=' + i.Total__c.intValue());
System.debug('KEM::overpayment=' + paid.reconciliationStatus);
System.debug('KEM::credit=' + creditId);
System.debug('KEM::creditAmount=' + [SELECT Amount__c FROM Credit_Note__c WHERE Id = :creditId].Amount__c.intValue());
"
check "Admission 1,180 + first month 2,950" firstTotal "4130"
check "Overpayment raised an exception" overpayment "Exception"
check "Held as credit" creditAmount "500"

say "5. The younger child's first invoice uses the family's credit automatically"
apex "
Id invoiceId = BillingService.createInvoice('{{youngerEnrolment}}', true);
Student_Invoice__c i = [SELECT Total__c, Amount_Paid__c, Status__c FROM Student_Invoice__c WHERE Id = :invoiceId];
System.debug('KEM::creditApplied=' + i.Amount_Paid__c.intValue());
System.debug('KEM::secondStatus=' + i.Status__c);
System.debug('KEM::creditStatus=' + [SELECT Status__c FROM Credit_Note__c WHERE Id = '{{credit}}'].Status__c);
"
check "Credit applied" creditApplied "500"
check "Invoice partly paid" secondStatus "Partially Paid"
check "Credit used up" creditStatus "Used"

say "6. Next month is billed (as the nightly job does) and split into two instalments"
apex "
CourseOfferingParticipant e = [SELECT StartDate FROM CourseOfferingParticipant WHERE Id = '{{elderEnrolment}}'];
Id nextId = BillingService.billDuePeriods('{{elderEnrolment}}', e.StartDate.addMonths(1));
BillingService.PlanRequest plan = new BillingService.PlanRequest();
plan.invoiceId = nextId; plan.count = 2; plan.firstDueDate = Date.today().addDays(10);
BillingService.createPlan(plan);
Student_Invoice__c i = [SELECT Total__c, Billing_Period__c, Instalment_Count__c FROM Student_Invoice__c WHERE Id = :nextId];
System.debug('KEM::nextTotal=' + i.Total__c.intValue());
System.debug('KEM::nextPeriod=' + i.Billing_Period__c);
System.debug('KEM::instalments=' + i.Instalment_Count__c.intValue());
"
check "Second month" nextTotal "2950"
check "Two instalments" instalments "2"

say "7. Withdrawal credit on the paid first invoice, part refunded (auto-approved) and paid out"
apex "
CreditService.CreditRequest cr = new CreditService.CreditRequest();
cr.sourceInvoiceId = '{{firstInvoice}}'; cr.amount = 1000; cr.origin = 'Withdrawal'; cr.reason = '[KEM Demo] Missed two weeks for a family event';
Id creditId = CreditService.issueForInvoice(cr);
CreditService.RefundRequest rr = new CreditService.RefundRequest();
rr.creditNoteId = creditId; rr.amount = 600; rr.method = 'UPI'; rr.reason = '[KEM Demo] Refund requested by the family';
Id refundId = CreditService.requestRefund(rr);
Refund__c r = [SELECT Status__c, Auto_Approved__c FROM Refund__c WHERE Id = :refundId];
System.debug('KEM::refundApproval=' + (r.Auto_Approved__c ? 'Auto-approved' : r.Status__c));
CreditService.markRefundPaid(refundId, 'KEM-DEMO-REFUND-$TAG', null);
Credit_Note__c n = [SELECT Balance__c, Status__c FROM Credit_Note__c WHERE Id = :creditId];
System.debug('KEM::refundStatus=' + [SELECT Status__c FROM Refund__c WHERE Id = :refundId].Status__c);
System.debug('KEM::creditLeft=' + n.Balance__c.intValue());
"
check "Refund within the limit" refundApproval "Auto-approved"
check "Refund paid" refundStatus "Paid"
check "Credit left for the next invoice" creditLeft "400"

say "8. The class teacher is absent tomorrow; the cover desk suggests a teacher who is assigned"
apex "
CoverService.AbsenceRequest r = new CoverService.AbsenceRequest();
r.startAt = Datetime.newInstance(Date.today().addDays(1), Time.newInstance(0, 0, 0, 0));
r.endAt = Datetime.newInstance(Date.today().addDays(1), Time.newInstance(23, 0, 0, 0));
r.reason = 'Training'; r.notes = '[KEM Demo] Phase 2 run $TAG';
Id absenceId = CoverService.recordAbsence(r);
Class_Session__c s = [SELECT Id FROM Class_Session__c WHERE Course_Offering__c = '{{classA}}' LIMIT 1];
List<CoverService.Candidate> options = CoverService.candidates(s.Id);
CoverService.Candidate pick;
for (CoverService.Candidate c : options) { if (pick == null && c.free) pick = c; }
CoverService.assignCover(s.Id, pick.userId, '[KEM Demo] Covering during training');
System.debug('KEM::coverTeacher=' + pick.name);
System.debug('KEM::absenceStatus=' + [SELECT Status__c FROM Staff_Absence__c WHERE Id = :absenceId].Status__c);
System.debug('KEM::sessionCovered=' + [SELECT Teacher_Attendance__c FROM Class_Session__c WHERE Id = :s.Id].Teacher_Attendance__c);
"
check "Absence covered" absenceStatus "Covered"
check "Session marked substituted" sessionCovered "Substituted"

say "9. A quiz is published and the class grades are finalised (report cards issued)"
apex "
Course_Assessment__c q = new Course_Assessment__c(Name = '[KEM Demo] P2 Quiz $TAG', Course_Offering__c = '{{classA}}',
  Assessment_Type__c = 'Quiz', Max_Score__c = 20, Assessment_Date__c = Date.today());
insert q;
AssessmentService.Gradebook book = AssessmentService.getGradebook(q.Id);
for (AssessmentService.ResultRow row : book.rows) { row.score = 18; }
AssessmentService.saveResults(q.Id, book.rows);
AssessmentService.publish(q.Id);
System.debug('KEM::reportCards=' + GradingService.finalise('{{classA}}'));
CourseOfferingParticipant e = [SELECT Course_Grade__c, Grade_Status__c FROM CourseOfferingParticipant WHERE Id = '{{elderEnrolment}}'];
System.debug('KEM::courseGrade=' + e.Course_Grade__c);
System.debug('KEM::gradeStatus=' + e.Grade_Status__c);
"
check "18/20 = 90%" courseGrade "A+"
check "Grades final" gradeStatus "Final"

say "10. The family's portal: inbox, grades with report card, documents, instalments, credit"
sleep 25 # background jobs file the PDFs
apex "
PortalService.Home h = PortalService.homeFor('{{guardian}}');
PortalService.LearnerDetail d = PortalService.learnerFor('{{guardian}}', '{{elderContact}}');
Set<String> kinds = new Set<String>();
for (PortalService.DocumentItem doc : d.documents) kinds.add(doc.kind);
Integer instalments = 0;
for (PortalService.InvoiceItem i : d.invoices) instalments += i.instalments.size();
System.debug('KEM::portalChildren=' + h.learners.size());
System.debug('KEM::portalMessages=' + (h.messages.size() >= 5));
System.debug('KEM::portalGrade=' + d.grades[0].grade + ' ' + d.grades[0].status);
System.debug('KEM::portalReportCard=' + (d.grades[0].reportCardVersionId != null));
System.debug('KEM::portalDocuments=' + kinds.contains('Invoice') + '/' + kinds.contains('Receipt') + '/' + kinds.contains('Report Card'));
System.debug('KEM::portalInstalments=' + instalments);
System.debug('KEM::portalCredit=' + d.creditBalance.intValue());
"
check "Both children in the portal" portalChildren "2"
check "Notices in the inbox" portalMessages "true"
check "Course grade" portalGrade "A+ Final"
check "Report card available" portalReportCard "true"
check "Invoice, receipt and report card PDFs" portalDocuments "true/true/true"
check "Instalments visible" portalInstalments "2"
check "Remaining credit visible" portalCredit "400"

say "11. Operations console"
apex "
OpsService.Console c = OpsService.console();
Integer missing = 0;
for (OpsService.Schedule s : c.schedules) if (s.missing) missing++;
System.debug('KEM::schedulesMissing=' + missing);
System.debug('KEM::consoleHealth=' + c.health);
"
check "Every recurring job scheduled" schedulesMissing "0"
printf '    console health: %s (attention means work is waiting in a queue)\n' "$(get consoleHealth)"

printf '\n\033[1m%s passed, %s failed\033[0m — guardian "Guardian %s [KEM Demo] Phase2", invoice %s\n' \
  "$PASS" "$FAIL" "$TAG" "$(get firstInvoiceName)"
rm -rf "$WORK"
[[ "$FAIL" -eq 0 ]]
