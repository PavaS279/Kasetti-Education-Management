// KTEdutech seed 10/10: library, bus routes and riders, and the October mock Olympiad with hall tickets.
// Idempotent per section (item codes, route codes, exam codes). Re-run if it pauses.
Map<String, Id> branches = new Map<String, Id>();
for (Branch__c b : [SELECT Id, Branch_Code__c FROM Branch__c WHERE Branch_Code__c IN ('IND-01','KOR-01','HSR-01')]) branches.put(b.Branch_Code__c, b.Id);
Date today = Date.today();

// ---- Library ----
if ([SELECT COUNT() FROM Library_Item__c WHERE Item_Code__c LIKE 'IND-B-%' OR Item_Code__c LIKE 'KOR-B-%' OR Item_Code__c LIKE 'HSR-B-%'] == 0) {
  List<Library_Item__c> items = new List<Library_Item__c>();
  List<Object[]> rows = new List<Object[]>{
    new Object[]{'IND-01','IND-B-001','Wings of Fire','A. P. J. Abdul Kalam','Book','Biography',3,350},
    new Object[]{'IND-01','IND-B-002','The Man Who Knew Infinity','Robert Kanigel','Book','Mathematics',2,499},
    new Object[]{'IND-01','IND-B-003','Python Crash Course','Eric Matthes','Book','Programming',3,1250},
    new Object[]{'IND-01','IND-K-001','Arduino Uno Starter Kit','','Kit','Robotics',4,4500},
    new Object[]{'KOR-01','KOR-B-001','Vedic Mathematics','Jagadguru Swami Bharati Krishna Tirthaji','Book','Mathematics',3,395},
    new Object[]{'KOR-01','KOR-B-002','Scratch Programming Playground','Al Sweigart','Book','Programming',2,899},
    new Object[]{'KOR-01','KOR-B-003','Drawing on the Right Side of the Brain','Betty Edwards','Book','Art',2,699},
    new Object[]{'HSR-01','HSR-B-001','Mathematical Olympiad Challenges','Titu Andreescu','Book','Mathematics',2,1450},
    new Object[]{'HSR-01','HSR-B-002','Challenge and Thrill of Pre-College Mathematics','V. Krishnamurthy','Book','Mathematics',3,450},
    new Object[]{'HSR-01','HSR-K-001','mBot Robotics Kit','','Kit','Robotics',3,6200}};
  for (Object[] r : rows) items.add(new Library_Item__c(Name = (String) r[2], Branch__c = branches.get((String) r[0]), Item_Code__c = (String) r[1], Author__c = (String) r[3],
    Item_Type__c = (String) r[4], Subject__c = (String) r[5], Copies_Total__c = (Integer) r[6], Replacement_Cost__c = (Integer) r[7],
    Loan_Days__c = r[4] == 'Kit' ? 7 : 14, Daily_Fine__c = r[4] == 'Kit' ? 20 : 5, Location__c = r[4] == 'Kit' ? 'Lab cupboard' : 'Reading corner', Active__c = true));
  insert items;
  // Loans to learners of each centre: some returned, some on loan, two overdue.
  Integer n = 0;
  for (Library_Item__c item : items) {
    List<Account> borrowers = [SELECT Id FROM Account WHERE Branch__c = :item.Branch__c AND External_Id__c LIKE 'KT-FAM-%-L%' ORDER BY External_Id__c LIMIT 2 OFFSET :Math.mod(n * 3, 20)];
    for (Account b : borrowers) {
      if (Limits.getQueries() > 70) break;
      Id loanId = LibraryService.issue(item.Id, b.Id);
      Integer kind = Math.mod(n, 4);
      if (kind == 0) { // returned on time in September
        update new Library_Loan__c(Id = loanId, Loaned_On__c = Date.newInstance(2026, 9, 5), Due_On__c = Date.newInstance(2026, 9, 5).addDays(item.Item_Type__c == 'Kit' ? 7 : 14));
        LibraryService.returnLoan(loanId, 'Good');
        update new Library_Loan__c(Id = loanId, Returned_On__c = Date.newInstance(2026, 9, 15));
      } else if (kind == 1) { // overdue
        update new Library_Loan__c(Id = loanId, Loaned_On__c = Date.newInstance(2026, 9, 12), Due_On__c = Date.newInstance(2026, 9, 26));
      } else { // on loan, due later this month
        update new Library_Loan__c(Id = loanId, Loaned_On__c = today.addDays(-3 - kind), Due_On__c = today.addDays(11 - kind));
      }
      n++;
    }
  }
  LibraryService.processOverdue(today);
  System.debug('SEED10 library items+' + items.size() + ' loans+' + n);
  return;
}

