// KTEdutech seed 2/9: classes (term July–December 2026), weekly patterns and sessions. Idempotent on SectionNumber.
Map<String, Id> users = new Map<String, Id>();
for (User u : [SELECT Id, Name FROM User WHERE Name IN ('Kasetti Tech','Anjali Advisor')]) users.put(u.Name, u.Id);
Map<String, Id> branches = new Map<String, Id>();
for (Branch__c b : [SELECT Id, Branch_Code__c FROM Branch__c WHERE Branch_Code__c IN ('IND-01','KOR-01','HSR-01')]) branches.put(b.Branch_Code__c, b.Id);
Map<String, Id> rooms = new Map<String, Id>();
for (Room__c r : [SELECT Id, External_Id__c FROM Room__c WHERE External_Id__c LIKE 'KT-RM-%']) rooms.put(r.External_Id__c, r.Id);
Map<String, Id> courses = new Map<String, Id>();
for (LearningCourse c : [SELECT Id, External_ID__c FROM LearningCourse WHERE External_ID__c LIKE 'KT-CRS-%']) courses.put(c.External_ID__c, c.Id);
Map<String, Id> faculty = new Map<String, Id>();
for (Contact c : [SELECT Id, LastName FROM Contact WHERE Account.External_Id__c = 'KT-FACULTY']) faculty.put(c.LastName, c.Id);
Set<String> have = new Set<String>();
for (CourseOffering o : [SELECT SectionNumber FROM CourseOffering WHERE SectionNumber LIKE 'KT-%']) have.add(o.SectionNumber);

// section, name, course, branch, room, faculty, teacher user, capacity, days, start h, start m, minutes, start date, status, mode
List<Object[]> rows = new List<Object[]>{
  new Object[]{'KT-IND-ABA2-SAT','Abacus Level 2 – Saturday 09:30','KT-CRS-ABA','IND-01','Ramanujan Room','Raghavan',null,12,'Sat',9,30,90,Date.newInstance(2026,7,4),'Open','Classroom'},
  new Object[]{'KT-IND-PYT-SAT','Python for Kids – Saturday 12:00','KT-CRS-PYT','IND-01','Turing Lab','Kulkarni',null,10,'Sat',12,0,90,Date.newInstance(2026,7,4),'Open','Classroom'},
  new Object[]{'KT-IND-OLY7-SUN','Olympiad Maths Grade 7 – Sunday 10:00','KT-CRS-OLY','IND-01','Ramanujan Room','Narayan','Anjali Advisor',12,'Sun',10,0,90,Date.newInstance(2026,7,5),'Open','Classroom'},
  new Object[]{'KT-IND-ROB-WED','Robotics with Arduino – Wednesday 17:00','KT-CRS-ROB','IND-01','Turing Lab','Iyengar','Kasetti Tech',10,'Wed',17,0,90,Date.newInstance(2026,7,8),'Open','Classroom'},
  new Object[]{'KT-IND-ENG-TT','Spoken English – Tuesday and Thursday 17:30','KT-CRS-ENG','IND-01','Raman Hall','D\'Souza',null,16,'Tue,Thu',17,30,60,Date.newInstance(2026,7,7),'Open','Classroom'},
  new Object[]{'KT-KOR-VED-SAT','Vedic Maths – Saturday 10:00','KT-CRS-VED','KOR-01','Aryabhata Room','Hegde',null,12,'Sat',10,0,90,Date.newInstance(2026,7,4),'Open','Classroom'},
  new Object[]{'KT-KOR-SCR-SAT','Scratch Coding Junior – Saturday 15:00','KT-CRS-SCR','KOR-01','Lovelace Lab','Mathew',null,10,'Sat',15,0,90,Date.newInstance(2026,7,4),'Open','Classroom'},
  new Object[]{'KT-KOR-ART-SUN','Drawing and Painting – Sunday 11:00','KT-CRS-ART','KOR-01','Tagore Studio','Rao',null,15,'Sun',11,0,90,Date.newInstance(2026,7,5),'Open','Classroom'},
  new Object[]{'KT-KOR-PYT-FRI','Python for Kids – Friday 17:00','KT-CRS-PYT','KOR-01','Lovelace Lab','Kulkarni','Kasetti Tech',10,'Fri',17,0,90,Date.newInstance(2026,7,10),'Open','Classroom'},
  new Object[]{'KT-HSR-ABA1-WED','Abacus Level 1 – Wednesday 16:30','KT-CRS-ABA','HSR-01','Bhaskara Room','Raghavan','Anjali Advisor',12,'Wed',16,30,90,Date.newInstance(2026,7,8),'Open','Classroom'},
  new Object[]{'KT-HSR-ROB-SAT','Robotics with Arduino – Saturday 14:00','KT-CRS-ROB','HSR-01','Hopper Lab','Iyengar',null,10,'Sat',14,0,90,Date.newInstance(2026,7,4),'Open','Classroom'},
  new Object[]{'KT-HSR-OLY6-SAT','Olympiad Maths Grade 6 – Saturday 10:00','KT-CRS-OLY','HSR-01','Bhaskara Room','Narayan',null,12,'Sat',10,0,90,Date.newInstance(2026,7,4),'Open','Classroom'},
  new Object[]{'KT-HSR-SCR-SUN','Scratch Coding Junior – Sunday 10:00 (from November)','KT-CRS-SCR','HSR-01','Hopper Lab','Mathew',null,10,'Sun',10,0,90,Date.newInstance(2026,11,15),'Open','Classroom'}};
