// KT College seed, stage 1 (idempotent): two campuses with rooms, three
// programmes, eleven branches and the 22 campus branches (2026-27 intake).
// Records are matched on their natural keys, so re-running adds only what is missing.

Map<String, Branch__c> campuses = new Map<String, Branch__c>();
for (Branch__c c : [SELECT Id, Campus_Code__c FROM Branch__c WHERE Campus_Code__c IN ('Y', 'R') AND Institution_Type__c = 'College']) {
  campuses.put(c.Campus_Code__c, c);
}
List<Branch__c> newCampuses = new List<Branch__c>();
for (List<String> c : new List<List<String>>{
  new List<String>{ 'Y', 'Yelahanka Campus', 'KTC-YLK', 'YLK', 'Yelahanka New Town', '560064' },
  new List<String>{ 'R', 'Rajajinagar Campus', 'KTC-RJN', 'RJN', 'Rajajinagar 2nd Block', '560010' }
}) {
  if (!campuses.containsKey(c[0])) {
    newCampuses.add(new Branch__c(
      Name = c[1], Branch_Code__c = c[2], Invoice_Prefix__c = c[3], Campus_Code__c = c[0],
      Institution_Type__c = 'College', Active__c = true, Street__c = c[4], City__c = 'Bengaluru',
      State__c = 'Karnataka', Postal_Code__c = c[5], Country__c = 'India', Tax_Rate__c = 0,
      Invoice_Due_Days__c = 7, Attendance_Threshold__c = 75,
      Allowed_Payment_Methods__c = 'Demand Draft;Cheque;Online Gateway;UPI;Bank Transfer',
      Discounts_Allowed__c = false
    ));
  }
}
insert newCampuses;
for (Branch__c c : newCampuses) {
  campuses.put(c.Campus_Code__c, c);
}

// Rooms: three classrooms and a lab per campus.
Set<String> roomKeys = new Set<String>();
for (Room__c r : [SELECT External_Id__c FROM Room__c WHERE External_Id__c LIKE 'KTC-%']) {
  roomKeys.add(r.External_Id__c);
}
List<Room__c> rooms = new List<Room__c>();
for (String code : campuses.keySet()) {
  for (List<String> r : new List<List<String>>{
    new List<String>{ 'A-101', 'Classroom' }, new List<String>{ 'A-102', 'Classroom' },
    new List<String>{ 'A-103', 'Classroom' }, new List<String>{ 'L-201', 'Lab' }
  }) {
    String key = 'KTC-' + code + '-' + r[0];
    if (!roomKeys.contains(key)) {
      rooms.add(new Room__c(Name = r[0], Branch__c = campuses.get(code).Id, Capacity__c = 60, Active__c = true, External_Id__c = key));
    }
  }
}
insert rooms;

// Programmes (LearningProgram needs a parent Learning record).
Map<String, LearningProgram> programmes = new Map<String, LearningProgram>();
for (LearningProgram p : [SELECT Id, Programme_Code__c FROM LearningProgram WHERE Programme_Code__c IN ('P', 'D', 'B')]) {
  programmes.put(p.Programme_Code__c, p);
}
List<List<Object>> programmeSpecs = new List<List<Object>>{
  new List<Object>{ 'P', 'Pre-University Course (PUC)', 2, 1, 'Year', 'PUC', 0 },
  new List<Object>{ 'D', 'Diploma in Engineering', 3, 2, 'Semester', 'Diploma', 2 },
  new List<Object>{ 'B', 'Bachelor of Engineering (BE)', 4, 2, 'Semester', 'BE', 4 }
};
for (List<Object> p : programmeSpecs) {
  String code = (String) p[0];
  if (programmes.containsKey(code)) {
    continue;
  }
  Learning learning = new Learning(Name = (String) p[1], Type = 'LearningProgram', IsActive = true);
  insert learning;
  LearningProgram programme = new LearningProgram(
    Name = (String) p[1], LearningId = learning.Id, Programme_Code__c = code,
    Duration_Years__c = (Integer) p[2], Terms_Per_Year__c = (Integer) p[3], Term_Label__c = (String) p[4],
    Qualification_Level__c = (String) p[5], Max_Backlogs_For_Promotion__c = (Integer) p[6],
    Roll_Release_Rule__c = 'Full Annual Invoice', Payment_Window_Days__c = 7, Active__c = true
  );
  insert programme;
  programmes.put(code, programme);
}

