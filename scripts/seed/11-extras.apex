// KTEdutech seed 11/11: waitlist for the full Python class, credit notes and refunds, a teacher absence
// with cover, and retention risk scoring. Run after payments (08) and bus riders (10). Idempotent per section.
Date today = Date.today();

// ---- Waitlist: Python for Kids – Saturday 12:00 (Indiranagar) is full ----
CourseOffering pyt = [SELECT Id, Branch__c FROM CourseOffering WHERE SectionNumber = 'KT-IND-PYT-SAT'];
if ([SELECT COUNT() FROM Waitlist_Entry__c WHERE Course_Offering__c = :pyt.Id] == 0) {
  Set<Id> inClass = new Set<Id>();
  for (CourseOfferingParticipant p : [SELECT ParticipantContact.AccountId FROM CourseOfferingParticipant WHERE CourseOfferingId = :pyt.Id]) inClass.add(p.ParticipantContact.AccountId);
  Integer added = 0;
  List<String> notes = new List<String>{ 'Prefers Saturday; cannot do weekdays.', 'Sibling already studies Abacus here.', 'Waiting since the open house.' };
  for (Account a : [SELECT Id FROM Account WHERE Branch__c = :pyt.Branch__c AND External_Id__c LIKE 'KT-FAM-%-L%' AND PersonBirthdate <= :today.addYears(-10) AND PersonBirthdate >= :today.addYears(-15) ORDER BY External_Id__c DESC LIMIT 10]) {
    if (inClass.contains(a.Id) || added == 3) continue;
    WaitlistService.JoinRequest j = new WaitlistService.JoinRequest();
    j.learnerAccountId = a.Id; j.offeringId = pyt.Id; j.priority = added == 1 ? 1 : 2; j.notes = notes[added];
    WaitlistService.join(j);
    added++;
  }
  System.debug('SEED11 waitlist+' + added);
  return;
}

// ---- Credit notes and refunds ----
if ([SELECT COUNT() FROM Credit_Note__c WHERE Reason__c LIKE 'Missed%' OR Reason__c LIKE 'Art batch%'] == 0) {
  List<Student_Invoice__c> paid = [SELECT Id, Total__c FROM Student_Invoice__c WHERE Status__c = 'Paid' AND Enrolment__r.CourseOffering.SectionNumber IN ('KT-KOR-ART-SUN','KT-IND-ENG-TT') AND Issue_Date__c >= 2026-09-01 ORDER BY Name LIMIT 2];
  if (paid.size() == 2) {
    CreditService.CreditRequest c1 = new CreditService.CreditRequest();
    c1.sourceInvoiceId = paid[0].Id; c1.amount = Math.min(900, paid[0].Total__c); c1.origin = 'Withdrawal'; c1.reason = 'Missed two weeks in September due to dengue; parent requested a refund.';
    Id cn1 = CreditService.issueForInvoice(c1);
    CreditService.RefundRequest r1 = new CreditService.RefundRequest();
    r1.creditNoteId = cn1; r1.amount = c1.amount; r1.method = 'Bank Transfer'; r1.reason = 'Refund to the parent\'s bank account';
    Id rf1 = CreditService.requestRefund(r1);
    Refund__c rf = [SELECT Status__c FROM Refund__c WHERE Id = :rf1];
    if (rf.Status__c == 'Approved') CreditService.markRefundPaid(rf1, 'NEFT N2261048834', today.addDays(-2));
    CreditService.CreditRequest c2 = new CreditService.CreditRequest();
    c2.sourceInvoiceId = paid[1].Id; c2.amount = Math.min(2500, paid[1].Total__c); c2.origin = 'Goodwill'; c2.reason = 'Art batch cancelled for two Sundays (studio repairs).';
    Id cn2 = CreditService.issueForInvoice(c2);
    CreditService.RefundRequest r2 = new CreditService.RefundRequest();
    r2.creditNoteId = cn2; r2.amount = c2.amount; r2.method = 'UPI'; r2.reason = 'Parent prefers a refund over credit';
    CreditService.requestRefund(r2);
    System.debug('SEED11 credits+2 refunds+2 (first ' + rf.Status__c + ')');
  }
  return;
}

// ---- Teacher absence with cover (next Wednesday's Abacus class at HSR Layout) ----
User anjali = [SELECT Id FROM User WHERE Name = 'Anjali Advisor'];
if ([SELECT COUNT() FROM Staff_Absence__c WHERE Staff_User__c = :anjali.Id AND Start__c >= :System.now()] == 0) {
  Class_Session__c s = [SELECT Id, Start__c, End__c FROM Class_Session__c WHERE Course_Offering__r.SectionNumber = 'KT-HSR-ABA1-WED' AND Start__c > :System.now() ORDER BY Start__c LIMIT 1];
  CoverService.AbsenceRequest a = new CoverService.AbsenceRequest();
  a.teacherId = anjali.Id; a.startAt = Datetime.newInstance(s.Start__c.date(), Time.newInstance(8, 0, 0, 0)); a.endAt = Datetime.newInstance(s.Start__c.date(), Time.newInstance(20, 0, 0, 0));
  a.reason = 'Planned Leave'; a.notes = 'Attending a family wedding in Mysuru.';
  CoverService.recordAbsence(a);
  for (CoverService.Candidate c : CoverService.candidates(s.Id)) {
    if (c.free) { CoverService.assignCover(s.Id, c.userId, 'Covering the Abacus Level 1 class; lesson plan shared on WhatsApp.'); break; }
  }
  System.debug('SEED11 absence+1');
  return;
}

// ---- Retention risk scoring for every running enrolment ----
Set<Id> ids = new Map<Id, CourseOfferingParticipant>([SELECT Id FROM CourseOfferingParticipant WHERE CourseOffering.SectionNumber LIKE 'KT-%' AND ParticipationStatus = 'Enrolled' AND StartDate <= :today]).keySet();
System.debug('SEED11 retention assessed ' + RetentionService.assess(ids));

// ---- Instalment plans for two families paying a term fee in parts ----
if ([SELECT COUNT() FROM Instalment__c WHERE Student_Invoice__r.Enrolment__r.CourseOffering.SectionNumber LIKE 'KT-%'] == 0) {
  Integer n = 0;
  for (Student_Invoice__c i : [SELECT Id FROM Student_Invoice__c WHERE Enrolment__r.CourseOffering.SectionNumber LIKE 'KT-%'
      AND Status__c IN ('Issued','Partially Paid') AND Balance_Due__c >= 3000 ORDER BY Balance_Due__c DESC LIMIT 2]) {
    BillingService.PlanRequest plan = new BillingService.PlanRequest();
    plan.invoiceId = i.Id; plan.count = 3; plan.firstDueDate = today.addDays(5); plan.intervalMonths = 1;
    BillingService.createPlan(plan);
    n++;
  }
  System.debug('SEED11 instalment plans+' + n);
}
