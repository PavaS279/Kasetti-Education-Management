// KTEdutech seed 1/9: faculty, centres, rooms, staff roles, courses, prices, discounts, holidays.
// Idempotent: records are matched on their KT- external ids / codes.
Map<String, Id> users = new Map<String, Id>();
for (User u : [SELECT Id, Name FROM User WHERE Name IN ('Kasetti Tech','Rahul Registrar','Adam Admissions','Anjali Advisor','Andrea Advancement') AND IsActive = true]) users.put(u.Name, u.Id);

// Faculty (teaching staff shown on classes as Primary Faculty)
Id businessRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Business_Account').getRecordTypeId();
List<Account> fa = [SELECT Id FROM Account WHERE External_Id__c = 'KT-FACULTY'];
Account faculty = fa.isEmpty() ? new Account(Name = 'KT Edutech Faculty', RecordTypeId = businessRt, External_Id__c = 'KT-FACULTY', Phone = '+91 80 4123 7700', Industry = 'Education') : fa[0];
if (faculty.Id == null) insert faculty;
List<String[]> facultyRows = new List<String[]>{
  new String[]{'Meenakshi','Raghavan','Abacus and Vedic Maths'}, new String[]{'Arvind','Kulkarni','Python and Coding'},
  new String[]{'Lakshmi','Narayan','Olympiad Mathematics'}, new String[]{'Karthik','Iyengar','Robotics and Electronics'},
  new String[]{'Sarah','DSouza','Spoken English'}, new String[]{'Priyanka','Hegde','Vedic Maths'},
  new String[]{'Rohan','Mathew','Scratch and Game Design'}, new String[]{'Nandini','Rao','Art and Design'}};
Set<String> haveFaculty = new Set<String>();
for (Contact c : [SELECT LastName FROM Contact WHERE AccountId = :faculty.Id]) haveFaculty.add(c.LastName);
List<Contact> newFaculty = new List<Contact>();
for (String[] r : facultyRows) {
  String last = r[1] == 'DSouza' ? 'D\'Souza' : r[1];
  if (!haveFaculty.contains(last)) newFaculty.add(new Contact(AccountId = faculty.Id, FirstName = r[0], LastName = last, Title = 'Faculty – ' + r[2],
    Email = (r[0] + '.' + r[1]).toLowerCase() + '@ktedutech.example.com', Department = 'Academics'));
}
insert newFaculty;

// Centres
Map<String, Branch__c> branches = new Map<String, Branch__c>();
for (Branch__c b : [SELECT Id, Branch_Code__c FROM Branch__c WHERE Branch_Code__c IN ('IND-01','KOR-01','HSR-01')]) branches.put(b.Branch_Code__c, b);
List<Branch__c> newBranches = new List<Branch__c>();
List<Object[]> branchRows = new List<Object[]>{
  new Object[]{'KT Edutech Indiranagar','IND-01','IND','No. 412, 100 Feet Road, HAL 2nd Stage','560038','+91 80 4123 7711','indiranagar@ktedutech.example.com', users.get('Rahul Registrar')},
  new Object[]{'KT Edutech Koramangala','KOR-01','KOR','No. 58, 80 Feet Road, 5th Block','560095','+91 80 4123 7722','koramangala@ktedutech.example.com', users.get('Rahul Registrar')},
  new Object[]{'KT Edutech HSR Layout','HSR-01','HSR','No. 1173, 24th Main Road, Sector 2','560102','+91 80 4123 7733','hsrlayout@ktedutech.example.com', users.get('Rahul Registrar')}};
for (Object[] r : branchRows) {
  if (branches.containsKey((String) r[1])) continue;
  newBranches.add(new Branch__c(Name = (String) r[0], Branch_Code__c = (String) r[1], Invoice_Prefix__c = (String) r[2], Street__c = (String) r[3],
    City__c = 'Bengaluru', State__c = 'Karnataka', Postal_Code__c = (String) r[4], Country__c = 'India', Phone__c = (String) r[5], Email__c = (String) r[6],
    Operating_Hours__c = 'Tue–Fri 15:30–20:00, Sat–Sun 08:30–18:00', Invoice_Due_Days__c = 10, Tax_Rate__c = 18, Attendance_Threshold__c = 75,
    Cancellation_Notice_Hours__c = 24, Active__c = true, External_Id__c = 'KT-BR-' + r[1], Branch_Manager__c = (Id) r[7]));
}
insert newBranches;
for (Branch__c b : newBranches) branches.put(b.Branch_Code__c, b);

