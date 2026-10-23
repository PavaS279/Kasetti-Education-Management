/**
 * Admission desk: creates a college admission from what the student brings to
 * the desk (person, campus branch, route, marks and entrance rank). The marks
 * and ranks are recorded as verified by the desk user who has seen the marks
 * card, so the eligibility verdict is immediate; the AI document reader and the
 * document checklist confirm them before the Dean's interview.
 */
public with sharing class CollegeAdmissionService {
  public static Id create(CollegeAdmissionController.NewAdmission request) {
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
      student = [
        SELECT Id, PersonContactId
        FROM Account
        WHERE Id = :student.Id
        WITH SYSTEM_MODE
      ];

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
}
