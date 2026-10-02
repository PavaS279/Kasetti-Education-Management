/**
 * Builds test records for all Kasetti Education Management tests.
 * build* methods return unsaved records; create* methods insert them.
 *
 * Setup objects (users, licences, permission set assignments) are created as
 * the deploying administrator (DEPLOYER). Business records are created by the
 * calling test, which normally runs as admin() so that tests exercise the
 * KEM permission sets deployed together with new fields.
 */
@IsTest
public class TestDataFactory {
  private static final User DEPLOYER = new User(Id = UserInfo.getUserId());
  private static Integer counter = 0;
  private static User adminUser;

  public static String unique(String prefix) {
    counter++;
    return prefix + '-' + counter + '-' + Crypto.getRandomInteger();
  }

  // ---------------------------------------------------------------- users

  /** Permission sets that make up a persona: the base set and its Education Cloud set. */
  public static List<String> persona(String baseName) {
    return new List<String>{ baseName, baseName + '_Edu' };
  }

  /** Returns a user holding KEM_Administrator and the Education Cloud licence. */
  public static User admin() {
    if (adminUser == null) {
      createReferenceData();
      adminUser = createUserWithLicense(persona('KEM_Administrator'));
    }
    return adminUser;
  }

  /**
   * Creates org configuration data that tests cannot see (no SeeAllData):
   * the Guardian/Child party role relation used for guardian links.
   */
  public static void createReferenceData() {
    System.runAs(DEPLOYER) {
      if (
        [
          SELECT COUNT()
          FROM PartyRoleRelation
          WHERE
            RoleName = 'Guardian'
            AND RelationshipObjectName = 'Contact_Contact_Relationship'
        ] == 0
      ) {
        insert new PartyRoleRelation(
          Name = 'Guardian',
          RoleName = 'Guardian',
          RelatedRoleName = 'Child',
          RelationshipObjectName = 'Contact_Contact_Relationship',
          ShouldCreaInversRoleAuto = false
        );
      }
    }
  }

  /** Creates an active Standard User and assigns the given permission sets. */
  public static User createUser(List<String> permissionSetNames) {
    User user;
    System.runAs(DEPLOYER) {
      user = insertUser();
      assignPermissionSets(user.Id, permissionSetNames);
    }
    return user;
  }

  /** Creates a user with the Education Cloud licence, then the permission sets. */
  public static User createUserWithLicense(List<String> permissionSetNames) {
    User user;
    System.runAs(DEPLOYER) {
      user = insertUser();
      assignEducationLicense(user.Id);
      assignPermissionSets(user.Id, permissionSetNames);
    }
    return user;
  }

  /** Creates an admissions counsellor assigned to the branch through Branch_Staff__c. */
  public static User createCounsellor(Id branchId) {
    User counsellor = createUserWithLicense(
      persona('KEM_Admissions_Counsellor')
    );
    assignToBranch(counsellor.Id, branchId, 'Admissions Counsellor');
    return counsellor;
  }

  public static Branch_Staff__c assignToBranch(
    Id userId,
    Id branchId,
    String role
  ) {
    Branch_Staff__c staff = new Branch_Staff__c(
      Branch__c = branchId,
      User__c = userId,
      Role__c = role
    );
    insert staff;
    return staff;
  }

  public static void assignPermissionSets(
    Id userId,
    List<String> permissionSetNames
  ) {
    if (permissionSetNames == null || permissionSetNames.isEmpty()) {
      return;
    }
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet ps : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN :permissionSetNames
    ]) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = userId,
          PermissionSetId = ps.Id
        )
      );
    }
    insert assignments;
  }

  /** Assigns the Education Cloud staff licence, required for Education Cloud objects. */
  public static void assignEducationLicense(Id userId) {
    List<PermissionSetLicense> licenses = [
      SELECT Id
      FROM PermissionSetLicense
      WHERE DeveloperName = 'EducationCloudAccessPsl'
      LIMIT 1
    ];
    if (!licenses.isEmpty()) {
      insert new PermissionSetLicenseAssign(
        AssigneeId = userId,
        PermissionSetLicenseId = licenses[0].Id
      );
    }
  }

  private static User insertUser() {
    Profile profile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    String key = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    User user = new User(
      Alias = ('u' + key).left(8),
      Email = 'kem.test' + key + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Test ' + key,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_IN',
      ProfileId = profile.Id,
      TimeZoneSidKey = 'Asia/Kolkata',
      Username = 'kem.test' + key + '@kasetti.test'
    );
    insert user;
    return user;
  }

  // ------------------------------------------------------------- branches

  public static Branch__c buildBranch() {
    return new Branch__c(
      Name = 'Test Branch ' + counter,
      Branch_Code__c = unique('BR').left(20),
      Active__c = true,
      Invoice_Due_Days__c = 10,
      Tax_Rate__c = 18,
      Attendance_Threshold__c = 80,
      Invoice_Prefix__c = 'TST'
    );
  }

  public static Branch__c createBranch() {
    Branch__c branch = buildBranch();
    insert branch;
    return branch;
  }

  public static Room__c createRoom(Id branchId, Integer capacity) {
    Room__c room = new Room__c(
      Name = unique('Room'),
      Branch__c = branchId,
      Capacity__c = capacity,
      Room_Type__c = 'Classroom'
    );
    insert room;
    return room;
  }

  // ---------------------------------------------------- enquiries, courses

  public static Lead buildEnquiry(Id branchId) {
    String key = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    return new Lead(
      FirstName = 'Asha',
      LastName = 'Learner' + key,
      Email = 'asha' + key + '@example.com',
      MobilePhone = '+9190' + key.left(8),
      Branch__c = branchId,
      Enquiry_Channel__c = 'Website',
      Guardian_First_Name__c = 'Ravi',
      Guardian_Last_Name__c = 'Guardian' + key,
      Guardian_Email__c = 'ravi' + key + '@example.com',
      Guardian_Phone__c = '+9180' + key.left(8),
      Guardian_Relationship__c = 'Father',
      Learner_Birthdate__c = Date.today().addYears(-12)
    );
  }

  public static LearningCourse createCourse(String name) {
    Learning learning = new Learning(
      Name = name,
      Type = 'LearningCourse',
      IsActive = true
    );
    insert learning;
    LearningCourse course = new LearningCourse(
      Name = name,
      LearningId = learning.Id,
      External_ID__c = unique('CRS')
    );
    insert course;
    return course;
  }

  /** Creates an open class for a course at a branch. */
  public static CourseOffering createOffering(
    Id courseId,
    Id branchId,
    Integer capacity
  ) {
    CourseOffering offering = new CourseOffering(
      Name = unique('Class').left(80),
      LearningCourseId = courseId,
      Branch__c = branchId,
      EnrollmentCapacity = capacity,
      Delivery_Mode__c = 'Classroom',
      Class_Status__c = 'Open',
      StartDate = DateTime.newInstance(
        Date.today().addDays(-7),
        Time.newInstance(9, 0, 0, 0)
      ),
      EndDate = DateTime.newInstance(
        Date.today().addDays(90),
        Time.newInstance(17, 0, 0, 0)
      )
    );
    insert offering;
    return offering;
  }
}
