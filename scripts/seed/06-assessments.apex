// KTEdutech seed 6/9: published tests and assignments with marks for each running class. Idempotent on External_Id__c.
// Each learner has a stable ability; irregular attenders score lower. Re-run until "remaining=0".
Map<String, List<Object[]>> plan = new Map<String, List<Object[]>>{
  'ABA' => new List<Object[]>{ new Object[]{'Speed test – July', 'Test', 50, 20, Date.newInstance(2026,7,25)}, new Object[]{'Mental arithmetic drill', 'Quiz', 25, 10, Date.newInstance(2026,8,22)}, new Object[]{'Level assessment – September', 'Exam', 100, 40, Date.newInstance(2026,9,26)} },
  'VED' => new List<Object[]>{ new Object[]{'Multiplication sutras test', 'Test', 40, 25, Date.newInstance(2026,7,25)}, new Object[]{'Squares and square roots quiz', 'Quiz', 20, 15, Date.newInstance(2026,8,29)}, new Object[]{'Mid-term assessment', 'Exam', 80, 40, Date.newInstance(2026,9,26)} },
  'OLY' => new List<Object[]>{ new Object[]{'Number theory worksheet', 'Assignment', 30, 15, Date.newInstance(2026,7,26)}, new Object[]{'Geometry test', 'Test', 50, 25, Date.newInstance(2026,8,23)}, new Object[]{'Mock Olympiad 1', 'Exam', 100, 40, Date.newInstance(2026,9,27)} },
  'PYT' => new List<Object[]>{ new Object[]{'Loops and conditions quiz', 'Quiz', 20, 15, Date.newInstance(2026,7,25)}, new Object[]{'Mini project: number guessing game', 'Project', 50, 35, Date.newInstance(2026,8,29)}, new Object[]{'Functions test', 'Test', 40, 25, Date.newInstance(2026,9,26)} },
  'SCR' => new List<Object[]>{ new Object[]{'Animation project', 'Project', 30, 40, Date.newInstance(2026,8,1)}, new Object[]{'Events and loops quiz', 'Quiz', 20, 20, Date.newInstance(2026,9,5)}, new Object[]{'Game design project', 'Project', 50, 40, Date.newInstance(2026,9,26)} },
  'ROB' => new List<Object[]>{ new Object[]{'Circuits basics quiz', 'Quiz', 20, 20, Date.newInstance(2026,7,29)}, new Object[]{'Line follower build', 'Project', 50, 40, Date.newInstance(2026,9,2)}, new Object[]{'Sensors test', 'Test', 40, 40, Date.newInstance(2026,9,30)} },
  'ENG' => new List<Object[]>{ new Object[]{'Self-introduction speech', 'Assignment', 20, 20, Date.newInstance(2026,7,23)}, new Object[]{'Storytelling', 'Assignment', 30, 30, Date.newInstance(2026,8,27)}, new Object[]{'Debate round', 'Test', 50, 50, Date.newInstance(2026,9,24)} },
  'ART' => new List<Object[]>{ new Object[]{'Still life sketch', 'Assignment', 20, 30, Date.newInstance(2026,7,26)}, new Object[]{'Watercolour landscape', 'Project', 30, 35, Date.newInstance(2026,8,30)}, new Object[]{'Colour theory quiz', 'Quiz', 20, 35, Date.newInstance(2026,9,27)} }};
List<String> praise = new List<String>{ 'Excellent work, very accurate.', 'Good effort; keep practising.', 'Strong understanding of the concepts.', 'Careless errors in a few questions.', 'Needs more practice at home.', 'Creative approach.' };
Set<String> have = new Set<String>();
for (Course_Assessment__c a : [SELECT External_Id__c FROM Course_Assessment__c WHERE External_Id__c LIKE 'KT-AS-%']) have.add(a.External_Id__c);
Integer published = 0, remaining = 0;
for (CourseOffering o : [SELECT Id, SectionNumber, StartDate FROM CourseOffering WHERE SectionNumber LIKE 'KT-%' ORDER BY SectionNumber]) {
  String course = o.SectionNumber.split('-')[2].left(3);
  Integer i = 0;
  for (Object[] p : plan.get(course)) {
    i++;
    String key = 'KT-AS-' + o.SectionNumber.substringAfter('KT-') + '-' + i;
    Date due = (Date) p[4];
    if (have.contains(key) || due < o.StartDate.date() || due > Date.today()) continue;
    if (Limits.getQueries() > 80 || Limits.getCpuTime() > 7000) { remaining++; continue; }
    Course_Assessment__c a = new Course_Assessment__c(Name = (String) p[0], Course_Offering__c = o.Id, Assessment_Type__c = (String) p[1],
      Max_Score__c = (Integer) p[2], Weight__c = (Integer) p[3], Assessment_Date__c = due, External_Id__c = key, Status__c = 'Draft');
    insert a;
    AssessmentService.Gradebook book = AssessmentService.getGradebook(a.Id);
    for (AssessmentService.ResultRow r : book.rows) {
      Integer ability = 55 + Math.mod(Math.abs(String.valueOf(r.learnerContactId).hashCode()), 41);
      if (Math.mod(Math.abs(String.valueOf(r.learnerContactId).hashCode()), 10) == 0) ability -= 15;
      Integer noise = Math.mod(Math.abs((key + r.learnerContactId).hashCode()), 17) - 8;
      Integer h = Math.abs((key + r.learnerContactId).hashCode());
      if (Math.mod(h, 25) == 0) { r.absent = true; r.feedback = 'Absent on the day'; continue; }
      Decimal pct = Math.max(25, Math.min(100, ability + noise));
      r.score = (pct * (Integer) p[2] / 100).setScale(0, RoundingMode.HALF_UP);
      r.feedback = praise[Math.mod(h, praise.size())];
    }
    AssessmentService.saveResults(a.Id, book.rows);
    AssessmentService.publish(a.Id);
    published++;
  }
}
System.debug('SEED6 published+' + published + ' remaining=' + remaining + ' soql=' + Limits.getQueries() + ' cpu=' + Limits.getCpuTime());
