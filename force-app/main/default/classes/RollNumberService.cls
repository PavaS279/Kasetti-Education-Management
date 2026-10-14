/** Lock-safe, retry-safe allocator for permanent college roll numbers. */
public without sharing class RollNumberService {
  public static String issue(Id programmeEnrolmentId) {
    Programme_Enrolment__c enrolment = [
      SELECT
        Id,
        Roll_Number__c,
        Admission_Year__c,
        Entry_Route__c,
        Campus__r.Campus_Code__c,
        Programme__r.Programme_Code__c,
        Branch__r.Branch_Code__c
      FROM Programme_Enrolment__c
      WHERE Id = :programmeEnrolmentId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (String.isNotBlank(enrolment.Roll_Number__c))
      return enrolment.Roll_Number__c;
    if (
      enrolment.Admission_Year__c == null ||
      String.isBlank(enrolment.Campus__r.Campus_Code__c) ||
      String.isBlank(enrolment.Programme__r.Programme_Code__c) ||
      String.isBlank(enrolment.Branch__r.Branch_Code__c)
    ) {
      throw new AppException(
        'Complete the admission year and roll-number codes before issuing a roll number.'
      );
    }
    String year = String.valueOf(enrolment.Admission_Year__c.intValue());
    year = year.substring(year.length() - 2);
    String band = enrolment.Entry_Route__c == 'Lateral' ? 'L' : 'R';
    String key = String.join(
      new List<String>{
        year,
        enrolment.Campus__r.Campus_Code__c,
        enrolment.Programme__r.Programme_Code__c,
        enrolment.Branch__r.Branch_Code__c,
        band
      },
      '|'
    );
    Roll_Number_Sequence__c sequence = lockOrCreate(key, band);
    Integer serial = sequence.Next_Serial__c.intValue();
    if (serial > sequence.Range_End__c) {
      throw new AppException('Roll-number range full for ' + key + '.');
    }
    String serialText = String.valueOf(serial);
    while (serialText.length() < 3)
      serialText = '0' + serialText;
    String rollNumber =
      AppSettings.getString('Roll_Prefix', 'KT') +
      year +
      enrolment.Campus__r.Campus_Code__c +
      enrolment.Programme__r.Programme_Code__c +
      enrolment.Branch__r.Branch_Code__c +
      serialText;
    sequence.Next_Serial__c = serial + 1;
    Database.update(sequence, AccessLevel.SYSTEM_MODE);
    Database.update(
      new Programme_Enrolment__c(
        Id = enrolment.Id,
        Roll_Number__c = rollNumber,
        Roll_Issued_On__c = Date.today()
      ),
      AccessLevel.SYSTEM_MODE
    );
    return rollNumber;
  }

  private static Roll_Number_Sequence__c lockOrCreate(String key, String band) {
    List<Roll_Number_Sequence__c> existing = [
      SELECT Id, Next_Serial__c, Range_Start__c, Range_End__c
      FROM Roll_Number_Sequence__c
      WHERE Key__c = :key
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (!existing.isEmpty())
      return existing[0];
    List<Integer> range = parseRange(
      AppSettings.getString(
        band == 'L' ? 'Roll_Lateral_Range' : 'Roll_Regular_Range',
        band == 'L' ? '401-999' : '001-400'
      )
    );
    Roll_Number_Sequence__c seed = new Roll_Number_Sequence__c(
      Key__c = key,
      Next_Serial__c = range[0],
      Range_Start__c = range[0],
      Range_End__c = range[1]
    );
    Database.SaveResult saved = Database.insert(
      seed,
      false,
      AccessLevel.SYSTEM_MODE
    );
    if (saved.isSuccess())
      return seed;
    if (saved.getErrors()[0].getStatusCode() != StatusCode.DUPLICATE_VALUE) {
      throw new AppException(saved.getErrors()[0].getMessage());
    }
    return [
      SELECT Id, Next_Serial__c, Range_Start__c, Range_End__c
      FROM Roll_Number_Sequence__c
      WHERE Key__c = :key
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
  }

  @TestVisible
  private static List<Integer> parseRange(String configured) {
    List<String> parts = configured == null
      ? new List<String>()
      : configured.split('-');
    Integer start;
    Integer finish;
    try {
      start = parts.size() == 2 ? Integer.valueOf(parts[0]) : null;
      finish = parts.size() == 2 ? Integer.valueOf(parts[1]) : null;
    } catch (Exception invalid) {
      throw new AppException(
        'The configured roll-number range is invalid: ' + configured + '.'
      );
    }
    if (
      start == null ||
      finish == null ||
      start < 0 ||
      finish > 999 ||
      start > finish
    ) {
      throw new AppException(
        'The configured roll-number range is invalid: ' + configured + '.'
      );
    }
    return new List<Integer>{ start, finish };
  }
}