// Rooms
Set<String> haveRooms = new Set<String>();
for (Room__c rm : [SELECT External_Id__c FROM Room__c WHERE External_Id__c LIKE 'KT-RM-%']) haveRooms.add(rm.External_Id__c);
List<Room__c> rooms = new List<Room__c>();
List<String[]> roomRows = new List<String[]>{
  new String[]{'IND-01','Ramanujan Room','12','Classroom','Smart Board'}, new String[]{'IND-01','Turing Lab','10','Laboratory','Computers;Projector'},
  new String[]{'IND-01','Raman Hall','20','Hall','Projector;Audio System'},
  new String[]{'KOR-01','Aryabhata Room','12','Classroom','Smart Board;Video Conferencing'}, new String[]{'KOR-01','Lovelace Lab','10','Laboratory','Computers;Projector'},
  new String[]{'KOR-01','Tagore Studio','15','Studio','Projector'},
  new String[]{'HSR-01','Bhaskara Room','12','Classroom','Projector;Smart Board'}, new String[]{'HSR-01','Hopper Lab','10','Laboratory','Computers;Lab Equipment'}};
for (String[] r : roomRows) {
  String key = 'KT-RM-' + r[0] + '-' + r[1].replace(' ', '');
  if (haveRooms.contains(key)) continue;
  rooms.add(new Room__c(Name = r[1], Branch__c = branches.get(r[0]).Id, Capacity__c = Integer.valueOf(r[2]), Room_Type__c = r[3], Equipment__c = r[4], Active__c = true, External_Id__c = key));
}
insert rooms;

// Staff roles at the centres
Set<String> haveStaff = new Set<String>();
for (Branch_Staff__c s : [SELECT Branch__r.Branch_Code__c, User__c, Role__c FROM Branch_Staff__c WHERE Branch__r.Branch_Code__c IN ('IND-01','KOR-01','HSR-01')]) haveStaff.add(s.Branch__r.Branch_Code__c + s.User__c + s.Role__c);
List<Branch_Staff__c> staff = new List<Branch_Staff__c>();
List<String[]> staffRows = new List<String[]>{
  new String[]{'IND-01','Rahul Registrar','Branch Manager'}, new String[]{'KOR-01','Rahul Registrar','Branch Manager'}, new String[]{'HSR-01','Rahul Registrar','Branch Manager'},
  new String[]{'IND-01','Adam Admissions','Admissions Counsellor'}, new String[]{'KOR-01','Adam Admissions','Admissions Counsellor'}, new String[]{'HSR-01','Adam Admissions','Admissions Counsellor'},
  new String[]{'IND-01','Anjali Advisor','Academic Coordinator'}, new String[]{'KOR-01','Anjali Advisor','Academic Coordinator'}, new String[]{'HSR-01','Anjali Advisor','Academic Coordinator'},
  new String[]{'IND-01','Anjali Advisor','Teacher'}, new String[]{'HSR-01','Anjali Advisor','Teacher'},
  new String[]{'IND-01','Kasetti Tech','Teacher'}, new String[]{'KOR-01','Kasetti Tech','Teacher'},
  new String[]{'IND-01','Andrea Advancement','Finance'}, new String[]{'KOR-01','Andrea Advancement','Finance'}, new String[]{'HSR-01','Andrea Advancement','Finance'}};
for (String[] r : staffRows) {
  Id uid = users.get(r[1]);
  if (uid == null || haveStaff.contains(r[0] + uid + r[2])) continue;
  staff.add(new Branch_Staff__c(Branch__c = branches.get(r[0]).Id, User__c = uid, Role__c = r[2], Active__c = true));
}
insert staff;