// ---- Bus routes ----
if ([SELECT COUNT() FROM Transport_Route__c WHERE Route_Code__c IN ('IND-R1','HSR-R1')] == 0) {
  Transport_Route__c ind = new Transport_Route__c(Name = 'Indiranagar – Domlur – HAL', Route_Code__c = 'IND-R1', Branch__c = branches.get('IND-01'), Capacity__c = 12,
    Monthly_Fee__c = 1500, Vehicle_Number__c = 'KA 03 AB 4521', Driver_Name__c = 'Manjunath S', Driver_Phone__c = '+91 98450 22184', Attendant_Name__c = 'Lakshmamma K',
    Morning_Start__c = '08:00', Afternoon_Start__c = '16:45', Active__c = true, Notes__c = 'Weekend route for Saturday and Sunday classes.');
  Transport_Route__c hsr = new Transport_Route__c(Name = 'HSR Layout – Agara – Bellandur', Route_Code__c = 'HSR-R1', Branch__c = branches.get('HSR-01'), Capacity__c = 10,
    Monthly_Fee__c = 1300, Vehicle_Number__c = 'KA 51 MC 7730', Driver_Name__c = 'Ravi Kumar', Driver_Phone__c = '+91 99860 41532', Attendant_Name__c = 'Shantha',
    Morning_Start__c = '08:15', Afternoon_Start__c = '16:30', Active__c = true, Notes__c = 'Saturday route.');
  insert new List<Transport_Route__c>{ ind, hsr };
  insert new List<Transport_Stop__c>{
    new Transport_Stop__c(Route__c = ind.Id, Name = 'Domlur Bus Stop', Sequence__c = 1, Pickup_Time__c = '08:05', Drop_Time__c = '17:20', Landmark__c = 'Opposite Domlur flyover', Active__c = true),
    new Transport_Stop__c(Route__c = ind.Id, Name = 'HAL 3rd Stage Park', Sequence__c = 2, Pickup_Time__c = '08:15', Drop_Time__c = '17:10', Landmark__c = 'Near Ganesha temple', Active__c = true),
    new Transport_Stop__c(Route__c = ind.Id, Name = 'Jeevan Bima Nagar Main Road', Sequence__c = 3, Pickup_Time__c = '08:25', Drop_Time__c = '17:00', Landmark__c = 'BDA complex', Active__c = true),
    new Transport_Stop__c(Route__c = hsr.Id, Name = 'Agara Lake Gate', Sequence__c = 1, Pickup_Time__c = '08:20', Drop_Time__c = '16:55', Landmark__c = 'Lake main gate', Active__c = true),
    new Transport_Stop__c(Route__c = hsr.Id, Name = 'HSR Sector 6 BDA Complex', Sequence__c = 2, Pickup_Time__c = '08:30', Drop_Time__c = '16:45', Landmark__c = 'Bus stop near BDA complex', Active__c = true),
    new Transport_Stop__c(Route__c = hsr.Id, Name = 'Bellandur Gate', Sequence__c = 3, Pickup_Time__c = '08:40', Drop_Time__c = '16:35', Landmark__c = 'Ecospace signal', Active__c = true)};
  System.debug('SEED10 routes+2 stops+6');
  return;
}
Integer riders = [SELECT COUNT() FROM Transport_Assignment__c WHERE Route__r.Route_Code__c IN ('IND-R1','HSR-R1')];
if (riders < 12) {
  Date fromNov = Date.newInstance(2026, 11, 1);
  Integer added = 0;
  for (Transport_Route__c r : [SELECT Id, Branch__c, (SELECT Id FROM Stops__r ORDER BY Sequence__c) FROM Transport_Route__c WHERE Route_Code__c IN ('IND-R1','HSR-R1')]) {
    Integer i = 0;
    Set<Id> riding = new Set<Id>();
    for (Transport_Assignment__c t : [SELECT Learner_Account__c FROM Transport_Assignment__c]) riding.add(t.Learner_Account__c);
    for (CourseOfferingParticipant e : [SELECT ParticipantContact.AccountId FROM CourseOfferingParticipant
        WHERE CourseOffering.Branch__c = :r.Branch__c AND CourseOffering.SectionNumber LIKE 'KT-%' AND ParticipationStatus = 'Enrolled'
        AND StartDate <= :today ORDER BY ParticipantContact.LastName LIMIT 40]) {
      if (Limits.getQueries() > 75 || i >= 7) break;
      if (riding.contains(e.ParticipantContact.AccountId)) continue;
      riding.add(e.ParticipantContact.AccountId);
      TransportService.AssignRequest q = new TransportService.AssignRequest();
      q.learnerAccountId = e.ParticipantContact.AccountId; q.routeId = r.Id; q.stopId = r.Stops__r[Math.mod(i, r.Stops__r.size())].Id;
      q.direction = Math.mod(i, 4) == 3 ? 'Morning only' : 'Both ways'; q.startDate = fromNov; q.chargeFee = true;
      try { TransportService.assign(q); added++; } catch (Exception ex) { System.debug('skip rider: ' + ex.getMessage()); }
      i++;
    }
  }
  System.debug('SEED10 riders+' + added);
  return;
}

