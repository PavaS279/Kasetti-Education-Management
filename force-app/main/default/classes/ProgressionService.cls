/**
 * College academic progression owned by the Dean: joining a section, year-end
 * promotion, repeating a year, discontinuing and completing a programme.
 * Every operation locks the programme enrolment and is idempotent through the
 * unique programme-year key on section enrolments and the source key on the
 * qualification earned.
 */
public without sharing class ProgressionService {
  public static final String DEAN_PERMISSION = CollegeProvisionalService.DEAN_PERMISSION;

  // ------------------------------------------------------------ joining

  /** Joins an enrolled student to a college section of their campus, branch and year of study. Returns the section enrolment. */
  public static Id join(
    Id programmeEnrolmentId,
    Id sectionId,
    Date joiningDate
  ) {
    RecordAccess.assertPermission(DEAN_PERMISSION);
    Programme_Enrolment__c enrolment = lock(programmeEnrolmentId);
    if (enrolment.Status__c != 'Enrolled') {
      throw new AppException(
        'Only an enrolled student with a roll number can join a section.'
      );
    }
    if (joiningDate == null) {
      throw new AppException('Enter the joining date.');
    }
    Id sectionEnrolmentId = enrol(
      enrolment,
      sectionId,
      enrolment.Current_Year_Of_Study__c.intValue()
    );
    if (enrolment.Joining_Date__c == null) {
      Database.update(
        new Programme_Enrolment__c(
          Id = enrolment.Id,
          Joining_Date__c = joiningDate
        ),
        AccessLevel.SYSTEM_MODE
      );
    }
    return sectionEnrolmentId;
  }

  /** Sections a programme enrolment can join for its current (or next) year of study. */
  public static List<CourseOffering> eligibleSections(
    Id programmeEnrolmentId,
    Integer yearOfStudy
  ) {
    Programme_Enrolment__c enrolment = [
      SELECT Id, Campus__c, Branch__c, Current_Year_Of_Study__c
      FROM Programme_Enrolment__c
      WHERE Id = :programmeEnrolmentId
      WITH USER_MODE
    ];
    Integer year = yearOfStudy == null
      ? enrolment.Current_Year_Of_Study__c.intValue()
      : yearOfStudy;
    return [
      SELECT
        Id,
        Name,
        Section_Code__c,
        Academic_Year__c,
        Year_Of_Study__c,
        EnrollmentCapacity,
        Seats_Taken__c
      FROM CourseOffering
      WHERE
        RecordType.DeveloperName = 'College_Section'
        AND Campus_Branch__r.Campus__c = :enrolment.Campus__c
        AND Campus_Branch__r.Branch__c = :enrolment.Branch__c
        AND Year_Of_Study__c = :year
        AND Class_Status__c NOT IN ('Cancelled', 'Completed')
      WITH SYSTEM_MODE
      ORDER BY Academic_Year__c DESC, Section_Code__c
      LIMIT 50
    ];
  }

  private static Id enrol(
    Programme_Enrolment__c enrolment,
    Id sectionId,
    Integer yearOfStudy
  ) {
    CourseOffering section = [
      SELECT
        Id,
        RecordType.DeveloperName,
        Branch__c,
        Academic_Year__c,
        Year_Of_Study__c,
        EnrollmentCapacity,
        Seats_Taken__c,
        StartDate,
        EndDate,
        Class_Status__c,
        Campus_Branch__r.Campus__c,
        Campus_Branch__r.Branch__c
      FROM CourseOffering
      WHERE Id = :sectionId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    String key = programmeYearKey(enrolment.Id, section.Academic_Year__c);
    List<CourseOfferingParticipant> existing = [
      SELECT Id, CourseOfferingId
      FROM CourseOfferingParticipant
      WHERE Programme_Year_Key__c = :key
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      if (existing[0].CourseOfferingId != sectionId) {
        throw new AppException(
          'The student is already in another section for ' +
            section.Academic_Year__c +
            '.'
        );
      }
      return existing[0].Id;
    }
    if (
      section.RecordType.DeveloperName != 'College_Section' ||
      section.Campus_Branch__r.Campus__c != enrolment.Campus__c ||
      section.Campus_Branch__r.Branch__c != enrolment.Branch__c ||
      section.Year_Of_Study__c != yearOfStudy
    ) {
      throw new AppException(
        'Choose a section of the same campus and branch for year ' +
          yearOfStudy +
          '.'
      );
    }
    if (
      section.Class_Status__c == 'Cancelled' ||
      section.Class_Status__c == 'Completed'
    ) {
      throw new AppException('This section is closed.');
    }
    if (
      section.EnrollmentCapacity != null &&
      nvl(section.Seats_Taken__c) >= section.EnrollmentCapacity
    ) {
      throw new AppException('This section is full; choose another section.');
    }
    CourseOfferingParticipant row = new CourseOfferingParticipant(
      CourseOfferingId = section.Id,
      ParticipantContactId = enrolment.Student__r.PersonContactId,
      ParticipantAccountId = enrolment.Student__c,
      ParticipantAffiliation = 'Student',
      ParticipationStatus = 'Enrolled',
      RegistrationDateTime = System.now(),
      StartDate = section.StartDate == null
        ? Date.today()
        : section.StartDate.date(),
      EndDate = section.EndDate == null ? null : section.EndDate.date(),
      Branch__c = section.Branch__c,
      Application__c = enrolment.Application__c,
      Programme_Enrolment__c = enrolment.Id,
      Academic_Year__c = section.Academic_Year__c,
      Year_Of_Study__c = yearOfStudy,
      Programme_Year_Key__c = key,
      Billing_Status__c = 'Not Invoiced'
    );
    Database.insert(row, AccessLevel.SYSTEM_MODE);
    ResultService.ensureResults(new Set<Id>{ row.Id });
    return row.Id;
  }

  // ------------------------------------------------------------ year end

  /** Promotes to the next year of study when this year's term results are final and backlogs are within the programme limit. */
  public static Id promote(Id programmeEnrolmentId, Id nextSectionId) {
    RecordAccess.assertPermission(DEAN_PERMISSION);
    Programme_Enrolment__c enrolment = lock(programmeEnrolmentId);
    CourseOffering target = [
      SELECT Academic_Year__c
      FROM CourseOffering
      WHERE Id = :nextSectionId
      WITH SYSTEM_MODE
    ];
    List<CourseOfferingParticipant> done = [
      SELECT Id, CourseOfferingId
      FROM CourseOfferingParticipant
      WHERE
        Programme_Year_Key__c = :programmeYearKey(
          enrolment.Id,
          target.Academic_Year__c
        )
      WITH SYSTEM_MODE
    ];
    if (!done.isEmpty() && done[0].CourseOfferingId == nextSectionId) {
      return done[0].Id; // already promoted into this section
    }
    Integer year = enrolment.Current_Year_Of_Study__c.intValue();
    CourseOfferingParticipant current = currentSection(enrolment.Id);
    assertYearFinal(enrolment, current, year);
    if (year >= enrolment.Programme__r.Duration_Years__c) {
      throw new AppException(
        'This is the final year; complete the programme instead.'
      );
    }
    List<Subject_Result__c> backlogs = ResultService.openBacklogs(enrolment.Id);
    if (
      backlogs.size() >
      nvl(enrolment.Programme__r.Max_Backlogs_For_Promotion__c)
    ) {
      throw new AppException(
        backlogs.size() +
          ' backlogs exceed the limit of ' +
          nvl(enrolment.Programme__r.Max_Backlogs_For_Promotion__c).intValue() +
          ' for promotion; the student repeats the year.'
      );
    }
    Id next = enrol(enrolment, nextSectionId, year + 1);
    for (Subject_Result__c backlog : backlogs) {
      ResultService.registerReattempt(backlog.Id, next);
    }
    complete(current);
    Database.update(
      new Programme_Enrolment__c(
        Id = enrolment.Id,
        Current_Year_Of_Study__c = year + 1
      ),
      AccessLevel.SYSTEM_MODE
    );
    BillingService.createProgrammeInvoiceSystem(
      enrolment.Id,
      year + 1,
      'Annual'
    );
    return next;
  }

  /** The student repeats the current year in a section of the next academic year. */
  public static Id repeatYear(
    Id programmeEnrolmentId,
    Id sectionId,
    String reason
  ) {
    RecordAccess.assertPermission(DEAN_PERMISSION);
    if (String.isBlank(reason)) {
      throw new AppException('Enter the reason for repeating the year.');
    }
    Programme_Enrolment__c enrolment = lock(programmeEnrolmentId);
    Integer year = enrolment.Current_Year_Of_Study__c.intValue();
    CourseOfferingParticipant current = currentSection(enrolment.Id);
    CourseOffering target = [
      SELECT Academic_Year__c
      FROM CourseOffering
      WHERE Id = :sectionId
      WITH SYSTEM_MODE
    ];
    if (
      current != null &&
      current.Academic_Year__c == target.Academic_Year__c
    ) {
      if (current.CourseOfferingId == sectionId) {
        return current.Id; // already repeating here
      }
      throw new AppException(
        'Choose a section of the next academic year to repeat the year.'
      );
    }
    assertYearFinal(enrolment, current, year);
    Id next = enrol(enrolment, sectionId, year);
    complete(current);
    Database.update(
      new Programme_Enrolment__c(
        Id = enrolment.Id,
        Status_Reason__c = ('Repeating year ' +
          year +
          ': ' +
          reason.trim())
          .left(255)
      ),
      AccessLevel.SYSTEM_MODE
    );
    return next;
  }

  /** Dean discontinues an enrolled student; the active section enrolment is withdrawn and the roll number kept. */
  public static void discontinue(Id programmeEnrolmentId, String reason) {
    RecordAccess.assertPermission(DEAN_PERMISSION);
    if (String.isBlank(reason)) {
      throw new AppException('Enter the reason for discontinuing.');
    }
    Programme_Enrolment__c enrolment = lock(programmeEnrolmentId);
    if (enrolment.Status__c == 'Discontinued') {
      return;
    }
    if (enrolment.Status__c != 'Enrolled') {
      throw new AppException('Only an enrolled student can be discontinued.');
    }
    for (CourseOfferingParticipant active : [
      SELECT Id
      FROM CourseOfferingParticipant
      WHERE
        Programme_Enrolment__c = :enrolment.Id
        AND ParticipationStatus = 'Enrolled'
      WITH SYSTEM_MODE
    ]) {
      Database.update(
        new CourseOfferingParticipant(
          Id = active.Id,
          ParticipationStatus = 'Withdrew',
          DroppedDateTime = System.now(),
          EndDate = Date.today(),
          Withdrawal_Reason__c = reason.trim().left(255)
        ),
        AccessLevel.SYSTEM_MODE
      );
    }
    Database.update(
      new Programme_Enrolment__c(
        Id = enrolment.Id,
        Status__c = 'Discontinued',
        Status_Reason__c = reason.trim().left(255)
      ),
      AccessLevel.SYSTEM_MODE
    );
  }

  /** Completes the programme after the final year with no open backlogs and records the qualification once. */
  public static Id completeProgramme(Id programmeEnrolmentId) {
    RecordAccess.assertPermission(DEAN_PERMISSION);
    Programme_Enrolment__c enrolment = lock(programmeEnrolmentId);
    List<Academic_Qualification__c> earned = [
      SELECT Id
      FROM Academic_Qualification__c
      WHERE Source_Key__c = :String.valueOf(enrolment.Id)
      WITH SYSTEM_MODE
    ];
    if (enrolment.Status__c == 'Completed' && !earned.isEmpty()) {
      return earned[0].Id;
    }
    if (enrolment.Status__c != 'Enrolled') {
      throw new AppException(
        'Only an enrolled student can complete the programme.'
      );
    }
    Integer year = enrolment.Current_Year_Of_Study__c.intValue();
    if (year < enrolment.Programme__r.Duration_Years__c) {
      throw new AppException(
        'The student is in year ' +
          year +
          ' of ' +
          enrolment.Programme__r.Duration_Years__c.intValue() +
          '.'
      );
    }
    CourseOfferingParticipant current = currentSection(enrolment.Id);
    assertYearFinal(enrolment, current, year);
    List<Subject_Result__c> backlogs = ResultService.openBacklogs(enrolment.Id);
    if (!backlogs.isEmpty()) {
      throw new AppException(
        backlogs.size() + ' backlogs must be cleared before completion.'
      );
    }
    // Programme percentage: the passing (latest) attempt of every subject studied at KT.
    Map<Id, Subject_Result__c> latest = new Map<Id, Subject_Result__c>();
    for (Subject_Result__c r : [
      SELECT Section_Subject__c, Total_Marks__c, Max_Marks__c, Attempt__c
      FROM Subject_Result__c
      WHERE Programme_Enrolment__c = :enrolment.Id AND Status__c = 'Final'
      WITH SYSTEM_MODE
      ORDER BY Attempt__c ASC
    ]) {
      latest.put(r.Section_Subject__c, r);
    }
    Decimal total = 0;
    Decimal max = 0;
    for (Subject_Result__c r : latest.values()) {
      total += nvl(r.Total_Marks__c);
      max += nvl(r.Max_Marks__c);
    }
    complete(current);
    Database.update(
      new Programme_Enrolment__c(Id = enrolment.Id, Status__c = 'Completed'),
      AccessLevel.SYSTEM_MODE
    );
    if (!earned.isEmpty()) {
      return earned[0].Id;
    }
    Academic_Qualification__c qualification = new Academic_Qualification__c(
      Student__c = enrolment.Student__c,
      Level__c = enrolment.Programme__r.Qualification_Level__c,
      Stream_Group__c = enrolment.Branch__r.Stream_Group__c,
      Branch_Code__c = enrolment.Branch__r.Branch_Code__c,
      Percentage__c = max == 0 ? 0 : (total * 100 / max).setScale(2),
      Completion_Year__c = Date.today().year(),
      Verified__c = true,
      Verified_By__c = UserInfo.getUserId(),
      Verified_On__c = System.now(),
      Source_Programme_Enrolment__c = enrolment.Id,
      Source_Key__c = String.valueOf(enrolment.Id)
    );
    Database.insert(qualification, AccessLevel.SYSTEM_MODE);
    return qualification.Id;
  }

  // ------------------------------------------------------------ helpers

  private static void assertYearFinal(
    Programme_Enrolment__c enrolment,
    CourseOfferingParticipant current,
    Integer year
  ) {
    if (enrolment.Status__c != 'Enrolled') {
      throw new AppException('Only an enrolled student can progress.');
    }
    if (current == null) {
      throw new AppException('Join the student to a section first.');
    }
    Integer perYear = enrolment.Programme__r.Terms_Per_Year__c == null
      ? 1
      : enrolment.Programme__r.Terms_Per_Year__c.intValue();
    Set<Integer> terms = new Set<Integer>();
    for (Integer t = (year - 1) * perYear + 1; t <= year * perYear; t++) {
      terms.add(t);
    }
    Integer finalTerms = 0;
    for (Term_Result__c t : [
      SELECT Term__c
      FROM Term_Result__c
      WHERE Section_Enrolment__c = :current.Id AND Status__c = 'Final'
      WITH SYSTEM_MODE
    ]) {
      if (terms.contains(t.Term__c.intValue())) {
        finalTerms++;
      }
    }
    if (finalTerms < terms.size()) {
      throw new AppException(
        'Finalise the results of every term of year ' + year + ' first.'
      );
    }
  }

  private static CourseOfferingParticipant currentSection(
    Id programmeEnrolmentId
  ) {
    List<CourseOfferingParticipant> rows = [
      SELECT
        Id,
        CourseOfferingId,
        Year_Of_Study__c,
        Academic_Year__c,
        ParticipationStatus
      FROM CourseOfferingParticipant
      WHERE Programme_Enrolment__c = :programmeEnrolmentId
      WITH SYSTEM_MODE
      ORDER BY Academic_Year__c DESC, Year_Of_Study__c DESC
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  private static void complete(CourseOfferingParticipant current) {
    if (current != null && current.ParticipationStatus == 'Enrolled') {
      Database.update(
        new CourseOfferingParticipant(
          Id = current.Id,
          ParticipationStatus = 'Completed',
          EndDate = Date.today()
        ),
        AccessLevel.SYSTEM_MODE
      );
    }
  }

  private static Programme_Enrolment__c lock(Id programmeEnrolmentId) {
    return [
      SELECT
        Id,
        Status__c,
        Student__c,
        Student__r.PersonContactId,
        Campus__c,
        Branch__c,
        Application__c,
        Current_Year_Of_Study__c,
        Joining_Date__c,
        Programme__r.Duration_Years__c,
        Programme__r.Terms_Per_Year__c,
        Programme__r.Max_Backlogs_For_Promotion__c,
        Programme__r.Qualification_Level__c,
        Branch__r.Stream_Group__c,
        Branch__r.Branch_Code__c
      FROM Programme_Enrolment__c
      WHERE Id = :programmeEnrolmentId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
  }

  public static String programmeYearKey(
    Id programmeEnrolmentId,
    String academicYear
  ) {
    return programmeEnrolmentId + '|' + academicYear;
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }
}
