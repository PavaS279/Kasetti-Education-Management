// KT College seed, stage 3 (idempotent): Year 1 subjects for every branch,
// Section A for every 2026-27 campus branch with its section subjects, and a
// live weekly timetable for the demo section (Yelahanka BE CSE, Tara Teacher).

Map<String, String> subjectNames = new Map<String, String>{
  'PPB' => 'Physics I|Biology I', 'PPC' => 'Physics I|Computer Science I',
  'PCM' => 'Accountancy I|Business Studies I', 'PAR' => 'History I|Political Science I',
  'DCS' => 'Applied Mathematics I|Programming in C', 'DME' => 'Applied Mathematics I|Engineering Drawing',
  'DEE' => 'Applied Mathematics I|Basic Electrical Engineering',
  'BCS' => 'Engineering Mathematics I|Programming in Python', 'BEC' => 'Engineering Mathematics I|Basic Electronics',
  'BME' => 'Engineering Mathematics I|Elements of Mechanical Engineering', 'BCV' => 'Engineering Mathematics I|Engineering Mechanics'
};
Map<String, String> branchShort = new Map<String, String>{
  'PPB' => 'PUC-PCMB', 'PPC' => 'PUC-PCMC', 'PCM' => 'PUC-COM', 'PAR' => 'PUC-ARTS', 'DCS' => 'DIP-CS', 'DME' => 'DIP-ME',
  'DEE' => 'DIP-EE', 'BCS' => 'BE-CSE', 'BEC' => 'BE-ECE', 'BME' => 'BE-ME', 'BCV' => 'BE-CV'
};
Map<String, LearningCourse> branches = new Map<String, LearningCourse>();
for (LearningCourse b : [SELECT Id, External_ID__c, Programme__r.Programme_Code__c FROM LearningCourse WHERE External_ID__c LIKE 'KTC-BR-%']) {
  branches.put(b.External_ID__c.removeStart('KTC-BR-'), b);
}
User faculty = [SELECT Id FROM User WHERE Name = 'Tara Teacher' AND IsActive = TRUE LIMIT 1];

// Subjects (codes like BCS101), Year 1, Term 1.
Map<String, Subject__c> subjects = new Map<String, Subject__c>();
for (Subject__c s : [SELECT Id, Subject_Code__c, Branch__c FROM Subject__c WHERE Curriculum_Version__c = '2025']) {
  subjects.put(s.Branch__c + '|' + s.Subject_Code__c, s);
}
List<Subject__c> newSubjects = new List<Subject__c>();
for (String key : subjectNames.keySet()) {
  Id branchId = branches.get(key).Id;
  Boolean puc = key.startsWith('P');
  Integer n = 1;
  for (String name : subjectNames.get(key).split('\\|')) {
    String code = key + '10' + n++;
    if (subjects.containsKey(branchId + '|' + code)) {
      continue;
    }
    newSubjects.add(new Subject__c(
      Name = name, Branch__c = branchId, Curriculum_Version__c = '2025', Subject_Code__c = code,
      Year_Of_Study__c = 1, Term__c = 1, Credits__c = puc ? 0 : 4,
      Internal_Max__c = puc ? 30 : 50, Exam_Max__c = puc ? 70 : 100,
      Internal_Pass_Percent__c = 35, Exam_Pass_Percent__c = 35, Total_Pass_Percent__c = 40, Active__c = true
    ));
  }
}
insert newSubjects;
for (Subject__c s : newSubjects) {
  subjects.put(s.Branch__c + '|' + s.Subject_Code__c, s);
}

// Section A per campus branch.
Id sectionType = Schema.SObjectType.CourseOffering.getRecordTypeInfosByDeveloperName().get('College_Section').getRecordTypeId();
Map<Id, CourseOffering> sectionByIntake = new Map<Id, CourseOffering>();
for (CourseOffering s : [SELECT Id, Campus_Branch__c FROM CourseOffering WHERE RecordTypeId = :sectionType AND Academic_Year__c = '2026-27' AND Year_Of_Study__c = 1 AND Section_Code__c = 'A']) {
  sectionByIntake.put(s.Campus_Branch__c, s);
}
Map<Id, String> keyOfBranch = new Map<Id, String>();
for (String key : branches.keySet()) {
  keyOfBranch.put(branches.get(key).Id, key);
}
List<CourseOffering> newSections = new List<CourseOffering>();
for (Campus_Branch__c cb : [SELECT Id, Campus__c, Campus__r.Invoice_Prefix__c, Branch__c, Intake_Regular__c FROM Campus_Branch__c WHERE Academic_Year__c = '2026-27']) {
  if (sectionByIntake.containsKey(cb.Id)) {
    continue;
  }
  String key = keyOfBranch.get(cb.Branch__c);
  newSections.add(new CourseOffering(
    Name = cb.Campus__r.Invoice_Prefix__c + ' · ' + branchShort.get(key) + ' · 2026-27 · Y1 · A',
    RecordTypeId = sectionType, LearningCourseId = cb.Branch__c, Branch__c = cb.Campus__c, Campus_Branch__c = cb.Id,
    Academic_Year__c = '2026-27', Year_Of_Study__c = 1, Section_Code__c = 'A',
    EnrollmentCapacity = cb.Intake_Regular__c.intValue(), Class_Status__c = 'Open', Teacher_User__c = faculty.Id,
    StartDate = Datetime.newInstance(2026, 8, 1, 9, 0, 0), EndDate = Datetime.newInstance(2027, 5, 31, 17, 0, 0)
  ));
}
insert newSections;
for (CourseOffering s : newSections) {
  sectionByIntake.put(s.Campus_Branch__c, s);
}

