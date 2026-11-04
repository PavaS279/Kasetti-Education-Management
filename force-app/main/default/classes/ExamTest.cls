@IsTest
private class ExamTest {
  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      MessageService.disabled = true;
      IntegrationService.disabled = true;
      Branch__c branch = TestDataFactory.buildBranch();
      branch.Branch_Code__c = 'EXM-01';
      insert branch;
      insert new List<Room__c>{
        new Room__c(
          Name = 'Hall A',
          Branch__c = branch.Id,
          Capacity__c = 1,
          Room_Type__c = 'Hall'
        ),
        new Room__c(
          Name = 'Room B',
          Branch__c = branch.Id,
          Capacity__c = 2,
          Room_Type__c = 'Classroom'
        )
      };
      LearningCourse course = TestDataFactory.createCourse('Exam Maths');
      insert new Fee_Price__c(
        Learning_Course__c = course.Id,
        Branch__c = branch.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'One-time',
        Amount__c = 3000,
        Effective_From__c = Date.today().addDays(-30)
      );
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        10
      );
      update new CourseOffering(Id = offering.Id, Name = 'Exam Maths Class');
      List<Account> learners = new List<Account>();
      for (String first : new List<String>{ 'Asha', 'Bala', 'Chitra' }) {
        learners.add(
          PersonAccountService.buildPerson(
            first,
            'Candidate',
            null,
            null,
            branch.Id,
            'Learner'
          )
        );
      }
      insert learners;
      List<Decimal> attendance = new List<Decimal>{ 95, 92, 60 };
      for (Integer i = 0; i < learners.size(); i++) {
        EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
        request.learnerAccountId = learners[i].Id;
        request.offeringId = offering.Id;
        Id enrolmentId = EnrolmentService.enrol(request).enrolmentId;
        Database.update(
          new CourseOfferingParticipant(
            Id = enrolmentId,
            Attendance_Rate__c = attendance[i]
          ),
          AccessLevel.SYSTEM_MODE
        );
      }
      LearnerService.GuardianInput g = new LearnerService.GuardianInput();
      g.firstName = 'Gita';
      g.lastName = 'Candidate';
      g.relationship = 'Mother';
      g.isFeePayer = true;
      LearnerService.addGuardian(learners[0].Id, g);
      Exam__c exam = new Exam__c(
        Name = 'Term 1 Exams',
        Exam_Code__c = 'T1-26',
        Branch__c = branch.Id,
        Start_Date__c = Date.today().addDays(10),
        End_Date__c = Date.today().addDays(12),
        Block_Overdue_Fees__c = true,
        Instructions__c = 'Arrive 20 minutes early.'
      );
      insert exam;
      insert new Exam_Paper__c(
        Exam__c = exam.Id,
        Name = 'Paper 1',
        Course_Offering__c = offering.Id,
        Paper_Date__c = Date.today().addDays(10),
        Start_Time__c = '09:30',
        Duration_Minutes__c = 90,
        Max_Marks__c = 50,
        Pass_Marks__c = 18,
        Weight__c = 20
      );
    }
  }

  private static Exam__c exam() {
    return [SELECT Id, Status__c FROM Exam__c WHERE Exam_Code__c = 'T1-26'];
  }

  private static Exam_Candidate__c candidate(String first) {
    return [
      SELECT
        Id,
        Name,
        Status__c,
        Withheld_Reason__c,
        Seat_Number__c,
        Room__r.Name,
        Override_Reason__c
      FROM Exam_Candidate__c
      WHERE Learner_Account__r.FirstName = :first
    ];
  }

  private static User examAdmin() {
    User u = TestDataFactory.admin();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.assignPermissionSets(
        u.Id,
        new List<String>{ 'KEM_Eligibility_Override' }
      );
    }
    return u;
  }

  @IsTest
  static void registerAndCheckEligibility() {
    User admin = examAdmin();
    System.runAs(admin) {
      // Bala has an overdue invoice.
      CourseOfferingParticipant bala = [
        SELECT Id
        FROM CourseOfferingParticipant
        WHERE ParticipantAccount.FirstName = 'Bala'
      ];
      Id invoiceId = BillingService.createInvoice(bala.Id, true);
      Database.update(
        new Student_Invoice__c(
          Id = invoiceId,
          Due_Date__c = Date.today().addDays(-5)
        ),
        AccessLevel.SYSTEM_MODE
      );
      Test.startTest();

      Assert.areEqual(1, ExamController.getExams(null).size(), 'Exam listed');
      ExamService.StepResult registered = ExamController.registerCandidates(
        exam().Id
      );
      Assert.areEqual(3, registered.processed, 'Three candidates');
      Assert.areEqual('Scheduled', exam().Status__c, 'Scheduled');
      Assert.areEqual(
        'T1-26-0001',
        candidate('Asha').Name,
        'Hall ticket numbers in name order'
      );
      Assert.areEqual(
        3,
        ExamController.registerCandidates(exam().Id).skipped,
        'Registered once'
      );

      ExamService.StepResult checked = ExamController.checkEligibility(
        exam().Id
      );
      Assert.areEqual(1, checked.processed, 'Asha eligible');
      Assert.areEqual('Eligible', candidate('Asha').Status__c, 'Eligible');
      Assert.isTrue(
        candidate('Bala').Withheld_Reason__c.contains('overdue'),
        'Fees overdue'
      );
      Assert.isTrue(
        candidate('Chitra').Withheld_Reason__c.contains('attendance 60.0%'),
        'Low attendance'
      );

      try {
        ExamController.overrideCandidate(candidate('Chitra').Id, 'x');
        Assert.fail('Reason needed');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('reason'), e.getMessage());
      }
      ExamController.overrideCandidate(
        candidate('Chitra').Id,
        'Medical leave certified'
      );
      Assert.areEqual('Eligible', candidate('Chitra').Status__c, 'Allowed');
      ExamService.checkEligibility(exam().Id);
      Assert.areEqual(
        'Eligible',
        candidate('Chitra').Status__c,
        'Override kept on re-check'
      );

      Test.stopTest();
    }
  }

  @IsTest
  static void seatAndIssueHallTickets() {
    System.runAs(examAdmin()) {
      ExamService.registerCandidates(exam().Id);
      ExamService.checkEligibility(exam().Id);
      ExamService.overrideCandidate(
        candidate('Chitra').Id,
        'Medical leave certified'
      );
      Test.startTest();
      ExamService.ExamDetail detail = ExamController.getExam(exam().Id);
      Assert.areEqual(2, detail.rooms.size(), 'Rooms of the branch');
      Assert.isTrue(ExamController.canSetUpExams(), 'Admin sets up exams');
      Assert.isTrue(
        detail.canOverride && detail.canManage,
        'Admin with override'
      );
      Assert.areEqual(
        3,
        detail.counts.get('Eligible'),
        'Three eligible (Chitra allowed)'
      );
      Id hall = detail.rooms[0].roomId;
      try {
        ExamService.allocateSeats(exam().Id, new List<Id>{ hall });
        Assert.fail('Not enough seats');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('seat 1 but 3'), e.getMessage());
      }
      Assert.areEqual(
        3,
        ExamController.allocateSeats(
            exam().Id,
            new List<Id>{ hall, detail.rooms[1].roomId }
          )
          .processed,
        'Seated'
      );
      Assert.areEqual(
        'Hall A-01',
        candidate('Asha').Seat_Number__c,
        'First seat'
      );
      Assert.areEqual(
        'Room B-02',
        candidate('Chitra').Seat_Number__c,
        'Next room'
      );

      ExamService.StepResult issued = ExamController.issueTickets(exam().Id);
      Test.stopTest();
      Assert.areEqual(3, issued.processed, 'Three tickets');
      Assert.areEqual('Ticket Issued', candidate('Asha').Status__c, 'Issued');
      Assert.areEqual('Hall Tickets Issued', exam().Status__c, 'Exam status');
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM ContentDocumentLink
          WHERE
            LinkedEntityId = :candidate('Asha').Id
            AND ContentDocument.LatestPublishedVersion.Description = 'KEM Hall Ticket'
        ],
        'Hall ticket PDF filed on the candidate'
      );
    }
  }

  @IsTest
  static void hallTicketPageShowsSeatAndPapers() {
    System.runAs(examAdmin()) {
      ExamService.registerCandidates(exam().Id);
      Exam_Candidate__c asha = candidate('Asha');
      PageReference page = Page.KEM_Hall_Ticket;
      page.getParameters().put('id', asha.Id);
      Test.setCurrentPage(page);
      KemDocumentController controller = new KemDocumentController();
      Assert.areEqual('T1-26-0001', controller.candidate.Name, 'Candidate');
      Assert.areEqual(1, controller.papers.size(), 'Her paper');
      Assert.areEqual('09:30', controller.papers[0].Start_Time__c, 'Time');
      try {
        DocumentService.generate(asha.Id, DocumentService.HALL_TICKET);
        Assert.fail('Not issued');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('once it is issued'),
          e.getMessage()
        );
      }
      Assert.areEqual(
        DocumentService.HALL_TICKET,
        DocumentService.kindFor(asha.Id),
        'Kind'
      );
    }
  }

  @IsTest
  static void marksArePublishedToTheGradebook() {
    System.runAs(examAdmin()) {
      ExamService.registerCandidates(exam().Id);
      Exam_Paper__c paper = [SELECT Id FROM Exam_Paper__c LIMIT 1];
      ExamService.MarkSheet sheet = ExamController.getMarkSheet(paper.Id);
      Assert.areEqual(3, sheet.rows.size(), 'Every candidate of the class');
      Assert.isTrue(sheet.editable, 'Editable');
      try {
        ExamController.publishMarks(paper.Id);
        Assert.fail('Nothing entered');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('Enter the marks'),
          e.getMessage()
        );
      }
      for (ExamService.MarkRow row : sheet.rows) {
        if (row.learner.startsWith('Asha')) {
          row.marks = 60;
        } else if (row.learner.startsWith('Chitra')) {
          row.absent = true;
        }
      }
      try {
        ExamController.saveMarks(paper.Id, sheet.rows);
        Assert.fail('Above maximum');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('between 0 and 50'),
          e.getMessage()
        );
      }
      for (ExamService.MarkRow row : sheet.rows) {
        if (row.learner.startsWith('Asha')) {
          row.marks = 45;
        }
      }
      ExamController.saveMarks(paper.Id, sheet.rows);
      Test.startTest();
      Id assessmentId = ExamController.publishMarks(paper.Id);
      Test.stopTest();
      Course_Assessment__c a = [
        SELECT
          Assessment_Type__c,
          Status__c,
          Max_Score__c,
          Weight__c,
          (SELECT Score__c, Absent__c FROM Results__r)
        FROM Course_Assessment__c
        WHERE Id = :assessmentId
      ];
      Assert.areEqual('Exam', a.Assessment_Type__c, 'Exam assessment');
      Assert.areEqual('Published', a.Status__c, 'Published');
      Assert.areEqual(2, a.Results__r.size(), 'Asha and absent Chitra');
      Assert.areEqual(
        'Results Published',
        exam().Status__c,
        'All papers published'
      );
      Assert.isFalse(ExamService.markSheet(paper.Id).editable, 'Locked');
      try {
        ExamService.saveMarks(paper.Id, sheet.rows);
        Assert.fail('Locked');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('locked'), e.getMessage());
      }
      try {
        ExamService.registerCandidates(exam().Id);
        Assert.fail('Closed');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('results published'),
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void permissionsAreEnforced() {
    System.runAs(TestDataFactory.admin()) {
      ExamService.registerCandidates(exam().Id);
      ExamService.checkEligibility(exam().Id);
      try {
        ExamService.overrideCandidate(
          candidate('Chitra').Id,
          'Medical leave certified'
        );
        Assert.fail('Needs the override permission');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('Eligibility Override'),
          e.getMessage()
        );
      }
    }
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      try {
        ExamController.registerCandidates(exam().Id);
        Assert.fail('Teachers cannot manage exams');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('permission'), e.getMessage());
      }
    }
  }
}