// Courses
Map<String, LearningCourse> courses = new Map<String, LearningCourse>();
for (LearningCourse c : [SELECT Id, External_ID__c FROM LearningCourse WHERE External_ID__c LIKE 'KT-CRS-%']) courses.put(c.External_ID__c, c);
List<Object[]> courseRows = new List<Object[]>{
  new Object[]{'KT-CRS-ABA','Abacus and Mental Arithmetic', 'Bead-frame arithmetic and mental calculation in eight levels; builds speed, concentration and number sense.', 6, 12},
  new Object[]{'KT-CRS-VED','Vedic Maths', 'Fast calculation techniques from Vedic sutras for multiplication, division, squares and roots; ideal before board exams.', 10, 15},
  new Object[]{'KT-CRS-OLY','Olympiad Mathematics (Grades 6–8)', 'Problem solving for IMO, NSTSE and RMO preparation: number theory, geometry, combinatorics and logical reasoning.', 11, 14},
  new Object[]{'KT-CRS-PYT','Python for Kids', 'Programming fundamentals in Python: variables, loops, functions and small games and data projects.', 10, 16},
  new Object[]{'KT-CRS-SCR','Scratch Coding Junior', 'Block-based coding with Scratch: animations, stories and games that teach sequencing, loops and events.', 7, 10},
  new Object[]{'KT-CRS-ROB','Robotics with Arduino', 'Hands-on electronics and robotics: circuits, sensors, motors and Arduino programming with a take-home kit.', 11, 16},
  new Object[]{'KT-CRS-ENG','Spoken English and Public Speaking', 'Confident spoken English through conversation, storytelling, debates and presentations.', 8, 15},
  new Object[]{'KT-CRS-ART','Drawing and Painting', 'Sketching, colour theory, watercolour and acrylic techniques with a term-end exhibition.', 6, 13}};
for (Object[] r : courseRows) {
  if (courses.containsKey((String) r[0])) continue;
  Learning l = new Learning(Name = (String) r[1], Type = 'LearningCourse', IsActive = true);
  insert l;
  LearningCourse c = new LearningCourse(Name = (String) r[1], LearningId = l.Id, External_ID__c = (String) r[0], Description = (String) r[2],
    Minimum_Age__c = (Integer) r[3], Maximum_Age__c = (Integer) r[4]);
  insert c;
  courses.put(c.External_ID__c, c);
}

// Fee prices (INR, before 18% tax)
Set<String> havePrices = new Set<String>();
for (Fee_Price__c p : [SELECT External_Id__c FROM Fee_Price__c WHERE External_Id__c LIKE 'KT-PRC-%']) havePrices.add(p.External_Id__c);
List<Fee_Price__c> prices = new List<Fee_Price__c>();
List<Object[]> priceRows = new List<Object[]>{
  // course, fee type, frequency, amount, branch code (null = all), description
  new Object[]{'KT-CRS-ABA','Admission','One-time',1500,null,'Admission and assessment'}, new Object[]{'KT-CRS-ABA','Tuition','Monthly',2200,null,'Monthly tuition (4 classes)'}, new Object[]{'KT-CRS-ABA','Materials','One-time',1200,null,'Abacus kit and level workbook'},
  new Object[]{'KT-CRS-VED','Admission','One-time',1500,null,'Admission and assessment'}, new Object[]{'KT-CRS-VED','Tuition','Monthly',2000,null,'Monthly tuition (4 classes)'},
  new Object[]{'KT-CRS-OLY','Admission','One-time',1500,null,'Admission and diagnostic test'}, new Object[]{'KT-CRS-OLY','Tuition','Term',9500,null,'Term tuition (July–December)'}, new Object[]{'KT-CRS-OLY','Materials','One-time',800,null,'Olympiad problem books'},
  new Object[]{'KT-CRS-PYT','Admission','One-time',1500,null,'Admission and laptop orientation'}, new Object[]{'KT-CRS-PYT','Tuition','Monthly',3200,null,'Monthly tuition (4 classes)'}, new Object[]{'KT-CRS-PYT','Tuition','Monthly',3000,'KOR-01','Monthly tuition (4 classes), Koramangala'},
  new Object[]{'KT-CRS-SCR','Admission','One-time',1000,null,'Admission'}, new Object[]{'KT-CRS-SCR','Tuition','Monthly',2600,null,'Monthly tuition (4 classes)'},
  new Object[]{'KT-CRS-ROB','Admission','One-time',1500,null,'Admission'}, new Object[]{'KT-CRS-ROB','Tuition','Monthly',3800,null,'Monthly tuition (4 classes)'}, new Object[]{'KT-CRS-ROB','Materials','One-time',4500,null,'Arduino starter kit (take home)'},
  new Object[]{'KT-CRS-ENG','Admission','One-time',1000,null,'Admission and speaking assessment'}, new Object[]{'KT-CRS-ENG','Tuition','Term',7500,null,'Term tuition (July–December, twice a week)'},
  new Object[]{'KT-CRS-ART','Admission','One-time',1000,null,'Admission'}, new Object[]{'KT-CRS-ART','Tuition','Monthly',1800,null,'Monthly tuition (4 classes)'}, new Object[]{'KT-CRS-ART','Materials','One-time',900,null,'Art supplies kit'}};
