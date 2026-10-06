// KTEdutech seed 7/9: invoice history. Replays billing as it would have run: the first invoice on the
// learner's start date (admission, materials, term fee or first month), then each month on its period date.
// Invoices are dated on the day they were raised (due 10 days later). Re-run until "remaining=0".
Integer raised = 0, remaining = 0;
Date today = Date.today();
List<CourseOfferingParticipant> enrolments = [SELECT Id, StartDate, CourseOffering.Branch__r.Invoice_Due_Days__c,
    (SELECT Id, Billing_Frequency__c, Next_Bill_Date__c, Invoiced__c FROM Fee_Lines__r)
  FROM CourseOfferingParticipant WHERE CourseOffering.SectionNumber LIKE 'KT-%' AND ParticipationStatus IN ('Enrolled','On Hold','Completed')
  AND StartDate <= :today ORDER BY StartDate, Id];
for (CourseOfferingParticipant e : enrolments) {
  Date next = null;
  Boolean firstInvoice = false;
  for (Enrolment_Fee_Line__c l : e.Fee_Lines__r) {
    if (l.Billing_Frequency__c != 'Monthly' && !l.Invoiced__c) { firstInvoice = true; }
    if (l.Billing_Frequency__c == 'Monthly' && !l.Invoiced__c) {
      Date d = l.Next_Bill_Date__c == null ? e.StartDate : l.Next_Bill_Date__c;
      if (l.Next_Bill_Date__c == null) firstInvoice = true;
      next = next == null || d < next ? d : next;
    }
  }
  if (firstInvoice) next = e.StartDate;
  while (next != null && next <= today) {
    if (Limits.getQueries() > 80 || Limits.getCpuTime() > 7000 || Limits.getQueueableJobs() > 40) { remaining++; break; }
    Id invoiceId = BillingService.billDuePeriods(e.Id, next);
    if (invoiceId == null) break;
    Integer dueDays = e.CourseOffering.Branch__r.Invoice_Due_Days__c == null ? 10 : e.CourseOffering.Branch__r.Invoice_Due_Days__c.intValue();
    update new Student_Invoice__c(Id = invoiceId, Issue_Date__c = next, Due_Date__c = next.addDays(dueDays));
    raised++;
    Date following = null;
    for (Enrolment_Fee_Line__c l : [SELECT Next_Bill_Date__c FROM Enrolment_Fee_Line__c WHERE Enrolment__c = :e.Id AND Billing_Frequency__c = 'Monthly' AND Invoiced__c = false]) {
      following = following == null || l.Next_Bill_Date__c < following ? l.Next_Bill_Date__c : following;
    }
    next = following;
  }
  if (remaining > 0) break;
}
System.debug('SEED7 invoices+' + raised + ' remaining=' + remaining + ' soql=' + Limits.getQueries() + ' cpu=' + Limits.getCpuTime());
