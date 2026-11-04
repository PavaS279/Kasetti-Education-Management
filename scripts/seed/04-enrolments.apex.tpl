// KTEdutech seed 4/9: enrolments from each learner's class plan (join dates honoured). Idempotent.
List<Object> families = (List<Object>) JSON.deserializeUntyped('__FAMILIES__');
Map<String, CourseOffering> classes = new Map<String, CourseOffering>();
for (CourseOffering o : [SELECT Id, SectionNumber, StartDate FROM CourseOffering WHERE SectionNumber LIKE 'KT-%']) classes.put(o.SectionNumber, o);
Map<String, Account> learners = new Map<String, Account>();
for (Account a : [SELECT Id, External_Id__c, PersonContactId FROM Account WHERE External_Id__c LIKE 'KT-FAM-%-L%']) learners.put(a.External_Id__c, a);
Set<String> enrolled = new Set<String>();
for (CourseOfferingParticipant p : [SELECT CourseOfferingId, ParticipantContactId FROM CourseOfferingParticipant WHERE CourseOffering.SectionNumber LIKE 'KT-%']) enrolled.add(p.CourseOfferingId + ':' + p.ParticipantContactId);
Integer n = 0, skipped = 0;
for (Object o : families) {
  Map<String, Object> f = (Map<String, Object>) o;
  Integer li = 0;
  for (Object lo : (List<Object>) f.get('learners')) {
    li++;
    Account learner = learners.get(f.get('key') + '-L' + li);
    for (Object co : (List<Object>) ((Map<String, Object>) lo).get('classes')) {
      Map<String, Object> c = (Map<String, Object>) co;
      CourseOffering cls = classes.get((String) c.get('section'));
      if (enrolled.contains(cls.Id + ':' + learner.PersonContactId)) { skipped++; continue; }
      if (Limits.getQueries() > 70 || Limits.getCpuTime() > 7000) { System.debug('SEED4 paused'); break; }
      Date joinDate = Date.valueOf((String) c.get('join'));
      Datetime classStart = cls.StartDate;
      Boolean late = joinDate > classStart.date();
      if (late) update new CourseOffering(Id = cls.Id, StartDate = Datetime.newInstance(joinDate, Time.newInstance(8, 0, 0, 0)));
      EnrolmentService.EnrolmentRequest r = new EnrolmentService.EnrolmentRequest();
      r.learnerAccountId = learner.Id;
      r.offeringId = cls.Id;
      if (li > 1) r.discountCode = 'SIBLING10';
      EnrolmentService.enrol(r);
      if (late) update new CourseOffering(Id = cls.Id, StartDate = classStart);
      n++;
    }
  }
}
System.debug('SEED4 enrolled+' + n + ' skipped=' + skipped + ' soql=' + Limits.getQueries() + ' cpu=' + Limits.getCpuTime());
