// KTEdutech seed 9a/9: the admissions pipeline: new, contacted, nurturing and lost enquiries, referrals,
// and converted enquiries whose applications are at different stages. Idempotent on Submission_Id__c.
Map<String, Id> branches = new Map<String, Id>();
for (Branch__c b : [SELECT Id, Branch_Code__c FROM Branch__c WHERE Branch_Code__c IN ('IND-01','KOR-01','HSR-01')]) branches.put(b.Branch_Code__c, b.Id);
Map<String, Id> courses = new Map<String, Id>();
for (LearningCourse c : [SELECT Id, External_ID__c FROM LearningCourse WHERE External_ID__c LIKE 'KT-CRS-%']) courses.put(c.External_ID__c.substringAfter('KT-CRS-'), c.Id);
Set<String> have = new Set<String>();
for (Lead l : [SELECT Submission_Id__c FROM Lead WHERE Submission_Id__c LIKE 'KT-ENQ-%']) have.add(l.Submission_Id__c);
// Referral codes of three existing fee payers
List<String> codes = new List<String>();
for (Account a : [SELECT Id FROM Account WHERE External_Id__c IN ('KT-FAM-003-G1','KT-FAM-021-G1','KT-FAM-040-G1') ORDER BY External_Id__c]) codes.add(ReferralService.codeFor(a.Id));
// key, branch, learner first, last, birth year, guardian first, relationship, course, channel, stage, note, referral index
List<Object[]> rows = new List<Object[]>{
  new Object[]{'01','IND-01','Advait','Rangan',2015,'Pallavi','Mother','PYT','Website','New','Asked about weekend batches and laptop requirements.',null},
  new Object[]{'02','KOR-01','Ira','Nambiar',2018,'Deepika','Mother','ART','Social Media','New','Saw the art exhibition post on Instagram.',null},
  new Object[]{'03','HSR-01','Vedant','Upadhyay',2013,'Alok','Father','ROB','Referral','New','Friend of the Menon family; keen on robotics competitions.',0},
  new Object[]{'04','IND-01','Mahika','Chopra',2016,'Tanya','Mother','ABA','Walk-in','New','Walked in after school; wants a demo class.',null},
  new Object[]{'05','KOR-01','Arush','Lobo',2012,'Clara','Mother','OLY','Phone','New','Preparing for NSTSE; asked about mock tests.',null},
  new Object[]{'06','HSR-01','Zainab','Ansari',2017,'Rizwan','Father','SCR','Website','New','Interested in the new Sunday Scratch batch.',null},
  new Object[]{'07','IND-01','Kian','Rajan',2014,'Divya','Mother','ENG','Phone','Contacted','Called back; sharing the term schedule on WhatsApp.',null},
  new Object[]{'08','KOR-01','Nysa','Mahadevan',2015,'Srikanth','Father','VED','Event','Contacted','Met at the Vedic maths workshop at the community hall.',null},
  new Object[]{'09','HSR-01','Parth','Tiwari',2011,'Neelam','Mother','ROB','Referral','Contacted','Referred by an existing family; trial booked.',1},
  new Object[]{'10','IND-01','Anaya','Sood',2016,'Karan','Father','ABA','Campaign','Contacted','Responded to the open-house leaflet.',null},
  new Object[]{'11','KOR-01','Rudra','Karanth',2014,'Shilpa','Mother','PYT','Website','Contacted','Wants the Friday batch; checking transport.',null},
  new Object[]{'12','HSR-01','Simran','Kaur',2013,'Harpreet','Mother','OLY','Referral','Contacted','Sister of a current student at another centre.',2},
  new Object[]{'13','IND-01','Aarush','Wadhwa',2012,'Mansi','Mother','ROB','Social Media','Nurturing','Interested for the January term; follow up in December.',null},
  new Object[]{'14','KOR-01','Tara','Hosmane',2017,'Vinay','Father','ART','Walk-in','Nurturing','Will decide after school exams.',null},
  new Object[]{'15','HSR-01','Kabir','Puri',2014,'Ritika','Mother','PYT','Website','Nurturing','Comparing with an online course.',null},
  new Object[]{'16','IND-01','Myra','Rathore',2015,'Devendra','Father','ENG','Phone','Nurturing','Prefers a weekend batch for spoken English.',null},
  new Object[]{'17','KOR-01','Evan','Jacob',2013,'Linda','Mother','PYT','Website','Lost','Timings clash with football practice.','Schedule'},
  new Object[]{'18','HSR-01','Riddhi','Dutta',2014,'Sumit','Father','VED','Phone','Lost','Found the fee higher than expected.','Price'},
  new Object[]{'19','IND-01','Liam','Saldanha',2016,'Rachel','Mother','SCR','Website','Lost','Moving to Pune next month.','Location'},
  new Object[]{'20','KOR-01','Diya','Chettiar',2012,'Bala','Father','OLY','Event','Lost','Joined another academy near home.','Chose Competitor'},
  new Object[]{'21','HSR-01','Om','Bhandari',2015,'Kriti','Mother','ABA','Phone','Lost','Did not answer three calls.','Unreachable'},
  new Object[]{'22','IND-01','Shanaya','Ravindran',2014,'Lekha','Mother','ENG','Website','Applied','Converted after a trial class.',null},
  new Object[]{'23','KOR-01','Aditya','Pandit',2013,'Sameer','Father','VED','Walk-in','Review','Documents received; awaiting review.',null},
  new Object[]{'24','HSR-01','Elena','Pinto',2017,'Maria','Mother','SCR','Referral','Ready','Trial went well; ready for decision.',0},
  new Object[]{'25','IND-01','Ayaan','Ali',2012,'Shahid','Father','OLY','Website','Offered','Offer sent; family to confirm.',null},
  new Object[]{'26','KOR-01','Kavin','Ravichandran',2016,'Uma','Mother','ART','Walk-in','Offered','Offer sent for the Sunday art batch.',null}};
