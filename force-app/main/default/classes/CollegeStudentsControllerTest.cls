@IsTest
private class CollegeStudentsControllerTest {
  @TestSetup
  static void setup() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(5, 7);
    MessageService.disabled = true;
    DocumentService.suppressJobs = true;
    System.runAs(fixture.dean) {
      // One student enrolled (fee paid), one admitted with the fee pending.
      CollegeTestFactory.enrolPaid(fixture, fixture.admission);
      InterviewService.admit(
        CollegeTestFactory.admission(fixture, 'Pending').Id
      );
    }
  }

  private static User dean() {
    return [
      SELECT Id
      FROM User
      WHERE
        Id IN (
          SELECT AssigneeId
          FROM PermissionSetAssignment
          WHERE PermissionSet.Name = 'KEM_College_Dean'
        )
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  @IsTest
  static void deanSeesEnrolledAndFeePendingStudents() {
    CollegeStudentsController.StudentList students;
    System.runAs(dean()) {
      Test.startTest();
      students = CollegeStudentsController.getStudents('current');
      Test.stopTest();
    }
    Assert.areEqual(2, students.students.size());
    Assert.areEqual(1, students.summary.enrolled);
    Assert.areEqual(1, students.summary.feePending);
    Assert.areEqual(1, students.summary.withoutSection, 'Not yet in a section');
    Assert.areEqual(1, students.campuses.size());
    CollegeStudentsController.Student enrolled;
    CollegeStudentsController.Student pending;
    for (CollegeStudentsController.Student s : students.students) {
      if (s.status == 'Enrolled') {
        enrolled = s;
      } else {
        pending = s;
      }
    }
    Assert.isNotNull(enrolled.rollNumber, 'Roll number shown');
    Assert.areEqual(0, enrolled.feesDue, 'Paid in full');
    Assert.isNull(pending.rollNumber);
    Assert.isTrue(pending.feesDue > 0, 'The unpaid invoice is due');
    Assert.areEqual(pending.feesDue, students.summary.feesDue);
    Assert.isNotNull(pending.paymentDueBy);
    Assert.isFalse(enrolled.hasPortal);
  }

  @IsTest
  static void deskSeesEnrolmentsTheyDidNotCreate() {
    User desk = TestDataFactory.createUserWithLicense(
      new List<String>{
        'KEM_Admissions_Counsellor',
        'KEM_Admissions_Counsellor_Edu',
        'KEM_College_Admissions'
      }
    );
    System.runAs(desk) {
      Test.startTest();
      CollegeStudentsController.StudentList all = CollegeStudentsController.getStudents(
        'all'
      );
      Test.stopTest();
      Assert.areEqual(2, all.students.size());
    }
  }

  @IsTest
  static void othersAreRefused() {
    User teacher = TestDataFactory.createUserWithLicense(
      new List<String>{ 'KEM_Teacher', 'KEM_Teacher_Edu' }
    );
    System.runAs(teacher) {
      try {
        CollegeStudentsController.getStudents('current');
        Assert.fail('Only the desk and the Dean see the students.');
      } catch (AuraHandledException expected) {
        Assert.isTrue(true);
      }
    }
  }
}
