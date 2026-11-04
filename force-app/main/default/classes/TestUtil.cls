/** Small helpers for unit tests that do not need database records. */
@IsTest
public class TestUtil {
  private static Integer fakeIdCounter = 1;

  public static Id fakeId(SObjectType objectType) {
    String suffix = String.valueOf(fakeIdCounter++);
    return Id.valueOf(
      objectType.getDescribe().getKeyPrefix() +
        '0'.repeat(12 - suffix.length()) +
        suffix
    );
  }
}
