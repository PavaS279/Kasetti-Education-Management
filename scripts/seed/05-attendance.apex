// KTEdutech seed 5/9: attendance for every past session of the KT classes. Re-run until "remaining=0".
// Realistic pattern: most learners attend ~93%; about one in ten attend ~65% (they show up on the retention desk).
List<String> absentNotes = new List<String>{ 'Unwell', 'Family function', 'School exam the next day', 'Travelling', 'No reason given', 'Fever' };
List<String> excusedNotes = new List<String>{ 'School sports day', 'Informed by parent in advance', 'Doctor\'s appointment' };
Integer marked = 0;
List<Class_Session__c> pending = [SELECT Id, Start__c FROM Class_Session__c WHERE Course_Offering__r.SectionNumber LIKE 'KT-%'
  AND Start__c < :System.now() AND Attendance_Marked__c = false AND Status__c != 'Cancelled' ORDER BY Start__c LIMIT 200];
for (Class_Session__c s : pending) {
  if (Limits.getQueries() > 85 || Limits.getCpuTime() > 7500 || Limits.getDmlStatements() > 130) break;
  AttendanceService.Register reg = AttendanceService.getRegister(s.Id);
  if (reg.rows.isEmpty()) {
    update new Class_Session__c(Id = s.Id, Attendance_Marked__c = true, Status__c = 'Completed');
    continue;
  }
  for (AttendanceService.RegisterRow row : reg.rows) {
    Integer h = Math.abs((String.valueOf(row.learnerContactId) + String.valueOf(s.Start__c.getTime())).hashCode());
    Boolean irregular = Math.mod(Math.abs(String.valueOf(row.learnerContactId).hashCode()), 10) == 0;
    Integer roll = Math.mod(h, 100);
    Integer presentCut = irregular ? 55 : 88;
    if (roll < presentCut) { row.status = 'Present'; }
    else if (roll < presentCut + 5) { row.status = 'Late'; row.minutesLate = 5 + Math.mod(h, 16); row.note = 'Traffic'; }
    else if (roll < presentCut + 7) { row.status = 'Excused'; row.note = excusedNotes[Math.mod(h, excusedNotes.size())]; }
    else { row.status = 'Absent'; row.note = absentNotes[Math.mod(h, absentNotes.size())]; }
  }
  AttendanceService.saveRegister(s.Id, reg.rows, 'Present');
  marked++;
}
Integer remaining = [SELECT COUNT() FROM Class_Session__c WHERE Course_Offering__r.SectionNumber LIKE 'KT-%' AND Start__c < :System.now() AND Attendance_Marked__c = false AND Status__c != 'Cancelled'];
System.debug('SEED5 registers+' + marked + ' remaining=' + remaining + ' soql=' + Limits.getQueries() + ' cpu=' + Limits.getCpuTime());
