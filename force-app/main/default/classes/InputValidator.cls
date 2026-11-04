/**
 * Shared rules for data people type in: names, email addresses, phone numbers,
 * dates of birth and academic results. Every entry point (public enquiry,
 * desk admission, enquiry API) uses these so the same value is accepted or
 * refused everywhere. Each method throws AppException with a message fit to
 * show the person who typed the value.
 */
public with sharing class InputValidator {
  /** Letters (any script), spaces, dot, apostrophe and hyphen; starts with a letter. */
  private static final String NAME_PATTERN = '^\\p{L}[\\p{L}\\p{M} .\'-]*$';
  private static final String EMAIL_PATTERN = '^[A-Za-z0-9._%+\'-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}$';
  /** Digits with an optional leading +, and spaces, brackets or hyphens between them. */
  private static final String PHONE_PATTERN = '^\\+?[0-9][0-9 ()-]*$';
  public static final Integer MIN_PHONE_DIGITS = 10;
  public static final Integer MAX_PHONE_DIGITS = 15;
  public static final Integer EARLIEST_RESULT_YEAR = 1980;

  public static void name(String value, String label) {
    if (String.isBlank(value)) {
      return;
    }
    String v = value.trim();
    if (!Pattern.matches(NAME_PATTERN, v) || v.contains('  ')) {
      throw new AppException(
        label + ' can contain only letters, spaces, apostrophes and hyphens.'
      );
    }
  }

  public static void email(String value, String label) {
    if (String.isBlank(value)) {
      return;
    }
    String v = value.trim();
    if (
      !Pattern.matches(EMAIL_PATTERN, v) ||
      v.contains('..') ||
      v.startsWith('.') ||
      v.substringBefore('@').endsWith('.')
    ) {
      throw new AppException(
        label + ' is not a valid email address (for example name@example.com).'
      );
    }
  }

  public static void phone(String value, String label) {
    if (String.isBlank(value)) {
      return;
    }
    String v = value.trim();
    Integer digits = v.replaceAll('[^0-9]', '').length();
    if (
      !Pattern.matches(PHONE_PATTERN, v) ||
      digits < MIN_PHONE_DIGITS ||
      digits > MAX_PHONE_DIGITS
    ) {
      throw new AppException(
        label +
          ' is not a valid phone number: use ' +
          MIN_PHONE_DIGITS +
          ' to ' +
          MAX_PHONE_DIGITS +
          ' digits, for example 9876543210 or +91 98765 43210.'
      );
    }
  }

  /** Not in the future and no more than 120 years ago; at least minAge years old when given. */
  public static void birthdate(Date value, Integer minAge, String label) {
    if (value == null) {
      return;
    }
    Date today = Date.today();
    if (value > today || value < today.addYears(-120)) {
      throw new AppException('Enter a valid ' + label + '.');
    }
    if (minAge != null && value > today.addYears(-minAge)) {
      throw new AppException(
        'The ' + label + ' gives an age under ' + minAge + '; check it.'
      );
    }
  }

  /** A percentage from 0 to 100 with at most two decimal places. */
  public static Boolean isPercentage(Decimal value) {
    return value != null &&
      value >= 0 &&
      value <= 100 &&
      value.setScale(2, RoundingMode.DOWN) == value;
  }

  /** A year a result could have been earned: not before 1980 and not after this year. */
  public static Boolean isResultYear(Integer value) {
    return value == null ||
      (value >= EARLIEST_RESULT_YEAR &&
      value <= Date.today().year());
  }
}
