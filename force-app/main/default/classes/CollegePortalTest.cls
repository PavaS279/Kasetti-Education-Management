@IsTest
private class CollegePortalTest {
  @TestSetup
  static void setup() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(2, 7);
    System.runAs(fixture.dean) {
      MessageService.disabled = true;
      Id enrolmentId = CollegeTestFactory.enrolPaid(fixture, fixture.admission);
      CourseOffering section = new CourseOffering(
        Name = 'PORTAL Y1 A',
        RecordTypeId = Schema.SObjectType.CourseOffering.getRecordTypeInfosByDeveloperName()
          .get('College_Section')
          .getRecordTypeId(),
        LearningCourseId = fixture.branch.Id,
        Branch__c = fixture.campus.Id,
        Campus_Branch__c = fixture.intake.Id,
        Academic_Year__c = '2026-27',
        Year_Of_Study__c = 1,
        Section_Code__c = 'A',
        EnrollmentCapacity = 60,
        Class_Status__c = 'Open'
      );
      insert section;
      Subject__c subject = new Subject__c(
        Name = 'Engineering Mathematics I',
        Branch__c = fixture.branch.Id,
        Curriculum_Version__c = '2025',
        Subject_Code__c = 'MAT11',
        Year_Of_Study__c = 1,
        Term__c = 1,
        Credits__c = 4,
        Internal_Max__c = 50,
        Exam_Max__c = 100
      );
      insert subject;
      Section_Subject__c ss = new Section_Subject__c(
        Section__c = section.Id,
        Subject__c = subject.Id,
        Faculty__c = fixture.dean.Id
      );
      insert ss;
      Id sectionEnrolmentId = ProgressionService.join(
        enrolmentId,
        section.Id,
        Date.today()
      );
      Datetime start = Datetime.newInstance(
        Date.today(),
        Time.newInstance(9, 0, 0, 0)
      );
      Class_Session__c period = new Class_Session__c(
        Name = 'Maths today',
        Course_Offering__c = section.Id,
        Section_Subject__c = ss.Id,
        Teacher_User__c = fixture.dean.Id,
        Start__c = start,
        End__c = start.addHours(1)
      );
      insert period;
      insert new Session_Attendance__c(
        Class_Session__c = period.Id,
        Learner__c = fixture.admission.ContactId,
        Enrolment__c = sectionEnrolmentId,
        Status__c = 'Present',
        Unique_Key__c = period.Id + ':' + fixture.admission.ContactId
      );
      insert new DocumentChecklistItem(
        Name = 'Fitness certificate',
        ParentRecordId = fixture.admission.Id,
        Status = 'New'
      );
      List<Account> people = new List<Account>{
        PersonAccountService.buildPerson(
          'Parent',
          TestDataFactory.unique('Guardian'),
          null,
          null,
          fixture.campus.Id,
          'Guardian'
        ),
        PersonAccountService.buildPerson(
          'Other',
          TestDataFactory.unique('Stranger'),
          null,
          null,
          fixture.campus.Id,
          'Learner'
        )
      };
      insert people;
      GuardianRelationshipService.GuardianLink link = new GuardianRelationshipService.GuardianLink();
      link.guardianContactId = [
        SELECT PersonContactId
        FROM Account
        WHERE Id = :people[0].Id
      ]
      .PersonContactId;
      link.learnerContactId = fixture.admission.ContactId;
      link.relationship = 'Father';
      GuardianRelationshipService.link(
        new List<GuardianRelationshipService.GuardianLink>{ link }
      );
    }
  }

  private static Id student() {
    return [SELECT Student__r.PersonContactId FROM Programme_Enrolment__c]
    .Student__r.PersonContactId;
  }

  private static Id person(String firstName) {
    return [
      SELECT PersonContactId
      FROM Account
      WHERE FirstName = :firstName
      LIMIT 1
    ]
    .PersonContactId;
  }

  @IsTest
  static void studentSeesOwnCollegeCardWithoutDraftMarks() {
    Id me = student();
    PortalService.viewerOverride = me;
    Test.startTest();
    PortalService.LearnerDetail detail = PortalController.getLearner(me);
    Test.stopTest();
    CollegePortalService.Summary college = detail.college;
    System.assertNotEquals(null, college);
    System.assertEquals(
      [SELECT Roll_Number__c FROM Programme_Enrolment__c].Roll_Number__c,
      college.rollNumber
    );
    System.assertEquals('Enrolled', college.status);
    System.assertEquals('PORTAL Y1 A', college.section);
    System.assertEquals(1, college.today.size());
    System.assertEquals('Engineering Mathematics I', college.today[0].subject);
    System.assertEquals(1, college.subjects.size());
    System.assertEquals(100, college.subjects[0].attendancePercent);
    System.assertEquals(
      false,
      college.subjects[0].published,
      'Draft marks stay hidden'
    );
    System.assertEquals(null, college.subjects[0].total);
    System.assertEquals(0, college.feesDue, 'The annual fee was paid online');
    Boolean labelled = false;
    for (PortalService.InvoiceItem invoice : detail.invoices) {
      labelled |=
        invoice.className != null && invoice.className.contains('year 1');
    }
    System.assert(
      labelled,
      'Programme invoices are labelled with programme, branch and year'
    );
  }

  @IsTest
  static void finalResultsArePublished() {
    Subject_Result__c r = [
      SELECT Id, Section_Enrolment__c
      FROM Subject_Result__c
    ];
    update new Subject_Result__c(
      Id = r.Id,
      Internal_Marks__c = 40,
      Exam_Marks__c = 80,
      Total_Marks__c = 120,
      Max_Marks__c = 150,
      Result__c = 'Pass',
      Status__c = 'Final'
    );
    insert new Term_Result__c(
      Unique_Key__c = ResultService.termKey(r.Section_Enrolment__c, 1),
      Section_Enrolment__c = r.Section_Enrolment__c,
      Programme_Enrolment__c = [SELECT Id FROM Programme_Enrolment__c]
      .Id,
      Term__c = 1,
      Status__c = 'Final',
      Outcome__c = 'Pass',
      Percentage__c = 80,
      Backlogs__c = 0
    );
    Id me = student();
    PortalService.viewerOverride = me;
    Test.startTest();
    CollegePortalService.Summary college = PortalService.learner(me).college;
    Test.stopTest();
    System.assert(college.subjects[0].published);
    System.assertEquals(120, college.subjects[0].total);
    System.assertEquals('Pass', college.subjects[0].result);
    System.assertEquals(1, college.terms.size());
    System.assertEquals(0, college.openBacklogs);
  }

  @IsTest
  static void parentSeesTheChildUntilTheLinkEnds() {
    Id child = student();
    PortalService.viewerOverride = person('Parent');
    Test.startTest();
    System.assertNotEquals(null, PortalService.learner(child).college);
    update new ContactContactRelation(
      Id = [
        SELECT Id
        FROM ContactContactRelation
        WHERE RelatedContactId = :child
        LIMIT 1
      ]
      .Id,
      IsActive = false
    );
    try {
      PortalService.learner(child);
      System.assert(false, 'Access ends with the guardian link');
    } catch (AppException expected) {
      System.assert(expected.getMessage().contains('access'));
    }
    Test.stopTest();
  }

  @IsTest
  static void otherFamiliesAreRefused() {
    Id child = student();
    Id stranger = person('Other');
    PortalService.viewerOverride = stranger;
    Test.startTest();
    try {
      PortalService.learner(child);
      System.assert(false, 'Another family cannot see this student');
    } catch (AppException expected) {
      System.assert(expected.getMessage().contains('access'));
    }
    Id itemId = [SELECT Id FROM DocumentChecklistItem LIMIT 1].Id;
    String file = EncodingUtil.base64Encode(Blob.valueOf('certificate'));
    try {
      PortalService.uploadAdmissionDocument(itemId, 'fitness.pdf', file);
      System.assert(false, 'Another family cannot upload to this admission');
    } catch (AppException expected) {
      System.assert(expected.getMessage().contains('not available'));
    }
    System.assertEquals(
      null,
      PortalService.learner(stranger).college,
      'Not a college student'
    );
    Test.stopTest();
  }

  @IsTest
  static void studentUploadsAnAdmissionDocument() {
    PortalService.viewerOverride = student();
    Id itemId = [SELECT Id FROM DocumentChecklistItem LIMIT 1].Id;
    Test.startTest();
    Id versionId = PortalService.uploadAdmissionDocument(
      itemId,
      'fitness.pdf',
      EncodingUtil.base64Encode(Blob.valueOf('certificate'))
    );
    Test.stopTest();
    System.assertNotEquals(null, versionId);
  }
}
