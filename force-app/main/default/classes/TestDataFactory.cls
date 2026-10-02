/**
 * Builds test records for all Kasetti Education Management tests.
 * build* methods return unsaved records; create* methods insert them.
 */
@IsTest
public class TestDataFactory {
  private static Integer counter = 0;

  public static String unique(String prefix) {
    counter++;
    return prefix + '-' + counter + '-' + Crypto.getRandomInteger();
  }

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

  /** Creates an active standard user and assigns the given permission sets. */
  public static User createUser(List<String> permissionSetNames) {
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
    assignPermissionSets(user.Id, permissionSetNames);
    return user;
  }

  public static void assignPermissionSets(
    Id userId,
    List<String> permissionSetNames
  ) {
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
}
