// KT College seed, stage 2 (idempotent): 2026-27 admission rules for both
// campuses (activated), accepted entrance exams, yearly fees and the admission
// document rules. Values are demo values from COLLEGE-DESIGN.md §4.5–4.7;
// the administrator replaces them through new rule versions and fee prices.

Map<String, LearningCourse> branches = new Map<String, LearningCourse>();
for (LearningCourse b : [SELECT Id, External_ID__c FROM LearningCourse WHERE External_ID__c LIKE 'KTC-BR-%']) {
  branches.put(b.External_ID__c.removeStart('KTC-BR-'), b);
}
Map<String, Id> programmes = new Map<String, Id>();
for (LearningProgram p : [SELECT Id, Programme_Code__c FROM LearningProgram WHERE Programme_Code__c IN ('P', 'D', 'B')]) {
  programmes.put(p.Programme_Code__c, p.Id);
}

// branch key, route, qualifying level, streams, diploma branch codes, minimum %, entrances "EXAM:maxRank" (0 = any)
List<List<Object>> ruleSpecs = new List<List<Object>>{
  new List<Object>{ 'PPB', 'Regular', 'SSLC', null, null, 75, new List<String>() },
  new List<Object>{ 'PPC', 'Regular', 'SSLC', null, null, 75, new List<String>() },
  new List<Object>{ 'PCM', 'Regular', 'SSLC', null, null, 50, new List<String>() },
  new List<Object>{ 'PAR', 'Regular', 'SSLC', null, null, 40, new List<String>() },
  new List<Object>{ 'DCS', 'Regular', 'SSLC', null, null, 60, new List<String>() },
  new List<Object>{ 'DME', 'Regular', 'SSLC', null, null, 50, new List<String>() },
  new List<Object>{ 'DEE', 'Regular', 'SSLC', null, null, 50, new List<String>() },
  new List<Object>{ 'BCS', 'Regular', 'PUC', 'Science', null, 90, new List<String>{ 'KCET:20000', 'COMEDK:15000' } },
  new List<Object>{ 'BEC', 'Regular', 'PUC', 'Science', null, 80, new List<String>{ 'KCET:40000', 'COMEDK:30000' } },
  new List<Object>{ 'BME', 'Regular', 'PUC', 'Science', null, 65, new List<String>{ 'KCET:0', 'COMEDK:0' } },
  new List<Object>{ 'BCV', 'Regular', 'PUC', 'Science', null, 60, new List<String>{ 'KCET:0', 'COMEDK:0' } },
  new List<Object>{ 'BCS', 'Lateral', 'Diploma', null, 'CS', 75, new List<String>{ 'DCET:5000' } },
  new List<Object>{ 'BEC', 'Lateral', 'Diploma', null, 'CS;EE', 65, new List<String>{ 'DCET:0' } },
  new List<Object>{ 'BME', 'Lateral', 'Diploma', null, 'ME', 55, new List<String>{ 'DCET:0' } },
  new List<Object>{ 'BCV', 'Lateral', 'Diploma', null, 'ME', 55, new List<String>{ 'DCET:0' } }
};
Set<String> existingRules = new Set<String>();
for (Admission_Rule__c r : [SELECT Branch__c, Entry_Route__c FROM Admission_Rule__c WHERE Academic_Year__c = '2026-27' AND Campus__c = NULL]) {
  existingRules.add(r.Branch__c + '|' + r.Entry_Route__c);
}
Integer activated = 0;
for (List<Object> spec : ruleSpecs) {
  Id branchId = branches.get((String) spec[0]).Id;
  String route = (String) spec[1];
  if (existingRules.contains(branchId + '|' + route)) {
    continue;
  }
  List<String> entrances = (List<String>) spec[6];
  Admission_Rule__c rule = new Admission_Rule__c(
    Branch__c = branchId, Academic_Year__c = '2026-27', Entry_Route__c = route, Status__c = 'Draft',
    Entry_Year_Of_Study__c = route == 'Lateral' ? 2 : 1, Qualifying_Level__c = (String) spec[2],
    Qualifying_Streams__c = (String) spec[3], Qualifying_Branch_Codes__c = (String) spec[4],
    Min_Percentage__c = (Integer) spec[5], Entrance_Required__c = !entrances.isEmpty(), Interview_Required__c = true
  );
  insert rule;
  List<Admission_Rule_Entrance__c> rows = new List<Admission_Rule_Entrance__c>();
  for (String entrance : entrances) {
    Integer maxRank = Integer.valueOf(entrance.substringAfter(':'));
    rows.add(new Admission_Rule_Entrance__c(
      Admission_Rule__c = rule.Id, Entrance_Exam__c = entrance.substringBefore(':'),
      Max_Rank__c = maxRank == 0 ? null : maxRank, Exam_Year_From__c = 2025, Exam_Year_To__c = 2026
    ));
  }
  insert rows;
  AdmissionRuleService.activate(rule.Id);
  activated++;
}

