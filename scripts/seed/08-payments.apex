// KTEdutech seed 8/9: payments against the invoice history, by family habit. Re-run until "remaining=0".
// Most families pay within a week by UPI or card; some pay late; a few have not paid September or October
// (overdue, for reminders and the retention desk); larger term invoices of two families run on instalments.
Date today = Date.today();
String[] methods = new String[]{ 'UPI','UPI','UPI','UPI','UPI','Card','Card','Bank Transfer','Bank Transfer','Cash','Cheque' };
Integer paid = 0, remaining = 0, plans = 0;
List<Student_Invoice__c> open = [SELECT Id, Name, Issue_Date__c, Due_Date__c, Total__c, Balance_Due__c, Amount_Paid__c, Bill_To__c, Instalment_Count__c,
    (SELECT Id FROM Payments__r)
  FROM Student_Invoice__c WHERE Enrolment__r.CourseOffering.SectionNumber LIKE 'KT-%' AND Status__c IN ('Issued','Partially Paid','Overdue')
  ORDER BY Issue_Date__c, Name];
for (Student_Invoice__c i : open) {
  if (!i.Payments__r.isEmpty()) continue; // already handled (paid, part-paid or on a plan)
  if (Limits.getQueries() > 80 || Limits.getCpuTime() > 7000 || Limits.getQueueableJobs() > 40) { remaining++; continue; }
  Integer habit = Math.mod(Math.abs(String.valueOf(i.Bill_To__c).hashCode()), 100); // stable per payer
  Integer h = Math.abs(String.valueOf(i.Id).hashCode());
  Date payOn;
  Decimal amount = i.Balance_Due__c;
  if (habit < 6 && i.Issue_Date__c >= Date.newInstance(2026, 9, 1)) continue;          // has not paid Sep/Oct
  if (habit >= 6 && habit < 10 && i.Total__c >= 8000 && i.Instalment_Count__c == null) { // term fee on instalments
    BillingService.PlanRequest plan = new BillingService.PlanRequest();
    plan.invoiceId = i.Id; plan.count = 3; plan.firstDueDate = i.Due_Date__c; plan.intervalMonths = 1;
    BillingService.createPlan(plan);
    plans++;
    amount = (i.Total__c / 3).setScale(0, RoundingMode.UP);
    payOn = i.Due_Date__c.addDays(-2);
  } else if (habit < 22) { payOn = i.Issue_Date__c.addDays(12 + Math.mod(h, 14)); } // late payer
  else { payOn = i.Issue_Date__c.addDays(1 + Math.mod(h, 7)); }                       // pays on time
  if (payOn > today) continue;
  if (habit >= 22 && habit < 27 && i.Total__c > 5000) amount = (i.Balance_Due__c / 2).setScale(0, RoundingMode.DOWN); // part payment
  String method = methods[Math.mod(h, methods.size())];
  BillingService.PaymentRequest p = new BillingService.PaymentRequest();
  p.invoiceId = i.Id; p.amount = amount; p.method = method; p.paymentDate = payOn; p.confirmed = true;
  p.reference = method == 'UPI' ? 'UPI/' + String.valueOf(626000000000L + Math.mod(h, 999999999)) :
    method == 'Card' ? 'POS ' + String.valueOf(100000 + Math.mod(h, 899999)) + ' (card ending ' + String.valueOf(1000 + Math.mod(h, 8999)) + ')' :
    method == 'Bank Transfer' ? 'NEFT N' + String.valueOf(2260000000L + Math.mod(h, 99999999)) :
    method == 'Cheque' ? 'Cheque ' + String.valueOf(100000 + Math.mod(h, 899999)) + ', HDFC Bank' : 'Cash at front desk';
  BillingService.recordPayment(p);
  paid++;
}
System.debug('SEED8 payments+' + paid + ' plans+' + plans + ' remaining=' + remaining + ' soql=' + Limits.getQueries() + ' cpu=' + Limits.getCpuTime());
