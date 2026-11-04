/**
 * Flags enquiries that match an open enquiry or an existing learner or
 * guardian on email or phone. Flagging never blocks capture: genuine siblings
 * share guardian contact details, so a counsellor reviews each match.
 *
 * Detection is a data-integrity check that must see every record regardless
 * of who captures the enquiry (website integration, counsellor, branch
 * manager), so it runs in system mode without sharing. Only record names and
 * IDs are written to the flagged enquiry.
 */
public without sharing class EnquiryDuplicateService {
  public static void flagDuplicates(List<Lead> enquiries) {
    Set<String> emails = new Set<String>();
    Set<String> phones = new Set<String>();
    for (Lead enquiry : enquiries) {
      addIfPresent(emails, enquiry.Email);
      addIfPresent(phones, enquiry.Phone);
      addIfPresent(phones, enquiry.MobilePhone);
    }
    if (emails.isEmpty() && phones.isEmpty()) {
      return;
    }
    List<Lead> openMatches = [
      SELECT Id, Name, Email, Phone, MobilePhone
      FROM Lead
      WHERE
        IsConverted = FALSE
        AND (Email IN :emails
        OR Phone IN :phones
        OR MobilePhone IN :phones)
      WITH SYSTEM_MODE
      LIMIT 500
    ];
    List<Account> personMatches = [
      SELECT Id, Name, PersonEmail, Phone, PersonMobilePhone
      FROM Account
      WHERE
        IsPersonAccount = TRUE
        AND (PersonEmail IN :emails
        OR Phone IN :phones
        OR PersonMobilePhone IN :phones)
      WITH SYSTEM_MODE
      LIMIT 500
    ];
    for (Lead enquiry : enquiries) {
      List<String> details = new List<String>();
      for (Lead other : openMatches) {
        if (
          other.Id != enquiry.Id &&
          matches(
            enquiry,
            other.Email,
            new List<String>{ other.Phone, other.MobilePhone }
          )
        ) {
          details.add('Open enquiry ' + other.Name + ' (' + other.Id + ')');
        }
      }
      for (Account person : personMatches) {
        if (
          matches(
            enquiry,
            person.PersonEmail,
            new List<String>{ person.Phone, person.PersonMobilePhone }
          )
        ) {
          details.add(
            'Existing person ' + person.Name + ' (' + person.Id + ')'
          );
        }
      }
      enquiry.Possible_Duplicate__c = !details.isEmpty();
      enquiry.Duplicate_Details__c = details.isEmpty()
        ? null
        : String.join(details, '\n').abbreviate(255);
    }
  }

  private static Boolean matches(
    Lead enquiry,
    String email,
    List<String> phones
  ) {
    if (
      String.isNotBlank(enquiry.Email) && enquiry.Email.equalsIgnoreCase(email)
    ) {
      return true;
    }
    for (String phone : phones) {
      if (
        String.isNotBlank(phone) &&
        (phone == enquiry.Phone ||
        phone == enquiry.MobilePhone)
      ) {
        return true;
      }
    }
    return false;
  }

  private static void addIfPresent(Set<String> values, String value) {
    if (String.isNotBlank(value)) {
      values.add(value);
    }
  }
}