Integer created = 0;
for (Object[] r : rows) {
  String key = 'KT-ENQ-' + r[0];
  if (have.contains(key)) continue;
  Boolean converts = !new Set<String>{ 'New', 'Contacted', 'Nurturing', 'Lost' }.contains((String) r[9]);
  // A conversion with checklist, review and decision is heavy: at most one per run.
  if (Limits.getQueries() > 75 || Limits.getCpuTime() > 7000 || (converts && Limits.getQueries() > 12)) { System.debug('SEED9a paused'); break; }
  String last = (String) r[3];
  String gFirst = (String) r[5];
  Integer h = Math.abs(key.hashCode());
  Lead l = new Lead(FirstName = (String) r[2], LastName = last, Branch__c = branches.get((String) r[1]), Interested_Course__c = courses.get((String) r[7]),
    Enquiry_Channel__c = (String) r[8], Learner_Birthdate__c = Date.newInstance((Integer) r[4], 1 + Math.mod(h, 12), 1 + Math.mod(h, 27)),
    Guardian_First_Name__c = gFirst, Guardian_Last_Name__c = last, Guardian_Relationship__c = (String) r[6],
    Guardian_Email__c = (gFirst + '.' + last).toLowerCase() + '@example.com', Guardian_Phone__c = '+91 9' + String.valueOf(845000000 + Math.mod(h, 99999999)).left(4) + ' ' + String.valueOf(10000 + Math.mod(h, 89999)),
    Description = (String) r[10], Preferred_Delivery_Mode__c = 'Classroom', Submission_Id__c = key);
  if (r[11] instanceof Integer && codes.size() > (Integer) r[11]) l.Referral_Code__c = codes[(Integer) r[11]];
  insert l;
  String stage = (String) r[9];
  if (stage == 'Contacted' || stage == 'Nurturing') {
    EnquiryController.logFollowUp(l.Id, 'Spoke to parent', (String) r[10], Datetime.now().addDays(2 + Math.mod(h, 6)));
    if (stage == 'Nurturing') EnquiryController.updateStatus(l.Id, 'Nurturing', null);
    if (key.endsWith('09') || key.endsWith('07')) update new Lead(Id = l.Id, Trial_Session_Date__c = Date.today().addDays(4));
  } else if (stage == 'Lost') {
    EnquiryController.logFollowUp(l.Id, 'Not proceeding', (String) r[10], null);
    EnquiryController.updateStatus(l.Id, 'Unqualified', (String) r[11]);
  } else if (stage != 'New') {
    EnquiryConversionService.ConversionRequest q = new EnquiryConversionService.ConversionRequest();
    q.leadId = l.Id; q.createGuardian = true; q.createApplication = true;
    Id app = EnquiryConversionService.convert(q).applicationId;
    if (stage != 'Applied') {
      for (DocumentChecklistItem i : [SELECT Id, IsRequired FROM DocumentChecklistItem WHERE ParentRecordId = :app]) {
        if (stage == 'Review' && !i.IsRequired) continue;
        ApplicationService.updateChecklistItem(i.Id, i.IsRequired ? 'Accepted' : 'Waived', i.IsRequired ? 'Original verified at the front desk' : 'Not needed for this course');
      }
      ApplicationService.submitForReview(app);
      if (stage == 'Ready' || stage == 'Offered') ApplicationService.markReadyForDecision(app);
      if (stage == 'Offered') ApplicationService.decide(app, 'Admit', null, 14);
    }
  }
  created++;
}
System.debug('SEED9a enquiries+' + created + ' referralCodes=' + codes + ' soql=' + Limits.getQueries() + ' cpu=' + Limits.getCpuTime());
