/**
 * Admission desk: creates a college admission from what the student brings to
 * the desk (person, campus branch, route, marks and entrance rank). The marks
 * and ranks are recorded as verified by the desk user who has seen the marks
 * card, so the eligibility verdict is immediate; the AI document reader and the
 * document checklist confirm them before the Dean's interview.
 *
 * A student already on file (same email, or same mobile and last name) is
 * reused rather than duplicated, so an online enquirer who later walks in, or
 * a converted enquiry, keeps one student record.
 *
 * Writes run in system mode after the explicit create check below: the
 * qualification, score and guardian records are desk-controlled evidence that
 * staff must not be able to edit directly (docs/03-security-model.md).
 */
public with sharing class CollegeAdmissionService {
  public static Id create(CollegeAdmissionController.NewAdmission request) {
    return create(request, null);
  }

  /**
   * Creates the admission for an existing student when existingStudentId is
   * given (enquiry conversion), otherwise for a matching or new student.
   */
  public static Id create(
    CollegeAdmissionController.NewAdmission request,
    Id existingStudentId
  ) {
    if (!Schema.SObjectType.IndividualApplication.isCreateable()) {
      throw new AppException(
        'You do not have permission to create admissions.'
      );
    }
    if (
      request == null ||
      String.isBlank(request.lastName) ||
      request.campusBranchId == null ||
      String.isBlank(request.entryRoute)
    ) {
      throw new AppException(
        'Enter the student name, the campus branch and the entry route.'
      );
    }
    if (request.qualifications == null || request.qualifications.isEmpty()) {
      throw new AppException(
        'Enter at least one qualification (for example the SSLC result).'
      );
    }
    // A converted enquiry reuses the student already on file.
    if (existingStudentId == null) {
      InputValidator.name(request.firstName, 'Student first name');
      InputValidator.name(request.lastName, 'Student last name');
      InputValidator.name(request.guardianFirstName, 'Guardian first name');
      InputValidator.name(request.guardianLastName, 'Guardian last name');
      InputValidator.email(request.email, 'Student email');
      InputValidator.phone(request.phone, 'Student mobile');
      InputValidator.phone(request.guardianPhone, 'Guardian phone');
      InputValidator.birthdate(request.birthdate, 14, 'student date of birth');
    }
    // Rows the desk left empty are ignored; the rest obey the public rules.
    List<CollegeAdmissionController.Qualification> filled = new List<CollegeAdmissionController.Qualification>();
    for (CollegeAdmissionController.Qualification q : request.qualifications) {
      if (q != null && (String.isNotBlank(q.level) || q.percentage != null)) {
        filled.add(q);
      }
    }
    List<CollegeAdmissionController.Entrance> filledRanks = new List<CollegeAdmissionController.Entrance>();
    for (
      CollegeAdmissionController.Entrance e : request.entrances == null
        ? new List<CollegeAdmissionController.Entrance>()
        : request.entrances
    ) {
      if (e != null && (String.isNotBlank(e.exam) || e.rank != null)) {
        filledRanks.add(e);
      }
    }
    if (filled.isEmpty()) {
      throw new AppException(
        'Enter at least one qualification (for example the SSLC result).'
      );
    }
    CollegePublicController.validateMarks(filled, filledRanks);
    request.qualifications = filled;
    request.entrances = filledRanks;
    Campus_Branch__c intake = [
      SELECT
        Id,
        Admissions_Open__c,
        Academic_Year__c,
        Campus__c,
        Branch__c,
        Branch__r.Programme__c
      FROM Campus_Branch__c
      WHERE Id = :request.campusBranchId
      WITH USER_MODE
    ];
    if (!intake.Admissions_Open__c) {
      throw new AppException('Admissions are closed for this campus branch.');
    }
    Savepoint checkpoint = Database.setSavepoint();
    try {
      Account student = resolveStudent(request, existingStudentId, intake);
      assertNoOpenAdmission(student.Id, intake.Id);

      List<Academic_Qualification__c> qualifications = new List<Academic_Qualification__c>();
      for (
        CollegeAdmissionController.Qualification q : request.qualifications
      ) {
        qualifications.add(
          new Academic_Qualification__c(
            Student__c = student.Id,
            Level__c = q.level,
            Stream_Group__c = String.isBlank(q.stream) ? null : q.stream,
            Branch_Code__c = String.isBlank(q.branchCode)
              ? null
              : q.branchCode.toUpperCase(),
            Percentage__c = q.percentage,
            Completion_Year__c = q.year == null ? Date.today().year() : q.year,
            Verified__c = true,
            Verified_By__c = UserInfo.getUserId(),
            Verified_On__c = System.now()
          )
        );
      }
      Database.insert(qualifications, AccessLevel.SYSTEM_MODE);
      List<Entrance_Score__c> scores = new List<Entrance_Score__c>();
      for (
        CollegeAdmissionController.Entrance e : request.entrances == null
          ? new List<CollegeAdmissionController.Entrance>()
          : request.entrances
      ) {
        if (String.isBlank(e.exam) || e.rank == null) {
          continue;
        }
        scores.add(
          new Entrance_Score__c(
            Student__c = student.Id,
            Exam__c = e.exam,
            Rank__c = e.rank,
            Exam_Year__c = e.year == null ? Date.today().year() : e.year,
            Verified__c = true,
            Verified_By__c = UserInfo.getUserId(),
            Verified_On__c = System.now()
          )
        );
      }
      Database.insert(scores, AccessLevel.SYSTEM_MODE);

      if (String.isNotBlank(request.guardianLastName)) {
        Account guardian = PersonAccountService.buildPerson(
          request.guardianFirstName,
          request.guardianLastName,
          null,
          request.guardianPhone,
          intake.Campus__c,
          'Guardian'
        );
        Database.insert(guardian, AccessLevel.SYSTEM_MODE);
        GuardianRelationshipService.GuardianLink link = new GuardianRelationshipService.GuardianLink();
        link.guardianContactId = [
          SELECT PersonContactId
          FROM Account
          WHERE Id = :guardian.Id
          WITH SYSTEM_MODE
        ]
        .PersonContactId;
        link.learnerContactId = student.PersonContactId;
        link.relationship = 'Guardian';
        // Parent portal access is optional and granted later with Give portal access.
        link.portalAccess = false;
        GuardianRelationshipService.link(
          new List<GuardianRelationshipService.GuardianLink>{ link }
        );
      }

      IndividualApplication admission = new IndividualApplication(
        Category = 'Education',
        AccountId = student.Id,
        ContactId = student.PersonContactId,
        Status = 'Processing',
        Branch__c = intake.Campus__c,
        Learning_Course__c = intake.Branch__c,
        Learning_Program__c = intake.Branch__r.Programme__c,
        Campus_Branch__c = intake.Id,
        College_Mode__c = true,
        College_Stage__c = 'Processing',
        Academic_Year__c = intake.Academic_Year__c,
        Entry_Route__c = request.entryRoute,
        Entry_Year_Of_Study__c = request.entryRoute == 'Lateral' ? 2 : 1
      );
      Database.insert(admission, AccessLevel.SYSTEM_MODE);
      if (request.consent == true) {
        CollegeDocumentService.captureConsent(admission.Id);
      }
      return admission.Id;
    } catch (Exception failure) {
      Database.rollback(checkpoint);
      throw failure;
    }
  }

  private static Account resolveStudent(
    CollegeAdmissionController.NewAdmission request,
    Id existingStudentId,
    Campus_Branch__c intake
  ) {
    Id studentId = existingStudentId;
    if (studentId == null) {
      Account match = PersonAccountService.findPerson(
        request.email,
        request.phone,
        request.lastName
      );
      studentId = match == null ? null : match.Id;
    }
    if (studentId != null) {
      Account existing = PersonAccountService.reload(new Set<Id>{ studentId })
        .get(studentId);
      if (existing == null || existing.PersonContactId == null) {
        throw new AppException(
          'The selected student is not a person account you can access.'
        );
      }
      String role = PersonAccountService.mergeRole(
        existing.KEM_Role__c,
        'Learner'
      );
      if (role != existing.KEM_Role__c) {
        Database.update(
          new Account(Id = existing.Id, KEM_Role__c = role),
          AccessLevel.SYSTEM_MODE
        );
      }
      return existing;
    }
    Account student = PersonAccountService.buildPerson(
      request.firstName,
      request.lastName,
      request.email,
      request.phone,
      intake.Campus__c,
      'Learner'
    );
    student.PersonBirthdate = request.birthdate;
    Database.insert(student, AccessLevel.SYSTEM_MODE);
    return [
      SELECT Id, PersonContactId
      FROM Account
      WHERE Id = :student.Id
      WITH SYSTEM_MODE
    ];
  }

  /** One live admission per student and intake; closed ones do not count. */
  private static void assertNoOpenAdmission(Id studentId, Id intakeId) {
    Integer open = [
      SELECT COUNT()
      FROM IndividualApplication
      WHERE
        AccountId = :studentId
        AND Campus_Branch__c = :intakeId
        AND College_Stage__c NOT IN (
          'Application Decision',
          'Enrollment Failed',
          'Withdrawn'
        )
      WITH SYSTEM_MODE
    ];
    if (open > 0) {
      throw new AppException(
        'This student already has an open admission for this programme.'
      );
    }
  }
}
