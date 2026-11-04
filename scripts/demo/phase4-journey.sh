#!/usr/bin/env bash
# Phase 4 journey against the connected org (live Einstein): a referred family
# is answered with an AI-drafted reply that a counsellor reviews, converted,
# enrolled, put on the bus (monthly transport fee), registered for an exam with
# a hall ticket; the referrer is rewarded; the forecast, the Agentforce actions,
# the AI evaluation and the AI console are checked.
#
# Every run creates its own enquiry, learner, route and exam tagged with the
# run tag, at the demo branch DEMO-01. The signed-in user needs KEM AI User.
# Online payments stay Off and email delivery as configured.
#
# Usage: scripts/demo/phase4-journey.sh [run-tag]      e.g. scripts/demo/phase4-journey.sh P4A
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

echo "Kasetti Phase 4 journey — run tag $TAG — org $ORG"

say "1. A referred family enquires; Einstein drafts the reply and the counsellor sends an edited version"
apex "
Account referrer = [SELECT Id FROM Account WHERE Name LIKE 'Rohit Sharma%' AND Name LIKE '%[KEM Demo]%' LIMIT 1];
String code = ReferralService.codeFor(referrer.Id);
Branch__c b = [SELECT Id FROM Branch__c WHERE Branch_Code__c = 'DEMO-01'];
CourseOffering club = [SELECT Id, LearningCourseId FROM CourseOffering WHERE Name LIKE '[KEM Demo] Coding Club%' AND Branch__c = :b.Id AND Class_Status__c = 'Open' LIMIT 1];
Lead l = new Lead(FirstName = 'Learner', LastName = '$TAG [KEM Demo] Referred', Email = 'learner.$TAG.p4@example.com', Branch__c = b.Id, Interested_Course__c = club.LearningCourseId, Guardian_First_Name__c = 'Parent', Guardian_Last_Name__c = '$TAG [KEM Demo] Referred', Guardian_Email__c = 'parent.$TAG.p4@example.com', Guardian_Relationship__c = 'Mother', Learner_Birthdate__c = Date.newInstance(2015, 1, 15), Referral_Code__c = code.toLowerCase(), Submission_Id__c = 'KEM-P4-$TAG');
insert l;
System.debug('KEM::leadId=' + l.Id);
System.debug('KEM::classId=' + club.Id);
System.debug('KEM::referred=' + ([SELECT Referred_By__c FROM Lead WHERE Id = :l.Id].Referred_By__c == referrer.Id));
System.debug('KEM::referralStatus=' + [SELECT Status__c FROM Referral__c WHERE Enquiry__c = :l.Id].Status__c);
"
check "Enquiry linked to the referrer by code" referred "true"
check "Referral recorded" referralStatus "Enquired"
apex "
AiService.Result r = AiAssistantService.draftEnquiryReply('{{leadId}}', 'Offer a free trial class on Saturday');
System.debug('KEM::draftOk=' + r.ok);
System.debug('KEM::draftId=' + r.interactionId);
System.debug('KEM::draftMentionsTrial=' + r.text.containsIgnoreCase('trial'));
"
check "Einstein drafted a reply" draftOk "true"
check "The draft uses the counsellor's note" draftMentionsTrial "true"
apex "
String text = [SELECT Response__c FROM AI_Interaction__c WHERE Id = '{{draftId}}'].Response__c;
AiController.recordEnquiryReply('{{leadId}}', text + '\nWe look forward to meeting you. ($TAG)', '{{draftId}}');
AI_Interaction__c i = [SELECT Outcome__c, Edit_Ratio__c, Minutes_Saved__c FROM AI_Interaction__c WHERE Id = '{{draftId}}'];
System.debug('KEM::replyOutcome=' + i.Outcome__c);
System.debug('KEM::minutesSaved=' + (i.Minutes_Saved__c > 0));
System.debug('KEM::replyLogged=' + [SELECT COUNT() FROM Task WHERE WhoId = '{{leadId}}' AND Subject = 'Email reply (AI-assisted)']);
"
check "Reviewed and edited by the counsellor" replyOutcome "Edited"
check "Minutes saved measured" minutesSaved "true"
check "Reply recorded on the enquiry" replyLogged "1"

say "2. Staff policy question (knowledge base and live settings only)"
apex "
AiAssistantService.Answer a = AiAssistantService.askPolicy('How many days do families have to pay an invoice?');
System.debug('KEM::policyConfident=' + a.confident);
System.debug('KEM::policySource=' + a.sources.contains('Fees and invoices'));
System.debug('KEM::policyMentions14=' + a.answer.contains('14'));
"
check "Answer is confident" policyConfident "true"
check "Answer cites the fees article" policySource "true"
check "Answer quotes the live setting (14 days)" policyMentions14 "true"

