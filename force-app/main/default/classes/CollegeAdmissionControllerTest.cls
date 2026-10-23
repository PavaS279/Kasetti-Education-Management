@IsTest
private class CollegeAdmissionControllerTest {
  private static Id activeRule(Id branchId, Decimal minimum) {
    Admission_Rule__c rule = new Admission_Rule__c(
      Branch__c = branchId,
      Academic_Year__c = '2026-27',
      Entry_Route__c = 'Regular',
      Status__c = 'Draft',
      Entry_Year_Of_Study__c = 1,
      Qualifying_Level__c = 'SSLC',
      Min_Percentage__c = minimum,
      Entrance_Required__c = false,
      Interview_Required__c = true
    );
    insert rule;
    AdmissionRuleService.activate(rule.Id);
    return rule.Id;
  }

  private static CollegeAdmissionController.NewAdmission request(
    Id intakeId,
    Decimal percentage
  ) {
    CollegeAdmissionController.NewAdmission r = new CollegeAdmissionController.NewAdmission();
    r.firstName = 'Desk';
    r.lastName = TestDataFactory.unique('Applicant');
    r.campusBranchId = intakeId;
    r.entryRoute = 'Regular';
    CollegeAdmissionController.Qualification q = new CollegeAdmissionController.Qualification();
    q.level = 'SSLC';
    q.percentage = percentage;
    q.year = 2025;
    r.qualifications = new List<CollegeAdmissionController.Qualification>{ q };
    r.entrances = new List<CollegeAdmissionController.Entrance>();
    r.guardianFirstName = 'Desk';
    r.guardianLastName = TestDataFactory.unique('Parent');
    r.consent = false;
    return r;
  }