// ---- Mock Olympiad with hall tickets ----
List<Object[]> exams = new List<Object[]>{
  new Object[]{'HSR-01','HSR-OLY-T1','Mock Olympiad – Term 1 (HSR Layout)','KT-HSR-OLY6-SAT',Date.newInstance(2026,10,24),'Mock Olympiad – Grade 6', new List<String>{'Bhaskara Room','Hopper Lab'}},
  new Object[]{'IND-01','IND-OLY-T1','Mock Olympiad – Term 1 (Indiranagar)','KT-IND-OLY7-SUN',Date.newInstance(2026,10,25),'Mock Olympiad – Grade 7', new List<String>{'Raman Hall'}}};
for (Object[] x : exams) {
  if ([SELECT COUNT() FROM Exam__c WHERE Exam_Code__c = :(String) x[1]] > 0) continue;
  Date d = (Date) x[4];
  Exam__c ex = new Exam__c(Name = (String) x[2], Exam_Code__c = (String) x[1], Branch__c = branches.get((String) x[0]), Exam_Type__c = 'Mock',
    Start_Date__c = d, End_Date__c = d, Min_Attendance__c = 75, Block_Overdue_Fees__c = false,
    Instructions__c = 'Report 20 minutes before the start with this hall ticket, a pencil, eraser and geometry box. Calculators and phones are not allowed.');
  insert ex;
  Id cls = [SELECT Id FROM CourseOffering WHERE SectionNumber = :(String) x[3]].Id;
  insert new Exam_Paper__c(Exam__c = ex.Id, Name = (String) x[5], Course_Offering__c = cls, Paper_Date__c = d, Start_Time__c = '10:00', Duration_Minutes__c = 120, Max_Marks__c = 100, Pass_Marks__c = 35, Weight__c = 30);
  ExamService.registerCandidates(ex.Id);
  ExamService.checkEligibility(ex.Id);
  List<Id> rooms = new List<Id>();
  for (Room__c rm : [SELECT Id FROM Room__c WHERE Branch__c = :ex.Branch__c AND Name IN :(List<String>) x[6]]) rooms.add(rm.Id);
  ExamService.allocateSeats(ex.Id, rooms);
  System.debug('SEED10 exam ' + x[1] + ' tickets ' + ExamService.issueTickets(ex.Id));
  return;
}
System.debug('SEED10 done');
