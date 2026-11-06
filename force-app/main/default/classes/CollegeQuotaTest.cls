@IsTest
private class CollegeQuotaTest {
  private class Quotas {
    Admission_Quota__c cet;
    Admission_Quota__c management;
    Admission_Quota__c snq;
  }

  private static Quotas quotas(
    CollegeTestFactory.Fixture f,
    Integer cetSeats,
    Integer mgmtSeats
  ) {
    Quotas q = new Quotas();
    q.cet = new Admission_Quota__c(
      Name = 'CET',
      Code__c = 'CET',
      Rank_Exam__c = 'KCET',
      Sort_Order__c = 1
    );
    q.management = new Admission_Quota__c(
      Name = 'Management',
      Code__c = 'MGMT',
      Sort_Order__c = 2
    );
    q.snq = new Admission_Quota__c(
      Name = 'SNQ',
      Code__c = 'SNQ',
      Extra_Document__c = 'Income certificate',
      Sort_Order__c = 3
    );
    insert new List<Admission_Quota__c>{ q.cet, q.management, q.snq };
    insert new List<Seat_Quota__c>{
      new Seat_Quota__c(
        Campus_Branch__c = f.intake.Id,
        Admission_Quota__c = q.cet.Id,
        Seats__c = cetSeats
      ),
      new Seat_Quota__c(
        Campus_Branch__c = f.intake.Id,
        Admission_Quota__c = q.management.Id,
        Seats__c = mgmtSeats
      ),
      new Seat_Quota__c(
        Campus_Branch__c = f.intake.Id,
        Admission_Quota__c = q.snq.Id,
        Seats__c = 0
      )
    };
    return q;
  }

  private static void giveRank(Id studentId) {
    insert new Entrance_Score__c(
      Student__c = studentId,
      Exam__c = 'KCET',
      Rank__c = 12400,
      Exam_Year__c = Date.today().year()
    );
  }

  @IsTest
  static void aFullQuotaRefusesTheNextAdmission() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    MessageService.disabled = true;
    DocumentService.suppressJobs = true;
    Quotas q = quotas(f, 4, 1);
    IndividualApplication second;
    System.runAs(f.dean) {
      second = CollegeTestFactory.admission(f, 'Second');
    }
    update new List<IndividualApplication>{
      new IndividualApplication(
        Id = f.admission.Id,
        Admission_Quota__c = q.management.Id
      ),
      new IndividualApplication(
        Id = second.Id,
        Admission_Quota__c = q.management.Id
      )
    };
    Test.startTest();
    System.runAs(f.dean) {
      InterviewService.admit(f.admission.Id);
      try {
        InterviewService.admit(second.Id);
        Assert.fail('Management is full');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('Management seats'),
          e.getMessage()
        );
        Assert.isTrue(e.getMessage().contains('(1 of 1)'), e.getMessage());
      }
    }
    Test.stopTest();
    Assert.areEqual(
      q.management.Id,
      [
        SELECT Admission_Quota__c
        FROM Seat_Reservation__c
        WHERE Application__c = :f.admission.Id
      ]
      .Admission_Quota__c
    );
    List<CollegeQuotaService.QuotaSeats> seats = CollegeQuotaService.seatsFor(
      f.intake.Id
    );
    Assert.areEqual(3, seats.size());
    Assert.areEqual(
      0,
      CollegeQuotaService.openQuotas(f.intake.Id).size() - 1,
      'Only CET has seats left'
    );
  }

  @IsTest
  static void theCetQuotaNeedsAKcetRank() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    MessageService.disabled = true;
    DocumentService.suppressJobs = true;
    quotas(f, 4, 1);
    System.runAs(f.dean) {
      try {
        InterviewService.admit(f.admission.Id); // no quota: the default CET
        Assert.fail('No KCET rank yet');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('needs a KCET rank'),
          e.getMessage()
        );
      }
    }
    giveRank(f.admission.AccountId);
    Test.startTest();
    System.runAs(f.dean) {
      InterviewService.admit(f.admission.Id);
    }
    Test.stopTest();
    Assert.areEqual(
      'Fee Pending',
      [
        SELECT College_Stage__c
        FROM IndividualApplication
        WHERE Id = :f.admission.Id
      ]
      .College_Stage__c
    );
  }

  @IsTest
  static void counsellorChangesTheQuotaAndTheExtraDocumentIsAdded() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    Quotas q = quotas(f, 4, 1);
    update new IndividualApplication(
      Id = f.admission.Id,
      College_Stage__c = 'Documents Verified'
    );
    System.runAs(f.dean) {
      CollegeAdmissionController.Admission view = CollegeAdmissionController.getAdmission(
        f.admission.Id
      );
      Assert.isTrue(view.canChangeQuota);
      Assert.areEqual(3, view.quotas.size());
      CollegeAdmissionController.setQuota(f.admission.Id, q.snq.Id);
    }
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM DocumentChecklistItem
        WHERE ParentRecordId = :f.admission.Id AND Name = 'Income certificate'
      ]
    );
    Assert.areEqual(
      1,
      CollegePublicController.getQuotas(f.intake.Id).size() - 1,
      'CET and Management are open'
    );
  }

  @IsTest
  static void setupKeepsTheSplitEqualToTheIntake() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    Quotas q = quotas(f, 4, 1);
    User admin = new User(
      Alias = 'qadm',
      Email = 'kem.qadm' + Crypto.getRandomInteger() + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Quota Admin',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_IN',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator']
      .Id,
      TimeZoneSidKey = 'Asia/Kolkata',
      Username = 'kem.qadm' + Crypto.getRandomInteger() + '@kasetti.test'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert admin;
    }
    System.runAs(admin) {
      CollegeSetupController.Setup view = CollegeSetupController.getSetup();
      Assert.areEqual(3, view.quotas.size());
      List<CollegeSetupController.SplitEntry> split = new List<CollegeSetupController.SplitEntry>();
      for (
        Admission_Quota__c quota : new List<Admission_Quota__c>{
          q.cet,
          q.management,
          q.snq
        }
      ) {
        CollegeSetupController.SplitEntry e = new CollegeSetupController.SplitEntry();
        e.quotaId = quota.Id;
        e.seats = 2;
        split.add(e);
      }
      try {
        CollegeSetupController.saveSplit(f.intake.Id, split);
        Assert.fail('2 + 2 + 2 is not 5');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('= 6'), e.getMessage());
      }
      split[2].seats = 1;
      CollegeSetupController.saveSplit(f.intake.Id, split);

      CollegeSetupController.QuotaDef dup = new CollegeSetupController.QuotaDef();
      dup.name = 'Another CET';
      dup.code = 'cet';
      try {
        CollegeSetupController.saveQuota(dup);
        Assert.fail('Codes are unique');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('already uses'), e.getMessage());
      }
      CollegeSetupController.QuotaDef nri = new CollegeSetupController.QuotaDef();
      nri.name = 'NRI';
      nri.code = 'nri';
      CollegeSetupController.saveQuota(nri);
    }
    Assert.areEqual(
      1,
      [
        SELECT Seats__c
        FROM Seat_Quota__c
        WHERE Campus_Branch__c = :f.intake.Id AND Admission_Quota__c = :q.snq.Id
      ]
      .Seats__c
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Admission_Quota__c WHERE Code__c = 'NRI']
    );
  }
}
