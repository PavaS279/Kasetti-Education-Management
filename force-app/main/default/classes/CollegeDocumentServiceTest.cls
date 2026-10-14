@IsTest
private class CollegeDocumentServiceTest {
  @IsTest
  static void collegeAdmissionSnapshotsOnlyMatchingDocumentRules() {
    LearningProgram programme = programme();
    insert new List<Admission_Document_Rule__c>{
      new Admission_Document_Rule__c(
        Programme__c = programme.Id,
        Academic_Year__c = '2026-27',
        Entry_Route__c = 'Regular',
        Document_Type__c = 'Aadhaar',
        Label__c = 'Aadhaar card',
        Instruction__c = 'Upload a clear image.',
        Required__c = true,
        Sensitive_Class__c = 'Identity',
        Retain_File__c = false,
        AI_Extractable__c = false,
        Sort_Order__c = 10
      ),
      new Admission_Document_Rule__c(
        Programme__c = programme.Id,
        Academic_Year__c = '2026-27',
        Entry_Route__c = 'Lateral',
        Document_Type__c = 'DiplomaMarks',
        Label__c = 'Diploma marks card',
        Sensitive_Class__c = 'Academic',
        Retention_Days__c = 365,
        Sort_Order__c = 20
      )
    };
    IndividualApplication admission = admission(programme.Id, 'Regular');

    List<DocumentChecklistItem> items = [
      SELECT
        Name,
        IsRequired,
        Instruction,
        Document_Rule__c,
        Document_Type__c,
        Sensitive_Class__c,
        Retain_File__c,
        AI_Extractable__c
      FROM DocumentChecklistItem
      WHERE ParentRecordId = :admission.Id
    ];
    System.assertEquals(1, items.size());
    System.assertEquals('Aadhaar card', items[0].Name);
    System.assertEquals('Aadhaar', items[0].Document_Type__c);
    System.assertEquals('Identity', items[0].Sensitive_Class__c);
    System.assertEquals(false, items[0].Retain_File__c);
    System.assertNotEquals(null, items[0].Document_Rule__c);

    CollegeDocumentService.createChecklists(new Set<Id>{ admission.Id });
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM DocumentChecklistItem
        WHERE ParentRecordId = :admission.Id
      ]
    );
  }

  @IsTest
  static void consentIsTimestampedAndLimitedToCollegeAdmissions() {
    LearningProgram programme = programme();
    IndividualApplication college = admission(programme.Id, 'Regular');
    Test.startTest();
    CollegeDocumentService.captureConsent(college.Id);
    Test.stopTest();
    college = [
      SELECT Privacy_Consent__c, Consent_Captured_On__c, Consent_Captured_By__c
      FROM IndividualApplication
      WHERE Id = :college.Id
    ];
    System.assertEquals(true, college.Privacy_Consent__c);
    System.assertNotEquals(null, college.Consent_Captured_On__c);
    System.assertEquals(UserInfo.getUserId(), college.Consent_Captured_By__c);

    IndividualApplication learningCentre = learningCentreAdmission();
    try {
      CollegeDocumentService.captureConsent(learningCentre.Id);
      System.assert(false, 'Expected non-college consent to be refused.');
    } catch (AppException expected) {
      System.assert(expected.getMessage().contains('only to college'));
    }
  }

  @IsTest
  static void identityVerificationRequiresConsentAndDeletesTheFile() {
    LearningProgram programme = programme();
    insert new Admission_Document_Rule__c(
      Programme__c = programme.Id,
      Academic_Year__c = '2026-27',
      Entry_Route__c = 'Regular',
      Document_Type__c = 'Aadhaar',
      Label__c = 'Aadhaar card',
      Required__c = true,
      Sensitive_Class__c = 'Identity',
      Retain_File__c = false,
      Sort_Order__c = 10
    );
    IndividualApplication admission = admission(programme.Id, 'Regular');
    DocumentChecklistItem item = [
      SELECT Id
      FROM DocumentChecklistItem
      WHERE ParentRecordId = :admission.Id
      LIMIT 1
    ];
    ContentVersion version = new ContentVersion(
      Title = 'identity',
      PathOnClient = 'identity.pdf',
      VersionData = Blob.valueOf('identity-test')
    );
    insert version;
    Id documentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :version.Id
    ]
    .ContentDocumentId;
    insert new ContentDocumentLink(
      ContentDocumentId = documentId,
      LinkedEntityId = item.Id,
      ShareType = 'V'
    );
    try {
      CollegeDocumentService.verify(item.Id, '1234');
      System.assert(false, 'Expected consent to be required.');
    } catch (AppException expected) {
      System.assert(expected.getMessage().contains('privacy consent'));
    }
    CollegeDocumentService.captureConsent(admission.Id);
    try {
      CollegeDocumentService.verify(item.Id, '12345');
      System.assert(false, 'Expected a masked value only.');
    } catch (AppException expected) {
      System.assert(expected.getMessage().contains('last four'));
    }

    CollegeDocumentService.suppressStatusUpdates = true;
    Test.startTest();
    CollegeDocumentService.verify(item.Id, '1234');
    Test.stopTest();
    item = [
      SELECT
        Status,
        Last4__c,
        Verified_By__c,
        Verified_On__c,
        File_Deleted_On__c
      FROM DocumentChecklistItem
      WHERE Id = :item.Id
    ];
    System.assertEquals('New', item.Status);
    System.assertEquals('1234', item.Last4__c);
    System.assertEquals(UserInfo.getUserId(), item.Verified_By__c);
    System.assertNotEquals(null, item.Verified_On__c);
    System.assertNotEquals(null, item.File_Deleted_On__c);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :documentId]
    );
  }

  @IsTest
  static void retentionJobDeletesOnlyElapsedFiles() {
    LearningProgram programme = programme();
    insert new Admission_Document_Rule__c(
      Programme__c = programme.Id,
      Academic_Year__c = '2026-27',
      Entry_Route__c = 'Regular',
      Document_Type__c = 'MarksCard',
      Label__c = 'Marks card',
      Required__c = true,
      Sensitive_Class__c = 'Academic',
      Retain_File__c = true,
      Retention_Days__c = 1,
      Sort_Order__c = 10
    );
    IndividualApplication admission = admission(programme.Id, 'Regular');
    DocumentChecklistItem item = [
      SELECT Id
      FROM DocumentChecklistItem
      WHERE ParentRecordId = :admission.Id
    ];
    ContentVersion version = new ContentVersion(
      Title = 'marks',
      PathOnClient = 'marks.pdf',
      VersionData = Blob.valueOf('marks-test')
    );
    insert version;
    Id documentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :version.Id
    ]
    .ContentDocumentId;
    insert new ContentDocumentLink(
      ContentDocumentId = documentId,
      LinkedEntityId = item.Id,
      ShareType = 'V'
    );
    update new DocumentChecklistItem(
      Id = item.Id,
      Verified_On__c = System.now().addDays(-2)
    );

    Test.startTest();
    Database.executeBatch(new CollegeDocumentRetentionJob(), 100);
    Test.stopTest();
    item = [
      SELECT File_Deleted_On__c
      FROM DocumentChecklistItem
      WHERE Id = :item.Id
    ];
    System.assertNotEquals(null, item.File_Deleted_On__c);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :documentId]
    );
  }

  @IsTest
  static void schedulableRetentionEntryPointStartsTheBatch() {
    Test.startTest();
    new CollegeDocumentRetentionJob().execute((SchedulableContext) null);
    Test.stopTest();
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM DocumentChecklistItem
        WHERE File_Deleted_On__c != NULL
      ]
    );
  }

  @IsTest
  static void collegeStageAdvancesOnlyAfterEligibilityConsentAndChecklist() {
    LearningProgram programme = programme();
    insert new Admission_Document_Rule__c(
      Programme__c = programme.Id,
      Academic_Year__c = '2026-27',
      Entry_Route__c = 'Regular',
      Document_Type__c = 'MarksCard',
      Label__c = 'Marks card',
      Required__c = true,
      Sensitive_Class__c = 'Academic',
      Retain_File__c = true,
      Retention_Days__c = 365,
      Sort_Order__c = 10
    );
    IndividualApplication admission = admission(programme.Id, 'Regular');
    update new IndividualApplication(
      Id = admission.Id,
      Eligibility_Status__c = 'Eligible'
    );
    CollegeDocumentService.captureConsent(admission.Id);
    try {
      CollegeDocumentService.markDocumentsVerified(admission.Id);
      System.assert(false, 'Expected the required checklist to be verified.');
    } catch (AppException expected) {
      System.assert(expected.getMessage().contains('has not been verified'));
    }
    DocumentChecklistItem item = [
      SELECT Id
      FROM DocumentChecklistItem
      WHERE ParentRecordId = :admission.Id AND IsRequired = TRUE
    ];
    ChecklistItemGateway.simulateStatusUpdates = true;
    ChecklistItemGateway.updateStatusAsSystem(
      new List<DocumentChecklistItem>{
        new DocumentChecklistItem(Id = item.Id, Status = 'Accepted')
      }
    );

    Test.startTest();
    CollegeDocumentService.markDocumentsVerified(admission.Id);
    Test.stopTest();
    System.assertEquals(
      'Documents Verified',
      [
        SELECT College_Stage__c
        FROM IndividualApplication
        WHERE Id = :admission.Id
      ]
      .College_Stage__c
    );
  }

  private static IndividualApplication admission(Id programmeId, String route) {
    Branch__c campus = TestDataFactory.createBranch();
    Account learner = learner(campus.Id);
    IndividualApplication value = new IndividualApplication(
      College_Mode__c = true,
      Category = 'Education',
      ApplicationType = 'Undergraduate',
      ApplicationCategory = 'Regular Decision',
      AccountId = learner.Id,
      ContactId = learner.PersonContactId,
      Status = 'Processing',
      Branch__c = campus.Id,
      Learning_Program__c = programmeId,
      Academic_Year__c = '2026-27',
      Entry_Route__c = route,
      Entry_Year_Of_Study__c = route == 'Lateral' ? 2 : 1
    );
    insert value;
    return value;
  }

  private static IndividualApplication learningCentreAdmission() {
    Branch__c branch = TestDataFactory.createBranch();
    Account value = learner(branch.Id);
    IndividualApplication admission = new IndividualApplication(
      Category = 'Education',
      AccountId = value.Id,
      ContactId = value.PersonContactId,
      Status = 'Processing',
      Branch__c = branch.Id
    );
    insert admission;
    return admission;
  }

  private static Account learner(Id branchId) {
    Account value = PersonAccountService.buildPerson(
      'College',
      'Applicant' + Crypto.getRandomInteger(),
      null,
      null,
      branchId,
      'Learner'
    );
    insert value;
    return [SELECT Id, PersonContactId FROM Account WHERE Id = :value.Id];
  }

  private static LearningProgram programme() {
    Learning learning = new Learning(
      Name = 'BE ' + Crypto.getRandomInteger(),
      Type = 'LearningProgram',
      IsActive = true
    );
    insert learning;
    LearningProgram value = new LearningProgram(
      Name = learning.Name,
      LearningId = learning.Id,
      Programme_Code__c = 'B',
      Duration_Years__c = 4,
      Terms_Per_Year__c = 2,
      Term_Label__c = 'Semester',
      Qualification_Level__c = 'BE',
      Active__c = true
    );
    insert value;
    return value;
  }
}