// Branches: code, name, programme, stream group.
List<List<String>> branchSpecs = new List<List<String>>{
  new List<String>{ 'PB', 'PUC Science (PCMB)', 'P', 'Science' },
  new List<String>{ 'PC', 'PUC Science (PCMC)', 'P', 'Science' },
  new List<String>{ 'CM', 'PUC Commerce', 'P', 'Commerce' },
  new List<String>{ 'AR', 'PUC Arts', 'P', 'Arts' },
  new List<String>{ 'CS', 'Diploma Computer Science', 'D', null },
  new List<String>{ 'ME', 'Diploma Mechanical', 'D', null },
  new List<String>{ 'EE', 'Diploma Electrical and Electronics', 'D', null },
  new List<String>{ 'CS', 'BE Computer Science and Engineering', 'B', null },
  new List<String>{ 'EC', 'BE Electronics and Communication', 'B', null },
  new List<String>{ 'ME', 'BE Mechanical Engineering', 'B', null },
  new List<String>{ 'CV', 'BE Civil Engineering', 'B', null }
};
Id branchType = Schema.SObjectType.LearningCourse.getRecordTypeInfosByDeveloperName().get('College_Branch').getRecordTypeId();
Map<String, LearningCourse> branches = new Map<String, LearningCourse>();
for (LearningCourse b : [SELECT Id, External_ID__c FROM LearningCourse WHERE External_ID__c LIKE 'KTC-BR-%']) {
  branches.put(b.External_ID__c, b);
}
for (List<String> b : branchSpecs) {
  String key = 'KTC-BR-' + b[2] + b[0];
  if (branches.containsKey(key)) {
    continue;
  }
  Learning learning = new Learning(Name = b[1], Type = 'LearningCourse', IsActive = true);
  insert learning;
  LearningCourse branch = new LearningCourse(
    Name = b[1], LearningId = learning.Id, RecordTypeId = branchType, External_ID__c = key,
    Programme__c = programmes.get(b[2]).Id, Branch_Code__c = b[0], Stream_Group__c = b[3],
    Curriculum_Version__c = '2025'
  );
  insert branch;
  branches.put(key, branch);
}

// Campus branches for 2026-27: BE CSE/ECE take lateral entrants too.
Set<String> existingIntakes = new Set<String>();
for (Campus_Branch__c cb : [SELECT Campus__c, Branch__c FROM Campus_Branch__c WHERE Academic_Year__c = '2026-27']) {
  existingIntakes.add(cb.Campus__c + '|' + cb.Branch__c);
}
List<Campus_Branch__c> intakes = new List<Campus_Branch__c>();
for (String code : campuses.keySet()) {
  for (List<String> b : branchSpecs) {
    LearningCourse branch = branches.get('KTC-BR-' + b[2] + b[0]);
    if (existingIntakes.contains(campuses.get(code).Id + '|' + branch.Id)) {
      continue;
    }
    Boolean be = b[2] == 'B';
    intakes.add(new Campus_Branch__c(
      Campus__c = campuses.get(code).Id, Branch__c = branch.Id, Academic_Year__c = '2026-27',
      Intake_Regular__c = be ? 60 : 40, Intake_Lateral__c = be ? 6 : 0, Admissions_Open__c = true
    ));
  }
}
insert intakes;
System.debug('KT College catalogue: campuses ' + campuses.size() + ', new rooms ' + rooms.size() + ', programmes ' + programmes.size() + ', branches ' + branches.size() + ', new campus branches ' + intakes.size());