// Yearly tuition per branch (every year of study) plus a one-time admission fee.
Map<String, Decimal> tuition = new Map<String, Decimal>{
  'PPB' => 60000, 'PPC' => 60000, 'PCM' => 45000, 'PAR' => 45000,
  'DCS' => 75000, 'DME' => 75000, 'DEE' => 75000,
  'BCS' => 150000, 'BEC' => 130000, 'BME' => 110000, 'BCV' => 110000
};
Set<String> priced = new Set<String>();
for (Fee_Price__c f : [SELECT Learning_Course__c, Fee_Type__c FROM Fee_Price__c WHERE Academic_Year__c = '2026-27']) {
  priced.add(f.Learning_Course__c + '|' + f.Fee_Type__c);
}
List<Fee_Price__c> fees = new List<Fee_Price__c>();
for (String key : tuition.keySet()) {
  Id branchId = branches.get(key).Id;
  if (!priced.contains(branchId + '|Tuition')) {
    fees.add(new Fee_Price__c(
      Learning_Course__c = branchId, Fee_Type__c = 'Tuition', Billing_Frequency__c = 'Annual',
      Amount__c = tuition.get(key), Academic_Year__c = '2026-27', Effective_From__c = Date.newInstance(2026, 4, 1),
      Description__c = 'Annual tuition 2026-27', Active__c = true
    ));
  }
  if (!priced.contains(branchId + '|Admission')) {
    fees.add(new Fee_Price__c(
      Learning_Course__c = branchId, Fee_Type__c = 'Admission', Billing_Frequency__c = 'One-time',
      Amount__c = 5000, Academic_Year__c = '2026-27', Year_Of_Study__c = null,
      Effective_From__c = Date.newInstance(2026, 4, 1), Description__c = 'Admission fee', Active__c = true
    ));
  }
}
insert fees;

// Admission documents (COLLEGE-DESIGN.md §4.6). Level = a qualification the student holds.
// type, label, programme, route, level, required, class, AI, keep file, retention days, order
List<List<Object>> documentSpecs = new List<List<Object>>{
  new List<Object>{ 'Aadhaar', 'Aadhaar card', null, null, null, true, 'Identity', false, false, 0, 10 },
  new List<Object>{ 'SSLC_Marks', 'SSLC / 10th marks card', null, null, null, true, 'Academic', true, true, 1825, 20 },
  new List<Object>{ 'Fitness', 'Fitness (medical) certificate', null, null, null, true, 'Health', false, true, 1460, 30 },
  new List<Object>{ 'Study_Certificate', 'Study certificate (1st–10th standard)', null, null, null, false, 'Academic', false, true, 1460, 40 },
  new List<Object>{ 'PAN', 'PAN card', null, null, null, false, 'Identity', false, false, 0, 50 },
  new List<Object>{ 'PUC_Marks', 'PUC marks card', null, null, 'PUC', true, 'Academic', true, true, 1825, 60 },
  new List<Object>{ 'Diploma_Marks', 'Diploma marks cards / certificate', 'B', 'Lateral', null, true, 'Academic', true, true, 1825, 70 },
  new List<Object>{ 'Entrance_Rank', 'Entrance rank card (KCET / COMEDK / DCET)', 'B', null, null, true, 'Academic', true, true, 1825, 80 }
};
Set<String> documentKeys = new Set<String>();
for (Admission_Document_Rule__c d : [SELECT Document_Type__c FROM Admission_Document_Rule__c WHERE Academic_Year__c = '2026-27']) {
  documentKeys.add(d.Document_Type__c);
}
List<Admission_Document_Rule__c> documents = new List<Admission_Document_Rule__c>();
for (List<Object> d : documentSpecs) {
  if (documentKeys.contains((String) d[0])) {
    continue;
  }
  Boolean keep = (Boolean) d[8];
  documents.add(new Admission_Document_Rule__c(
    Document_Type__c = (String) d[0], Label__c = (String) d[1],
    Programme__c = d[2] == null ? null : programmes.get((String) d[2]),
    Entry_Route__c = (String) d[3], Qualifying_Level__c = (String) d[4], Academic_Year__c = '2026-27',
    Required__c = (Boolean) d[5], Sensitive_Class__c = (String) d[6], AI_Extractable__c = (Boolean) d[7],
    Retain_File__c = keep, Retention_Days__c = keep ? (Integer) d[9] : null, Sort_Order__c = (Integer) d[10],
    Instruction__c = keep ? 'Upload a clear scan or photo of the original.' : 'Shown for verification; the file is deleted once verified.',
    Active__c = true
  ));
}
insert documents;
System.debug('KT College rules activated ' + activated + ', fee prices ' + fees.size() + ', document rules ' + documents.size());
