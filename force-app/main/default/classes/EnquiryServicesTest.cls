@IsTest
private class EnquiryServicesTest {
  @IsTest
  static void assignsToCounsellorWithLowestWorkload() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      User busy = TestDataFactory.createCounsellor(branch.Id);
      User free = TestDataFactory.createCounsellor(branch.Id);
      Lead existing = TestDataFactory.buildEnquiry(null);
      existing.OwnerId = busy.Id;
      insert existing;

      Test.startTest();
      List<Lead> enquiries = new List<Lead>{
        TestDataFactory.buildEnquiry(branch.Id),
        TestDataFactory.buildEnquiry(branch.Id)
      };
      insert enquiries;
      Test.stopTest();

      Map<Id, Lead> saved = new Map<Id, Lead>(
        [SELECT OwnerId, Next_Follow_Up__c FROM Lead WHERE Id IN :enquiries]
      );
      Assert.areEqual(
        free.Id,
        saved.get(enquiries[0].Id).OwnerId,
        'First enquiry goes to the counsellor with no open enquiries'
      );
      Assert.areEqual(
        new Set<Id>{ free.Id, busy.Id }.size(),
        new Set<Id>{
            saved.get(enquiries[0].Id).OwnerId,
            saved.get(enquiries[1].Id).OwnerId
          }
          .size(),
        'Load is balanced'
      );
      Assert.isNotNull(
        saved.get(enquiries[0].Id).Next_Follow_Up__c,
        'First follow-up is scheduled'
      );
      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM Task
          WHERE WhoId IN :enquiries AND Priority = 'High'
        ],
        'A first-contact task is created per enquiry'
      );
    }
  }

  @IsTest
  static void fallsBackToBranchManager() {
    System.runAs(TestDataFactory.admin()) {
      User manager = TestDataFactory.createUser(
        new List<String>{ 'KEM_Branch_Manager' }
      );
      Branch__c branch = TestDataFactory.buildBranch();
      branch.Branch_Manager__c = manager.Id;
      insert branch;
      Lead enquiry = TestDataFactory.buildEnquiry(branch.Id);
      insert enquiry;
      Assert.areEqual(
        manager.Id,
        [SELECT OwnerId FROM Lead WHERE Id = :enquiry.Id].OwnerId,
        'Branch manager owns enquiries when no counsellor exists'
      );
    }
  }

  @IsTest
  static void flagsDuplicatesAgainstEnquiriesAndPeople() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      Lead first = TestDataFactory.buildEnquiry(branch.Id);
      insert first;
      Lead second = TestDataFactory.buildEnquiry(branch.Id);
      second.Email = first.Email;
      Database.DMLOptions allowDuplicates = new Database.DMLOptions();
      allowDuplicates.DuplicateRuleHeader.allowSave = true;
      Database.insert(second, allowDuplicates);
      Lead saved = [
        SELECT Possible_Duplicate__c, Duplicate_Details__c
        FROM Lead
        WHERE Id = :second.Id
      ];
      Assert.isTrue(
        saved.Possible_Duplicate__c,
        'Same email is a possible duplicate'
      );
      Assert.isTrue(
        saved.Duplicate_Details__c.contains(first.Id),
        'Details reference the matching enquiry'
      );

      second.Email = 'unique-' + Crypto.getRandomInteger() + '@example.com';
      second.MobilePhone = '+910000000000';
      update second;
      Assert.isFalse(
        [SELECT Possible_Duplicate__c FROM Lead WHERE Id = :second.Id]
        .Possible_Duplicate__c,
        'Flag clears once contact details are unique'
      );
    }
  }

  @IsTest
  static void enforcesStatusTransitionsAndLostReason() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      Lead enquiry = TestDataFactory.buildEnquiry(branch.Id);
      insert enquiry;
      enquiry.Status = 'Contacted';
      update enquiry;
      Assert.isNotNull(
        [SELECT Last_Contacted__c FROM Lead WHERE Id = :enquiry.Id]
        .Last_Contacted__c,
        'Contacted stamps Last Contacted'
      );

      Database.SaveResult noReason = Database.update(
        new Lead(Id = enquiry.Id, Status = 'Unqualified'),
        false
      );
      Assert.isFalse(
        noReason.isSuccess(),
        'Unqualified requires a lost reason'
      );

      EnquiryController.updateStatus(enquiry.Id, 'Unqualified', 'Price');
      Assert.areEqual(
        'Unqualified',
        [SELECT Status FROM Lead WHERE Id = :enquiry.Id].Status,
        'Status updated with reason'
      );

      Database.SaveResult invalid = Database.update(
        new Lead(Id = enquiry.Id, Status = 'New'),
        false
      );
      Assert.isFalse(
        invalid.isSuccess(),
        'Unqualified to New is not an allowed transition'
      );
    }
  }

  @IsTest
  static void convertsEnquiryIntoLearnerGuardianAndApplication() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      LearningCourse course = TestDataFactory.createCourse(
        'Mathematics Foundation'
      );
      Lead enquiry = TestDataFactory.buildEnquiry(branch.Id);
      enquiry.Interested_Course__c = course.Id;
      insert enquiry;

      EnquiryConversionService.ConversionPreview preview = EnquiryController.getConversionPreview(
        enquiry.Id
      );
      Assert.isNull(preview.learnerMatch, 'No existing learner');
      Assert.isTrue(preview.hasGuardianDetails, 'Guardian details captured');

      EnquiryConversionService.ConversionRequest request = new EnquiryConversionService.ConversionRequest();
      request.leadId = enquiry.Id;
      request.createApplication = true;
      Test.startTest();
      EnquiryConversionService.ConversionResult result = EnquiryController.convertEnquiry(
        request
      );
      Test.stopTest();

      Assert.isTrue(
        result.learnerCreated && result.guardianCreated,
        'Learner and guardian created'
      );
      Account learner = [
        SELECT PersonContactId, KEM_Role__c, Branch__c, PersonBirthdate
        FROM Account
        WHERE Id = :result.learnerId
      ];
      Account guardian = [
        SELECT PersonContactId, KEM_Role__c
        FROM Account
        WHERE Id = :result.guardianId
      ];
      Assert.areEqual('Learner', learner.KEM_Role__c, 'Learner role');
      Assert.areEqual(branch.Id, learner.Branch__c, 'Learner home branch');
      Assert.areEqual(
        enquiry.Learner_Birthdate__c,
        learner.PersonBirthdate,
        'Birthdate carried over'
      );
      Assert.areEqual('Guardian', guardian.KEM_Role__c, 'Guardian role');

      ContactContactRelation rel = [
        SELECT Is_Fee_Payer__c, Portal_Access__c, Guardian_Relationship__c
        FROM ContactContactRelation
        WHERE
          ContactId = :guardian.PersonContactId
          AND RelatedContactId = :learner.PersonContactId
      ];
      Assert.isTrue(
        rel.Is_Fee_Payer__c && rel.Portal_Access__c,
        'Guardian is fee payer with portal access'
      );
      Assert.areEqual(
        'Father',
        rel.Guardian_Relationship__c,
        'Relationship carried over'
      );
      Assert.isTrue(
        GuardianRelationshipService.learnersOf(guardian.PersonContactId, true)
          .contains(learner.PersonContactId),
        'Guardian sees learner'
      );

      IndividualApplication application = [
        SELECT
          Status,
          Branch__c,
          Learning_Course__c,
          Source_Enquiry__c,
          AccountId
        FROM IndividualApplication
        WHERE Id = :result.applicationId
      ];
      Assert.areEqual(
        'Processing',
        application.Status,
        'Application starts in Processing'
      );
      Assert.areEqual(
        course.Id,
        application.Learning_Course__c,
        'Course carried over'
      );
      Assert.areEqual(
        enquiry.Id,
        application.Source_Enquiry__c,
        'Application traces its enquiry'
      );

      Lead converted = [
        SELECT
          IsConverted,
          ConvertedAccountId,
          Converted_Learner__c,
          Converted_Application__c
        FROM Lead
        WHERE Id = :enquiry.Id
      ];
      Assert.isTrue(converted.IsConverted, 'Lead converted');
      Assert.areEqual(
        result.learnerId,
        converted.ConvertedAccountId,
        'Converted into the learner account'
      );
      Assert.areEqual(
        result.applicationId,
        converted.Converted_Application__c,
        'Lead links the application'
      );
    }
  }

  @IsTest
  static void reusesExistingLearnerAndGuardian() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      Lead enquiry = TestDataFactory.buildEnquiry(branch.Id);
      insert enquiry;
      Account learner = PersonAccountService.buildPerson(
        'Asha',
        enquiry.LastName,
        enquiry.Email,
        null,
        branch.Id,
        'Learner'
      );
      Account guardian = PersonAccountService.buildPerson(
        'Ravi',
        enquiry.Guardian_Last_Name__c,
        enquiry.Guardian_Email__c,
        null,
        branch.Id,
        'Learner'
      );
      insert new List<Account>{ learner, guardian };

      EnquiryConversionService.ConversionPreview preview = EnquiryConversionService.preview(
        enquiry.Id
      );
      Assert.areEqual(
        learner.Id,
        preview.learnerMatch.Id,
        'Existing learner matched by email'
      );
      Assert.areEqual(
        guardian.Id,
        preview.guardianMatch.Id,
        'Existing guardian matched by email'
      );

      EnquiryConversionService.ConversionRequest request = new EnquiryConversionService.ConversionRequest();
      request.leadId = enquiry.Id;
      request.existingLearnerId = learner.Id;
      request.existingGuardianId = guardian.Id;
      request.createApplication = false;
      EnquiryConversionService.ConversionResult result = EnquiryConversionService.convert(
        request
      );

      Assert.areEqual(learner.Id, result.learnerId, 'Existing learner reused');
      Assert.isFalse(result.learnerCreated, 'No new learner');
      Assert.isNull(result.applicationId, 'No application requested');
      Assert.areEqual(
        'Learner and Guardian',
        [SELECT KEM_Role__c FROM Account WHERE Id = :guardian.Id].KEM_Role__c,
        'Role merged'
      );

      try {
        EnquiryConversionService.convert(request);
        Assert.fail('Converting twice must fail');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('already been converted'),
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void conversionRollsBackOnFailure() {
    System.runAs(TestDataFactory.admin()) {
      Lead enquiry = TestDataFactory.buildEnquiry(null);
      enquiry.Company = 'Acme';
      insert enquiry;
      EnquiryConversionService.ConversionRequest request = new EnquiryConversionService.ConversionRequest();
      request.leadId = enquiry.Id;
      try {
        EnquiryController.convertEnquiry(request);
        Assert.fail('Conversion without branch must fail');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('branch'), e.getMessage());
      }
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM Account
          WHERE IsPersonAccount = TRUE AND LastName = :enquiry.LastName
        ],
        'Nothing created'
      );
    }
  }

  @IsTest
  static void counsellorCanWorkAndConvertEnquiries() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      User counsellor = TestDataFactory.createCounsellor(branch.Id);
      System.runAs(counsellor) {
        Lead enquiry = TestDataFactory.buildEnquiry(branch.Id);
        Database.insert(enquiry, AccessLevel.USER_MODE);
        EnquiryController.logFollowUp(
          enquiry.Id,
          'Interested',
          'Wants weekend batch',
          System.now().addDays(2)
        );
        Lead worked = [
          SELECT Status, OwnerId, Last_Contacted__c
          FROM Lead
          WHERE Id = :enquiry.Id
        ];
        Assert.areEqual(
          'Contacted',
          worked.Status,
          'Logging a follow-up moves New to Contacted'
        );
        Assert.areEqual(
          counsellor.Id,
          worked.OwnerId,
          'Counsellor keeps their own enquiry'
        );

        List<EnquiryController.PipelineColumn> pipeline = EnquiryController.getPipeline(
          branch.Id,
          true
        );
        Assert.areEqual(3, pipeline.size(), 'Three pipeline columns');
        Assert.areEqual(
          1,
          pipeline[1].enquiries.size(),
          'Enquiry shown under Contacted'
        );
        Assert.isFalse(
          EnquiryController.getBranches().isEmpty(),
          'Branches available for filter'
        );

        EnquiryConversionService.ConversionRequest request = new EnquiryConversionService.ConversionRequest();
        request.leadId = enquiry.Id;
        EnquiryConversionService.ConversionResult result = EnquiryController.convertEnquiry(
          request
        );
        Assert.isNotNull(
          result.applicationId,
          'Counsellor converts with an application'
        );
      }
    }
  }

  @IsTest
  static void qualifiedStatusRequiresConversion() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      Lead enquiry = TestDataFactory.buildEnquiry(branch.Id);
      insert enquiry;
      try {
        EnquiryController.updateStatus(enquiry.Id, 'Qualified', null);
        Assert.fail('Qualified must go through conversion');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('Convert'), e.getMessage());
      }
    }
  }

  @IsTest
  static void flagsMatchesAgainstExistingPeopleByEmailAndPhone() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      Account person = PersonAccountService.buildPerson(
        'Kiran',
        'Existing',
        'kiran.existing@example.com',
        '+919812345678',
        branch.Id,
        'Learner'
      );
      insert person;

      Lead byEmail = TestDataFactory.buildEnquiry(branch.Id);
      byEmail.Email = 'kiran.existing@example.com';
      Lead byPhone = TestDataFactory.buildEnquiry(branch.Id);
      byPhone.MobilePhone = '+919812345678';
      Lead unique = TestDataFactory.buildEnquiry(branch.Id);
      Database.DMLOptions allowDuplicates = new Database.DMLOptions();
      allowDuplicates.DuplicateRuleHeader.allowSave = true;
      Database.insert(
        new List<Lead>{ byEmail, byPhone, unique },
        allowDuplicates
      );

      Map<Id, Lead> saved = new Map<Id, Lead>(
        [
          SELECT Possible_Duplicate__c, Duplicate_Details__c
          FROM Lead
          WHERE Id IN :new List<Id>{ byEmail.Id, byPhone.Id, unique.Id }
        ]
      );
      Assert.isTrue(
        saved.get(byEmail.Id).Duplicate_Details__c.contains(person.Id),
        'Email match against an existing person'
      );
      Assert.isTrue(
        saved.get(byPhone.Id).Possible_Duplicate__c,
        'Phone match against an existing person'
      );
      Assert.isFalse(
        saved.get(unique.Id).Possible_Duplicate__c,
        'Unique enquiry is not flagged'
      );

      Account found = PersonAccountService.findPerson(
        null,
        '+919812345678',
        'Existing'
      );
      Assert.areEqual(
        person.Id,
        found.Id,
        'Person found by phone and last name'
      );
      Assert.isNull(
        PersonAccountService.findPerson(null, null, null),
        'No criteria returns null'
      );
      Assert.areEqual(
        'Learner and Guardian',
        PersonAccountService.mergeRole('Guardian', 'Learner'),
        'Roles merge'
      );
    }
  }

  @IsTest
  static void branchStaffKeyFollowsRoleChanges() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      User counsellor = TestDataFactory.createCounsellor(branch.Id);
      Branch_Staff__c staff = [
        SELECT Id, Unique_Key__c
        FROM Branch_Staff__c
        WHERE User__c = :counsellor.Id
      ];
      update new Branch_Staff__c(Id = staff.Id, Role__c = 'Teacher');
      Assert.isTrue(
        [SELECT Unique_Key__c FROM Branch_Staff__c WHERE Id = :staff.Id]
          .Unique_Key__c.endsWith(':Teacher'),
        'Key recalculated on role change'
      );
    }
  }
}