// Section subjects: every Year 1 subject in every section (Planned); the demo section's subjects are Active.
CourseOffering demo = [
  SELECT Id, Branch__c FROM CourseOffering
  WHERE RecordTypeId = :sectionType AND Name LIKE 'YLK · BE-CSE · 2026-27 · Y1 · A' LIMIT 1
];
Map<String, Id> rooms = new Map<String, Id>();
for (Room__c r : [SELECT Id, External_Id__c FROM Room__c WHERE External_Id__c LIKE 'KTC-Y-%']) {
  rooms.put(r.External_Id__c, r.Id);
}
Set<String> linked = new Set<String>();
for (Section_Subject__c ss : [SELECT Section__c, Subject__c FROM Section_Subject__c]) {
  linked.add(ss.Section__c + '|' + ss.Subject__c);
}
List<Section_Subject__c> newLinks = new List<Section_Subject__c>();
for (Campus_Branch__c cb : [SELECT Id, Branch__c FROM Campus_Branch__c WHERE Academic_Year__c = '2026-27']) {
  CourseOffering section = sectionByIntake.get(cb.Id);
  for (Subject__c s : subjects.values()) {
    if (s.Branch__c != cb.Branch__c || linked.contains(section.Id + '|' + s.Id)) {
      continue;
    }
    Boolean live = section.Id == demo.Id;
    Section_Subject__c link = new Section_Subject__c(Section__c = section.Id, Subject__c = s.Id, Faculty__c = faculty.Id);
    if (live) {
      link.Status__c = 'Active';
      link.Default_Room__c = s.Subject_Code__c.endsWith('2') ? rooms.get('KTC-Y-L-201') : rooms.get('KTC-Y-A-101');
      link.Start_Date__c = Date.newInstance(2026, 8, 1);
      link.End_Date__c = Date.newInstance(2027, 1, 31);
    }
    newLinks.add(link);
  }
}
insert newLinks;

// Demo timetable: Mathematics Mon/Wed/Fri 09:00–10:00, Python lab Tue/Thu 10:00–12:00, from two weeks ago.
Integer patterns = [SELECT COUNT() FROM CourseOfferingSchedule WHERE CourseOfferingId = :demo.Id];
SessionService.GenerationResult generated;
if (patterns == 0) {
  List<CourseOfferingSchedule> week = new List<CourseOfferingSchedule>();
  for (Section_Subject__c ss : [SELECT Id, Subject__r.Subject_Code__c FROM Section_Subject__c WHERE Section__c = :demo.Id]) {
    Boolean lab = ss.Subject__r.Subject_Code__c.endsWith('2');
    week.add(new CourseOfferingSchedule(
      CourseOfferingId = demo.Id, Section_Subject__c = ss.Id, Type = lab ? 'Lab' : 'Class',
      Description = lab ? 'Python lab Tue/Thu 10:00' : 'Mathematics Mon/Wed/Fri 09:00',
      StartTime = lab ? Time.newInstance(10, 0, 0, 0) : Time.newInstance(9, 0, 0, 0),
      EndTime = lab ? Time.newInstance(12, 0, 0, 0) : Time.newInstance(10, 0, 0, 0),
      IsMonday = !lab, IsWednesday = !lab, IsFriday = !lab, IsTuesday = lab, IsThursday = lab,
      StartDate = Date.today().addDays(-14), EndDate = Date.newInstance(2027, 1, 31)
    ));
  }
  insert week;
  generated = SessionService.generate(demo.Id);
}
System.debug('KT College subjects new ' + newSubjects.size() + ', sections new ' + newSections.size() + ', section subjects new ' + newLinks.size() + ', sessions ' + (generated == null ? 'already generated' : String.valueOf(generated.created)));