for (Object[] r : priceRows) {
  String key = 'KT-PRC-' + ((String) r[0]).substringAfter('KT-CRS-') + '-' + ((String) r[1]).left(3).toUpperCase() + '-' + ((String) r[2]).left(1) + (r[4] == null ? '' : '-' + ((String) r[4]).left(3));
  if (havePrices.contains(key)) continue;
  prices.add(new Fee_Price__c(Learning_Course__c = courses.get((String) r[0]).Id, Fee_Type__c = (String) r[1], Billing_Frequency__c = (String) r[2], Amount__c = (Integer) r[3],
    Branch__c = r[4] == null ? null : branches.get((String) r[4]).Id, Description__c = (String) r[5], Effective_From__c = Date.newInstance(2026, 4, 1), Active__c = true, External_Id__c = key));
}
insert prices;

// Discounts
Set<String> haveCodes = new Set<String>();
for (Discount__c d : [SELECT Code__c FROM Discount__c]) haveCodes.add(d.Code__c);
List<Discount__c> discounts = new List<Discount__c>();
if (!haveCodes.contains('EARLYBIRD5')) discounts.add(new Discount__c(Name = 'Early bird 5%', Code__c = 'EARLYBIRD5', Discount_Type__c = 'Percentage', Value__c = 5, Fee_Type__c = 'Tuition', Valid_From__c = Date.newInstance(2026, 4, 1), Valid_To__c = Date.newInstance(2026, 6, 30), Active__c = true, Description__c = 'For admissions confirmed before the July term'));
if (!haveCodes.contains('STAFFKIDS15')) discounts.add(new Discount__c(Name = 'Staff children 15%', Code__c = 'STAFFKIDS15', Discount_Type__c = 'Percentage', Value__c = 15, Fee_Type__c = 'Tuition', Requires_Approval__c = true, Active__c = true, Description__c = 'Children of KT Edutech staff; approved by finance'));
if (!haveCodes.contains('ADMWAIVE')) discounts.add(new Discount__c(Name = 'Admission fee waiver', Code__c = 'ADMWAIVE', Discount_Type__c = 'Fixed Amount', Value__c = 1000, Fee_Type__c = 'Admission', Requires_Approval__c = true, Max_Uses__c = 25, Active__c = true, Description__c = 'Open-house event offer'));
insert discounts;

// Holidays and term breaks (all three centres)
Set<String> haveClosures = new Set<String>();
for (Calendar_Closure__c c : [SELECT Name, Branch__r.Branch_Code__c FROM Calendar_Closure__c WHERE Branch__r.Branch_Code__c IN ('IND-01','KOR-01','HSR-01')]) haveClosures.add(c.Branch__r.Branch_Code__c + c.Name);
List<Calendar_Closure__c> closures = new List<Calendar_Closure__c>();
List<Object[]> closureRows = new List<Object[]>{
  new Object[]{'Independence Day', Date.newInstance(2026,8,15), Date.newInstance(2026,8,15), 'Public Holiday'},
  new Object[]{'Ganesh Chaturthi', Date.newInstance(2026,9,14), Date.newInstance(2026,9,14), 'Public Holiday'},
  new Object[]{'Gandhi Jayanti', Date.newInstance(2026,10,2), Date.newInstance(2026,10,2), 'Public Holiday'},
  new Object[]{'Dussehra break', Date.newInstance(2026,10,19), Date.newInstance(2026,10,21), 'Term Break'},
  new Object[]{'Kannada Rajyotsava', Date.newInstance(2026,11,1), Date.newInstance(2026,11,1), 'Public Holiday'},
  new Object[]{'Deepavali break', Date.newInstance(2026,11,7), Date.newInstance(2026,11,10), 'Term Break'},
  new Object[]{'Christmas and New Year break', Date.newInstance(2026,12,24), Date.newInstance(2027,1,1), 'Term Break'}};
for (String code : new List<String>{'IND-01','KOR-01','HSR-01'}) for (Object[] r : closureRows) {
  if (haveClosures.contains(code + r[0])) continue;
  closures.add(new Calendar_Closure__c(Name = (String) r[0], Branch__c = branches.get(code).Id, Start_Date__c = (Date) r[1], End_Date__c = (Date) r[2], Closure_Type__c = (String) r[3]));
}
insert closures;
System.debug('SEED1 faculty+' + newFaculty.size() + ' branches+' + newBranches.size() + ' rooms+' + rooms.size() + ' staff+' + staff.size() + ' courses=' + courses.size() + ' prices+' + prices.size() + ' discounts+' + discounts.size() + ' closures+' + closures.size());