say "3. Conversion and enrolment complete the referral; finance rewards the referrer"
apex "
EnquiryConversionService.ConversionRequest q = new EnquiryConversionService.ConversionRequest();
q.leadId = '{{leadId}}'; q.createGuardian = true; q.createApplication = false;
System.debug('KEM::learnerId=' + EnquiryConversionService.convert(q).learnerId);
"
apex "
EnrolmentService.EnrolmentRequest e = new EnrolmentService.EnrolmentRequest();
e.learnerAccountId = '{{learnerId}}'; e.offeringId = '{{classId}}';
System.debug('KEM::enrolmentId=' + EnrolmentService.enrol(e).enrolmentId);
Referral__c r = [SELECT Id, Status__c FROM Referral__c WHERE Enquiry__c = '{{leadId}}'];
System.debug('KEM::referralId=' + r.Id);
System.debug('KEM::referralAfterEnrolment=' + r.Status__c);
"
check "Referral enrolled" referralAfterEnrolment "Enrolled"
apex "
Id note = ReferralService.reward('{{referralId}}', false);
Credit_Note__c cn = [SELECT Name, Amount__c, Origin__c FROM Credit_Note__c WHERE Id = :note];
System.debug('KEM::rewardOrigin=' + cn.Origin__c);
System.debug('KEM::rewardAmount=' + cn.Amount__c.intValue());
System.debug('KEM::rewardNote=' + cn.Name);
"
check "Reward credit note" rewardOrigin "Referral"
check "Reward amount" rewardAmount "500"

say "4. Transport from next month on a new route"
apex "
Branch__c b = [SELECT Id FROM Branch__c WHERE Branch_Code__c = 'DEMO-01'];
Transport_Route__c route = new Transport_Route__c(Name = '[KEM Demo] Route $TAG', Route_Code__c = 'D4-$TAG', Branch__c = b.Id, Capacity__c = 2, Monthly_Fee__c = 1100, Morning_Start__c = '07:10');
insert route;
Transport_Stop__c stop = new Transport_Stop__c(Route__c = route.Id, Name = 'Stop $TAG', Sequence__c = 1, Pickup_Time__c = '07:25', Drop_Time__c = '16:00');
insert stop;
TransportService.AssignRequest q = new TransportService.AssignRequest();
q.learnerAccountId = '{{learnerId}}'; q.routeId = route.Id; q.stopId = stop.Id; q.startDate = Date.today().toStartOfMonth().addMonths(1);
Id a = TransportService.assign(q);
Transport_Assignment__c t = [SELECT Fee_Line__r.Fee_Type__c, Fee_Line__r.Line_Total__c, Fee_Line__r.Next_Bill_Date__c FROM Transport_Assignment__c WHERE Id = :a];
System.debug('KEM::routeId=' + route.Id);
System.debug('KEM::feeType=' + t.Fee_Line__r.Fee_Type__c);
System.debug('KEM::feeAmount=' + t.Fee_Line__r.Line_Total__c.intValue());
System.debug('KEM::feeFromNextMonth=' + (t.Fee_Line__r.Next_Bill_Date__c == Date.today().toStartOfMonth().addMonths(1)));
System.debug('KEM::seatsTaken=' + [SELECT Seats_Taken__c FROM Transport_Route__c WHERE Id = :route.Id].Seats_Taken__c.intValue());
System.debug('KEM::portalTransport=' + TransportService.forLearners(new Set<Id>{ '{{learnerId}}' }).size());
"
check "Monthly transport fee line" feeType "Transport"
check "Route fee" feeAmount "1100"
check "Billed from the start date" feeFromNextMonth "true"
check "Seat taken" seatsTaken "1"
check "Shown to the family" portalTransport "1"

