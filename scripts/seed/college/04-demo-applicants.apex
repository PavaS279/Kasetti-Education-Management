// KT College seed, stage 4 (idempotent): demo applicants tagged [KEM College]
// with verified qualifications and entrance ranks, each with a college admission
// waiting at Processing for the hands-on demo. No users are created.
// first, last, campus code, branch key, route, [level:stream:branchCode:percent ...], [exam:rank ...], guardian
List<List<Object>> people = new List<List<Object>>{
  new List<Object>{ 'Ravi', 'Kumar', 'Y', 'BCS', 'Regular', new List<String>{ 'SSLC:::91', 'PUC:Science::92' }, new List<String>{ 'KCET:12400' }, null },
  new List<Object>{ 'Meghana', 'Rao', 'Y', 'BCS', 'Regular', new List<String>{ 'SSLC:::88', 'PUC:Science::86' }, new List<String>{ 'KCET:18200' }, null },
  new List<Object>{ 'Sneha', 'Gowda', 'Y', 'BCS', 'Regular', new List<String>{ 'SSLC:::90', 'PUC:Commerce::88' }, new List<String>(), null },
  new List<Object>{ 'Kiran', 'Patil', 'R', 'BCS', 'Lateral', new List<String>{ 'SSLC:::78', 'Diploma::CS:82' }, new List<String>{ 'DCET:3200' }, null },
  new List<Object>{ 'Arjun', 'Shetty', 'Y', 'PPC', 'Regular', new List<String>{ 'SSLC:::85' }, new List<String>(), 'Suresh' }
};
String tag = ' [KEM College]';
Map<String, Branch__c> campuses = new Map<String, Branch__c>();
for (Branch__c c : [SELECT Id, Campus_Code__c FROM Branch__c WHERE Institution_Type__c = 'College']) {
  campuses.put(c.Campus_Code__c, c);
}
Map<String, LearningCourse> branches = new Map<String, LearningCourse>();
for (LearningCourse b : [SELECT Id, External_ID__c, Programme__c FROM LearningCourse WHERE External_ID__c LIKE 'KTC-BR-%']) {
  branches.put(b.External_ID__c.removeStart('KTC-BR-'), b);
}
Set<String> existing = new Set<String>();
for (Account a : [SELECT LastName FROM Account WHERE IsPersonAccount = TRUE AND LastName LIKE '%[KEM College]']) {
  existing.add(a.LastName);
}
Integer created = 0;
for (List<Object> p : people) {
  String lastName = (String) p[1] + tag;
  if (existing.contains(lastName)) {
    continue;
  }
  Branch__c campus = campuses.get((String) p[2]);
  LearningCourse branch = branches.get((String) p[3]);
  Account student = PersonAccountService.buildPerson((String) p[0], lastName, null, '+91 98450 0000' + created, campus.Id, 'Learner');
  student.PersonBirthdate = ((String) p[3]).startsWith('P') ? Date.newInstance(2010, 6, 15) : Date.newInstance(2007, 3, 9);
  insert student;
  student = [SELECT Id, PersonContactId FROM Account WHERE Id = :student.Id];

  List<Academic_Qualification__c> qualifications = new List<Academic_Qualification__c>();
  for (String q : (List<String>) p[5]) {
    List<String> parts = q.split(':', -1);
    qualifications.add(new Academic_Qualification__c(
      Student__c = student.Id, Level__c = parts[0], Stream_Group__c = String.isBlank(parts[1]) ? null : parts[1],
      Branch_Code__c = String.isBlank(parts[2]) ? null : parts[2], Percentage__c = Decimal.valueOf(parts[3]),
      Completion_Year__c = parts[0] == 'SSLC' ? 2024 : 2026, Verified__c = true,
      Verified_By__c = UserInfo.getUserId(), Verified_On__c = System.now()
    ));
  }
  insert qualifications;
  List<Entrance_Score__c> scores = new List<Entrance_Score__c>();
  for (String e : (List<String>) p[6]) {
    scores.add(new Entrance_Score__c(
      Student__c = student.Id, Exam__c = e.substringBefore(':'), Exam_Year__c = 2026,
      Rank__c = Integer.valueOf(e.substringAfter(':')), Verified__c = true,
      Verified_By__c = UserInfo.getUserId(), Verified_On__c = System.now()
    ));
  }
  insert scores;

  if (p[7] != null) {
    Account parent = PersonAccountService.buildPerson((String) p[7], (String) p[1] + tag, null, '+91 98450 1111' + created, campus.Id, 'Guardian');
    insert parent;
    GuardianRelationshipService.GuardianLink link = new GuardianRelationshipService.GuardianLink();
    link.guardianContactId = [SELECT PersonContactId FROM Account WHERE Id = :parent.Id].PersonContactId;
    link.learnerContactId = student.PersonContactId;
    link.relationship = 'Father';
    link.portalAccess = false;
    GuardianRelationshipService.link(new List<GuardianRelationshipService.GuardianLink>{ link });
  }

  Campus_Branch__c intake = [
    SELECT Id FROM Campus_Branch__c
    WHERE Campus__c = :campus.Id AND Branch__c = :branch.Id AND Academic_Year__c = '2026-27'
  ];
  String route = (String) p[4];
  insert new IndividualApplication(
    Category = 'Education', AccountId = student.Id, ContactId = student.PersonContactId, Status = 'Processing',
    Branch__c = campus.Id, Learning_Course__c = branch.Id, Learning_Program__c = branch.Programme__c,
    Campus_Branch__c = intake.Id, College_Mode__c = true, College_Stage__c = 'Processing',
    Academic_Year__c = '2026-27', Entry_Route__c = route, Entry_Year_Of_Study__c = route == 'Lateral' ? 2 : 1
  );
  created++;
}
System.debug('KT College demo applicants created ' + created);
