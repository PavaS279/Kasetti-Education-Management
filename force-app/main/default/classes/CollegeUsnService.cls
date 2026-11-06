/**
 * VTU University Seat Numbers (USN) for enrolled college students.
 *
 * A USN is 10 characters: region digit, two-letter college code, two-digit year
 * of joining, two-letter branch code, three-digit serial (for example
 * 1KT26CS001). It must match the student's campus VTU codes, their admission
 * year and their branch VTU code, and be unique. College staff (the admission
 * desk and the Dean) enter it once, one at a time or from a CSV
 * (Enrolment Number, USN); after that only a System Administrator can change
 * it, with a reason that is logged.
 */
public without sharing class CollegeUsnService {
  private static final String USN_PATTERN = '^[1-9][A-Z]{2}[0-9]{2}[A-Z]{2}[0-9]{3}$';

  public class RowResult {
    @AuraEnabled
    public Integer line;
    @AuraEnabled
    public String enrolmentNumber;
    @AuraEnabled
    public String usn;
    @AuraEnabled
    public String student;
    @AuraEnabled
    public Boolean ok = false;
    @AuraEnabled
    public String reason;
  }

  public class UploadResult {
    @AuraEnabled
    public List<RowResult> rows = new List<RowResult>();
    @AuraEnabled
    public Integer accepted = 0;
    @AuraEnabled
    public Integer rejected = 0;
    @AuraEnabled
    public Boolean saved = false;
  }

  public static Boolean canSet() {
    return FeatureManagement.checkPermission(
        CollegeDocumentService.VERIFY_PERMISSION
      ) ||
      FeatureManagement.checkPermission(InterviewService.PERMISSION) ||
      CollegeSetupController.canEdit();
  }

  private static void assertCanSet() {
    if (!canSet()) {
      throw new AppException(
        'Only college admission staff can enter university seat numbers.'
      );
    }
  }

  private static List<Programme_Enrolment__c> load(
    String field,
    Set<String> keys
  ) {
    return Database.queryWithBinds(
      'SELECT Id, Roll_Number__c, USN__c, Status__c, Admission_Year__c, Student__r.Name, ' +
        'Campus__r.Name, Campus__r.VTU_Region_Code__c, Campus__r.VTU_College_Code__c, ' +
        'Branch__r.Name, Branch__r.VTU_Branch_Code__c, Branch__r.Branch_Code__c ' +
        'FROM Programme_Enrolment__c WHERE ' +
        field +
        ' IN :keys',
      new Map<String, Object>{ 'keys' => keys },
      AccessLevel.SYSTEM_MODE
    );
  }

  /** Why this USN cannot be given to this student; null when it can. */
  public static String problem(Programme_Enrolment__c e, String usn) {
    if (String.isBlank(usn) || !Pattern.matches(USN_PATTERN, usn)) {
      return 'A USN is 10 characters like 1KT26CS001 (region digit, college code, year, branch code, serial).';
    }
    if (String.isBlank(e.Roll_Number__c)) {
      return 'The student is not enrolled yet (no enrolment number).';
    }
    String region = e.Campus__r?.VTU_Region_Code__c;
    String college = e.Campus__r?.VTU_College_Code__c;
    if (String.isBlank(region) || String.isBlank(college)) {
      return 'Set the VTU region and college codes for ' +
        e.Campus__r?.Name +
        ' in College Admission Setup → University first.';
    }
    if (usn.left(1) != region || usn.substring(1, 3) != college.toUpperCase()) {
      return 'The USN starts with ' +
        usn.left(3) +
        ' but ' +
        e.Campus__r.Name +
        ' is ' +
        region +
        college.toUpperCase() +
        '.';
    }
    if (e.Admission_Year__c != null) {
      String year = String.valueOf(e.Admission_Year__c.intValue()).right(2);
      if (usn.substring(3, 5) != year) {
        return 'The year in the USN is ' +
          usn.substring(3, 5) +
          ' but the student joined in 20' +
          year +
          '.';
      }
    }
    String branch = String.isNotBlank(e.Branch__r?.VTU_Branch_Code__c)
      ? e.Branch__r.VTU_Branch_Code__c
      : e.Branch__r?.Branch_Code__c;
    if (
      String.isNotBlank(branch) && usn.substring(5, 7) != branch.toUpperCase()
    ) {
      return 'The branch code in the USN is ' +
        usn.substring(5, 7) +
        ' but ' +
        e.Branch__r.Name +
        ' is ' +
        branch.toUpperCase() +
        '.';
    }
    return null;
  }

  private static String normalise(String value) {
    return value == null
      ? null
      : value.trim().toUpperCase().replaceAll('\\s', '');
  }

  /** One at a time. A change after the USN is set needs a System Administrator and a reason. */
  public static void setUsn(Id enrolmentId, String usnValue, String reason) {
    assertCanSet();
    String usn = normalise(usnValue);
    List<Programme_Enrolment__c> rows = load(
      'Id',
      new Set<String>{ enrolmentId }
    );
    if (rows.isEmpty()) {
      throw new AppException('Programme enrolment not found.');
    }
    Programme_Enrolment__c e = rows[0];
    if (e.USN__c == usn) {
      return;
    }
    if (String.isNotBlank(e.USN__c)) {
      if (!CollegeSetupController.canEdit()) {
        throw new AppException(
          'The USN is already set; only a System Administrator can change it.'
        );
      }
      if (String.isBlank(reason)) {
        throw new AppException('Enter the reason for changing the USN.');
      }
    }
    String why = problem(e, usn);
    if (why != null) {
      throw new AppException(why);
    }
    assertUnused(usn, e.Id);
    save(
      new List<Programme_Enrolment__c>{ e },
      new Map<Id, String>{ e.Id => usn }
    );
    if (String.isNotBlank(e.USN__c)) {
      Logger.info(
        'CollegeUsnService',
        'USN of ' +
          e.Roll_Number__c +
          ' changed from ' +
          e.USN__c +
          ' to ' +
          usn +
          ' by ' +
          UserInfo.getName() +
          ': ' +
          reason.trim()
      );
    }
  }

  private static void assertUnused(String usn, Id enrolmentId) {
    List<Programme_Enrolment__c> taken = [
      SELECT Roll_Number__c
      FROM Programme_Enrolment__c
      WHERE USN__c = :usn AND Id != :enrolmentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!taken.isEmpty()) {
      throw new AppException(
        usn + ' is already the USN of ' + taken[0].Roll_Number__c + '.'
      );
    }
  }

  private static void save(
    List<Programme_Enrolment__c> rows,
    Map<Id, String> usns
  ) {
    List<Programme_Enrolment__c> updates = new List<Programme_Enrolment__c>();
    for (Programme_Enrolment__c e : rows) {
      updates.add(
        new Programme_Enrolment__c(
          Id = e.Id,
          USN__c = usns.get(e.Id),
          USN_Set_By__c = UserInfo.getUserId(),
          USN_Set_On__c = System.now()
        )
      );
    }
    Database.update(updates, AccessLevel.SYSTEM_MODE);
  }

  /**
   * CSV with the columns Enrolment Number, USN (a header line is optional).
   * Every row is checked; with saveValid the valid rows are saved. A row that
   * would change an existing USN is refused here; use the one-at-a-time change.
   */
  public static UploadResult upload(String csv, Boolean saveValid) {
    assertCanSet();
    UploadResult result = new UploadResult();
    if (String.isBlank(csv)) {
      throw new AppException(
        'Choose a CSV file with Enrolment Number and USN.'
      );
    }
    List<String> lines = csv.replace('\r\n', '\n')
      .replace('\r', '\n')
      .split('\n');
    if (lines.size() > 2001) {
      throw new AppException('Upload at most 2,000 rows at a time.');
    }
    Set<String> numbers = new Set<String>();
    Set<String> usns = new Set<String>();
    List<RowResult> parsed = new List<RowResult>();
    for (Integer i = 0; i < lines.size(); i++) {
      String line = lines[i].trim();
      if (String.isBlank(line)) {
        continue;
      }
      List<String> cells = line.split(',');
      String first = cells[0].replace('"', '').trim();
      if (i == 0 && first.toLowerCase().contains('enrol')) {
        continue; // header
      }
      RowResult r = new RowResult();
      r.line = i + 1;
      r.enrolmentNumber = first.toUpperCase();
      r.usn = cells.size() > 1 ? normalise(cells[1].replace('"', '')) : null;
      parsed.add(r);
      numbers.add(r.enrolmentNumber);
      if (r.usn != null) {
        usns.add(r.usn);
      }
    }
    Map<String, Programme_Enrolment__c> byNumber = new Map<String, Programme_Enrolment__c>();
    for (Programme_Enrolment__c e : load('Roll_Number__c', numbers)) {
      byNumber.put(e.Roll_Number__c.toUpperCase(), e);
    }
    Map<String, String> usedBy = new Map<String, String>();
    for (Programme_Enrolment__c e : [
      SELECT Roll_Number__c, USN__c
      FROM Programme_Enrolment__c
      WHERE USN__c IN :usns
      WITH SYSTEM_MODE
    ]) {
      usedBy.put(e.USN__c.toUpperCase(), e.Roll_Number__c);
    }
    Set<String> seenNumbers = new Set<String>();
    Set<String> seenUsns = new Set<String>();
    List<Programme_Enrolment__c> toSave = new List<Programme_Enrolment__c>();
    Map<Id, String> values = new Map<Id, String>();
    for (RowResult r : parsed) {
      Programme_Enrolment__c e = byNumber.get(r.enrolmentNumber);
      r.student = e?.Student__r?.Name;
      if (e == null) {
        r.reason = 'No student has this enrolment number.';
      } else if (!seenNumbers.add(r.enrolmentNumber)) {
        r.reason = 'This enrolment number appears twice in the file.';
      } else if (r.usn != null && !seenUsns.add(r.usn)) {
        r.reason = 'This USN appears twice in the file.';
      } else if (String.isNotBlank(e.USN__c) && e.USN__c != r.usn) {
        r.reason =
          'Already has USN ' +
          e.USN__c +
          '; change it one at a time (System Administrator).';
      } else if (
        usedBy.containsKey(r.usn) && usedBy.get(r.usn) != e.Roll_Number__c
      ) {
        r.reason = r.usn + ' is already the USN of ' + usedBy.get(r.usn) + '.';
      } else {
        r.reason = problem(e, r.usn);
      }
      r.ok = r.reason == null;
      if (r.ok) {
        result.accepted++;
        if (e.USN__c != r.usn) {
          toSave.add(e);
          values.put(e.Id, r.usn);
        }
      } else {
        result.rejected++;
      }
      result.rows.add(r);
    }
    if (saveValid == true && !toSave.isEmpty()) {
      save(toSave, values);
      result.saved = true;
    }
    return result;
  }
}