  @IsTest
  static void deskCreatesAdmissionsDeanInterviewsAndAdmits() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(2, 7);
    System.runAs(fixture.dean) {
      MessageService.disabled = true;
      CollegeDocumentService.suppressStatusUpdates = true;
      activeRule(fixture.branch.Id, 60);
      insert new List<Admission_Document_Rule__c>{
        new Admission_Document_Rule__c(
          Academic_Year__c = '2026-27',
          Document_Type__c = 'Aadhaar',
          Label__c = 'Aadhaar card',
          Required__c = false,
          Sensitive_Class__c = 'Identity',
          Retain_File__c = false,
          Active__c = true
        ),
        new Admission_Document_Rule__c(
          Academic_Year__c = '2026-27',
          Document_Type__c = 'SSLC_Marks',
          Label__c = 'SSLC marks card',
          Required__c = false,
          Sensitive_Class__c = 'Academic',
          Retain_File__c = true,
          Retention_Days__c = 365,
          Active__c = true
        )
      };
      Test.startTest();
      System.assertEquals(1, CollegeAdmissionController.getIntakes().size());
      CollegeAdmissionController.Admission a = CollegeAdmissionController.createAdmission(
        request(fixture.intake.Id, 72)
      );
      System.assertEquals('Eligible', a.eligibility);
      System.assertEquals('Processing', a.stage);
      System.assertEquals(2, a.items.size());
      System.assert(a.canDesk && a.canDean);
      try {
        CollegeAdmissionController.verifyDocument(a.id, a.items[0].id, null);
        System.assert(false, 'Consent comes first');
      } catch (AuraHandledException expected) {
        System.assert(true);
      }
      a = CollegeAdmissionController.captureConsent(a.id);
      System.assert(a.consent);
      Id aadhaar;
      for (CollegeAdmissionController.Item item : a.items) {
        if (item.sensitiveClass == 'Identity') {
          aadhaar = item.id;
        }
      }
      try {
        CollegeAdmissionController.verifyDocument(a.id, aadhaar, '12');
        System.assert(false, 'Only the last four digits');
      } catch (AuraHandledException expected) {
        System.assert(true);
      }
      a = CollegeAdmissionController.verifyDocument(a.id, aadhaar, '4321');
      a = CollegeAdmissionController.markDocumentsVerified(a.id);
      System.assertEquals('Documents Verified', a.stage);
      a = CollegeAdmissionController.scheduleInterview(
        a.id,
        System.now().addMinutes(-5)
      );
      System.assertEquals('Interview Scheduled', a.stage);
      a = CollegeAdmissionController.recordOutcome(a.id, 'Pass', 'Confident');
      System.assertEquals('Ready For Decision', a.stage);
      a = CollegeAdmissionController.admit(a.id);
      Test.stopTest();
      System.assertEquals('Fee Pending', a.stage);
      System.assertNotEquals(null, a.programmeEnrolmentId);
      System.assertEquals('Provisional', a.enrolmentStatus);
      System.assertEquals(
        '4321',
        [SELECT Last4__c FROM DocumentChecklistItem WHERE Id = :aadhaar]
        .Last4__c
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContactContactRelation
          WHERE
            RelatedContactId IN (
              SELECT ContactId
              FROM IndividualApplication
              WHERE Id = :a.id
            )
        ],
        'Optional parent linked without portal access'
      );
    }
  }

  @IsTest
  static void refusedApplicantSeesSuggestionsAndTheDeanRejects() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(2, 7);
    System.runAs(fixture.dean) {
      MessageService.disabled = true;
      activeRule(fixture.branch.Id, 90);
      Learning other = new Learning(
        Name = TestDataFactory.unique('Other'),
        Type = 'LearningCourse',
        IsActive = true
      );
      insert other;
      LearningCourse civil = new LearningCourse(
        Name = 'BE Civil',
        LearningId = other.Id,
        RecordTypeId = Schema.SObjectType.LearningCourse.getRecordTypeInfosByDeveloperName()
          .get('College_Branch')
          .getRecordTypeId(),
        External_ID__c = TestDataFactory.unique('CIVIL'),
        Programme__c = fixture.programme.Id,
        Branch_Code__c = 'CV',
        Curriculum_Version__c = '2025'
      );
      insert civil;
      activeRule(civil.Id, 60);
      insert new Campus_Branch__c(
        Campus__c = fixture.campus.Id,
        Branch__c = civil.Id,
        Academic_Year__c = '2026-27',
        Intake_Regular__c = 10,
        Intake_Lateral__c = 0,
        Admissions_Open__c = true
      );
      Test.startTest();
      // The desk sees the verdict before saving anything.
      Integer admissionsBefore = [SELECT COUNT() FROM IndividualApplication];
      List<CollegeAdmissionController.CampusChoice> catalogue = CollegeAdmissionController.getAdmissionCatalogue();
      System.assertEquals(1, catalogue.size());
      System.assertEquals(2, catalogue[0].programmes[0].branches.size());
      CollegeAdmissionController.Requirements needs = CollegeAdmissionController.getRequirements(
        fixture.intake.Id,
        'Regular'
      );
      System.assert(needs.open);
      System.assertEquals('SSLC', needs.qualifyingLevel);
      System.assertEquals(90, needs.minimum);
      System.assertEquals(100000, needs.tuition);
      System.assertEquals(
        false,
        CollegeAdmissionController.getRequirements(fixture.intake.Id, 'Lateral')
          .open
      );
      CollegeAdmissionController.Qualification declared = new CollegeAdmissionController.Qualification();
      declared.level = 'SSLC';
      declared.percentage = 72;
      AdmissionEligibilityService.Preview preview = CollegeAdmissionController.previewEligibility(
        fixture.intake.Id,
        'Regular',
        new List<CollegeAdmissionController.Qualification>{ declared },
        new List<CollegeAdmissionController.Entrance>()
      );
      System.assertEquals('Not Eligible', preview.status);
      System.assertEquals(1, preview.checks.size());
      System.assertEquals(false, preview.checks[0].passed);
      System.assertEquals(1, preview.suggestions.size());
      System.assertEquals('BE Civil', preview.suggestions[0].branch);
      System.assertEquals(
        admissionsBefore,
        [SELECT COUNT() FROM IndividualApplication],
        'Nothing saved by the preview'
      );
      CollegeAdmissionController.Admission a = CollegeAdmissionController.createAdmission(
        request(fixture.intake.Id, 72)
      );
      System.assertEquals('Not Eligible', a.eligibility);
      System.assertEquals(1, a.suggestions.size());
      System.assert(a.suggestions[0].startsWith('BE Civil'));
      try {
        CollegeAdmissionController.reject(a.id, ' ');
        System.assert(false, 'Reason required');
      } catch (AuraHandledException expected) {
        System.assert(true);
      }
      a = CollegeAdmissionController.reject(a.id, 'Below the BE CSE cut-off');
      Test.stopTest();
      System.assertEquals('Application Decision', a.stage);
      System.assertEquals('Reject', a.decision);
      try {
        CollegeAdmissionController.reject(a.id, 'Again');
        System.assert(false, 'Already decided');
      } catch (AuraHandledException expected) {
        System.assert(true);
      }
    }
  }

  @IsTest
  static void deskInputIsValidatedAndOthersAreRefused() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(1, 7);
    System.runAs(fixture.dean) {
      Test.startTest();
      CollegeAdmissionController.NewAdmission empty = request(
        fixture.intake.Id,
        72
      );
      empty.qualifications = null;
      try {
        CollegeAdmissionController.createAdmission(empty);
        System.assert(false, 'Qualification required');
      } catch (AuraHandledException expected) {
        System.assert(true);
      }
      Test.stopTest();
    }
    User finance = TestDataFactory.createUser(
      new List<String>{ 'KEM_Finance' }
    );
    System.runAs(finance) {
      try {
        CollegeAdmissionController.admit(fixture.admission.Id);
        System.assert(false, 'Dean permission required');
      } catch (AuraHandledException expected) {
        System.assert(true);
      }
      try {
        CollegeAdmissionController.getAdmission(fixture.admission.Id);
        System.assert(false, 'No access to the admission');
      } catch (AuraHandledException expected) {
        System.assert(true);
      }
    }
  }
}