say "5. Exam with a hall ticket"
apex "
Branch__c b = [SELECT Id FROM Branch__c WHERE Branch_Code__c = 'DEMO-01'];
Exam__c ex = new Exam__c(Name = '[KEM Demo] Exam $TAG', Exam_Code__c = 'D4-$TAG', Branch__c = b.Id, Start_Date__c = Date.today().addDays(21), Instructions__c = 'Bring this hall ticket.');
insert ex;
insert new Exam_Paper__c(Exam__c = ex.Id, Name = 'Coding $TAG', Course_Offering__c = '{{classId}}', Paper_Date__c = Date.today().addDays(21), Start_Time__c = '10:00', Duration_Minutes__c = 60, Max_Marks__c = 50, Weight__c = 10);
System.debug('KEM::examId=' + ex.Id);
System.debug('KEM::registered=' + (ExamService.registerCandidates(ex.Id).processed > 0));
ExamService.checkEligibility(ex.Id);
System.debug('KEM::learnerEligible=' + [SELECT Status__c FROM Exam_Candidate__c WHERE Exam__c = :ex.Id AND Learner_Account__c = '{{learnerId}}'].Status__c);
"
check "Candidates registered from the class" registered "true"
check "New learner eligible" learnerEligible "Eligible"
apex "
List<Id> rooms = new List<Id>();
for (Room__c r : [SELECT Id FROM Room__c WHERE Branch__r.Branch_Code__c = 'DEMO-01' AND Active__c = TRUE AND Room_Type__c != 'Virtual' ORDER BY Capacity__c DESC]) rooms.add(r.Id);
ExamService.allocateSeats('{{examId}}', rooms);
ExamService.StepResult s = ExamService.issueTickets('{{examId}}');
Exam_Candidate__c c = [SELECT Name, Status__c, Seat_Number__c FROM Exam_Candidate__c WHERE Exam__c = '{{examId}}' AND Learner_Account__c = '{{learnerId}}'];
System.debug('KEM::ticketStatus=' + c.Status__c);
System.debug('KEM::hasSeat=' + (c.Seat_Number__c != null));
System.debug('KEM::hallTicket=' + c.Name);
System.debug('KEM::examStatus=' + [SELECT Status__c FROM Exam__c WHERE Id = '{{examId}}'].Status__c);
"
check "Hall ticket issued" ticketStatus "Ticket Issued"
check "Seat allocated" hasSeat "true"
check "Exam status" examStatus "Hall Tickets Issued"

say "6. Forecast, Agentforce actions and the AI evaluation"
apex "
ForecastService.Forecast f = ForecastService.forecast([SELECT Id FROM Branch__c WHERE Branch_Code__c = 'DEMO-01'].Id, 3);
System.debug('KEM::forecastFigures=' + (f.showEnrolments && f.showFinance));
System.debug('KEM::forecastMethod=' + f.enrolments.method);
AgentPolicyAnswer.Request p = new AgentPolicyAnswer.Request(); p.question = 'Can I approve a refund I requested myself?';
AgentPolicyAnswer.Response pr = AgentPolicyAnswer.answer(new List<AgentPolicyAnswer.Request>{ p })[0];
System.debug('KEM::agentPolicySourced=' + String.isNotBlank(pr.sources));
AgentForecast.Request fr = new AgentForecast.Request(); fr.branch = 'demo-01';
System.debug('KEM::agentForecast=' + AgentForecast.forecast(new List<AgentForecast.Request>{ fr })[0].forecast.startsWith('New enrolments'));
"
check "Forecast figures for the branch" forecastFigures "true"
check "Agentforce policy action cites a source" agentPolicySourced "true"
check "Agentforce forecast action" agentForecast "true"
apex "
AiEvaluationService.RunSummary s = AiEvaluationService.run(null);
System.debug('KEM::evalAllPassed=' + (s.passed == s.cases));
System.debug('KEM::evalCases=' + s.cases);
System.debug('KEM::evalLabel=' + s.runLabel);
"
check "Every evaluation case passes" evalAllPassed "true"

say "7. AI console: measured benefit"
apex "
AiConsoleService.Console c = AiConsoleService.console(30);
System.debug('KEM::aiCalls=' + (c.totals.calls > 0));
System.debug('KEM::agentCalls=' + (c.agentCalls > 0));
System.debug('KEM::minutesTotal=' + (c.totals.minutesSaved > 0));
System.debug('KEM::evaluationShown=' + (c.evaluation != null));
System.debug('KEM::acceptance=' + c.totals.acceptanceRate);
System.debug('KEM::minutes=' + c.totals.minutesSaved);
"
check "AI requests measured" aiCalls "true"
check "Agentforce actions measured" agentCalls "true"
check "Minutes saved measured" minutesTotal "true"
check "Latest evaluation shown" evaluationShown "true"
printf '    used (as is or edited): %s%%, minutes saved: %s\n' "$(get acceptance)" "$(get minutes)"

printf '\n\033[1m%s passed, %s failed\033[0m — learner "Learner %s [KEM Demo] Referred", hall ticket %s, reward %s, evaluation %s (%s cases)\n' \
  "$PASS" "$FAIL" "$TAG" "$(get hallTicket)" "$(get rewardNote)" "$(get evalLabel)" "$(get evalCases)"
rm -rf "$WORK"
[[ "$FAIL" -eq 0 ]]
