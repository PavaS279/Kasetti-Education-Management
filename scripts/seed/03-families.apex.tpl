// KTEdutech seed 3/9: households (guardians, learners, guardian links). Idempotent on External_Id__c.
// __FAMILIES__ is replaced by a JSON batch from families.json (see seed.sh).
List<Object> families = (List<Object>) JSON.deserializeUntyped('__FAMILIES__');
Map<String, Id> branches = new Map<String, Id>();
for (Branch__c b : [SELECT Id, Branch_Code__c FROM Branch__c WHERE Branch_Code__c IN ('IND-01','KOR-01','HSR-01')]) branches.put(b.Branch_Code__c, b.Id);
Set<String> keys = new Set<String>();
for (Object o : families) keys.add((String) ((Map<String, Object>) o).get('key'));
Set<String> done = new Set<String>();
for (Account a : [SELECT External_Id__c FROM Account WHERE External_Id__c LIKE 'KT-FAM-%']) done.add(a.External_Id__c.left(10));
List<Account> people = new List<Account>();
for (Object o : families) {
  Map<String, Object> f = (Map<String, Object>) o;
  String key = (String) f.get('key');
  if (done.contains(key)) continue;
  Id branchId = branches.get((String) f.get('branch'));
  Integer g = 0;
  for (Object go : (List<Object>) f.get('guardians')) {
    Map<String, Object> gm = (Map<String, Object>) go;
    Account a = PersonAccountService.buildPerson((String) gm.get('first'), (String) gm.get('last'), (String) gm.get('email'), (String) gm.get('phone'), branchId, 'Guardian');
    a.External_Id__c = key + '-G' + (++g);
    a.PersonMailingStreet = (String) f.get('street'); a.PersonMailingCity = 'Bengaluru'; a.PersonMailingState = 'Karnataka';
    a.PersonMailingPostalCode = (String) f.get('pin'); a.PersonMailingCountry = 'India';
    a.Preferred_Language__pc = (String) gm.get('lang'); a.Preferred_Channel__pc = (String) gm.get('channel');
    people.add(a);
  }
  Integer k = 0;
  for (Object lo : (List<Object>) f.get('learners')) {
    Map<String, Object> lm = (Map<String, Object>) lo;
    Account a = PersonAccountService.buildPerson((String) lm.get('first'), (String) lm.get('last'), null, null, branchId, 'Learner');
    a.External_Id__c = key + '-L' + (++k);
    a.PersonBirthdate = Date.valueOf((String) lm.get('dob'));
    a.Description = (String) lm.get('school');
    a.PersonMailingStreet = (String) f.get('street'); a.PersonMailingCity = 'Bengaluru'; a.PersonMailingState = 'Karnataka';
    a.PersonMailingPostalCode = (String) f.get('pin'); a.PersonMailingCountry = 'India';
    people.add(a);
  }
}
insert people;
Map<String, Account> byKey = new Map<String, Account>();
for (Account a : [SELECT Id, External_Id__c, PersonContactId FROM Account WHERE Id IN :people]) byKey.put(a.External_Id__c, a);
List<GuardianRelationshipService.GuardianLink> links = new List<GuardianRelationshipService.GuardianLink>();
for (Object o : families) {
  Map<String, Object> f = (Map<String, Object>) o;
  String key = (String) f.get('key');
  if (done.contains(key)) continue;
  List<Object> gs = (List<Object>) f.get('guardians');
  Integer nl = ((List<Object>) f.get('learners')).size();
  for (Integer gi = 1; gi <= gs.size(); gi++) {
    Map<String, Object> gm = (Map<String, Object>) gs[gi - 1];
    for (Integer li = 1; li <= nl; li++) {
      GuardianRelationshipService.GuardianLink l = new GuardianRelationshipService.GuardianLink();
      l.guardianContactId = byKey.get(key + '-G' + gi).PersonContactId;
      l.learnerContactId = byKey.get(key + '-L' + li).PersonContactId;
      l.relationship = (String) gm.get('rel');
      l.isFeePayer = (Boolean) gm.get('payer');
      l.isEmergencyContact = true;
      l.portalAccess = true;
      links.add(l);
    }
  }
}
GuardianRelationshipService.link(links);
System.debug('SEED3 people+' + people.size() + ' links+' + links.size() + ' soql=' + Limits.getQueries() + ' cpu=' + Limits.getCpuTime());