String[] codes = new String[]{'IND','KOR','HSR'};
Integer created = 0, sessions = 0;
for (Object[] r : rows) {
  String section = (String) r[0];
  if (have.contains(section)) continue;
  String branch = (String) r[3];
  Date startDate = (Date) r[12];
  CourseOffering o = new CourseOffering(Name = (String) r[1], SectionNumber = section, LearningCourseId = courses.get((String) r[2]), Branch__c = branches.get(branch),
    Room__c = rooms.get('KT-RM-' + branch + '-' + ((String) r[4]).replace(' ', '')), PrimaryFacultyId = faculty.get((String) r[5]),
    Teacher_User__c = r[6] == null ? null : users.get((String) r[6]), EnrollmentCapacity = (Integer) r[7], Delivery_Mode__c = (String) r[14], Class_Status__c = (String) r[13],
    StartDate = Datetime.newInstance(startDate, Time.newInstance(8, 0, 0, 0)), EndDate = Datetime.newInstance(Date.newInstance(2026, 12, 20), Time.newInstance(20, 0, 0, 0)));
  insert o;
  String days = (String) r[8];
  Time st = Time.newInstance((Integer) r[9], (Integer) r[10], 0, 0);
  CourseOfferingSchedule p = new CourseOfferingSchedule(CourseOfferingId = o.Id, Description = days.replace(',', ' and ') + ' ' + String.valueOf(st).left(5),
    StartTime = st, EndTime = st.addMinutes((Integer) r[11]), StartDate = startDate,
    IsMonday = days.contains('Mon'), IsTuesday = days.contains('Tue'), IsWednesday = days.contains('Wed'), IsThursday = days.contains('Thu'),
    IsFriday = days.contains('Fri'), IsSaturday = days.contains('Sat'), IsSunday = days.contains('Sun'));
  insert p;
  SessionService.GenerationResult g = SessionService.generate(o.Id);
  created++;
  System.debug('CLASS ' + section + ' sessions ' + g);
  if (Limits.getCpuTime() > 7000 || Limits.getQueries() > 80) break;
}
System.debug('SEED2 classes+' + created + ' cpu=' + Limits.getCpuTime() + ' soql=' + Limits.getQueries());
