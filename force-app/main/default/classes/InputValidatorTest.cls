@IsTest
private class InputValidatorTest {
  private static Boolean refused(String kind, String value) {
    try {
      if (kind == 'name') {
        InputValidator.name(value, 'Name');
      } else if (kind == 'email') {
        InputValidator.email(value, 'Email');
      } else {
        InputValidator.phone(value, 'Phone');
      }
      return false;
    } catch (AppException e) {
      return true;
    }
  }

  @IsTest
  static void namesAreLettersOnly() {
    for (
      String ok : new List<String>{
        'Kavya',
        'D\'Souza',
        'Anne-Marie',
        'K. Rao',
        'ಕಾವ್ಯ',
        null,
        ''
      }
    ) {
      Assert.isFalse(refused('name', ok), 'value: ' + ok);
    }
    for (
      String bad : new List<String>{
        'Kavya123',
        '<script>',
        '-Rao',
        'Rao@',
        '12',
        'Kavya  Rao'
      }
    ) {
      Assert.isTrue(refused('name', bad), 'value: ' + bad);
    }
  }

  @IsTest
  static void emailsMustBeAddresses() {
    for (
      String ok : new List<String>{
        'kavya.rao@example.com',
        'a+b@mail.co.in',
        null
      }
    ) {
      Assert.isFalse(refused('email', ok), 'value: ' + ok);
    }
    for (
      String bad : new List<String>{
        'kavya',
        'kavya@',
        'a@b',
        'a@b.c',
        'a..b@x.com',
        'a.@x.com',
        'a b@x.com',
        'a@@x.com'
      }
    ) {
      Assert.isTrue(refused('email', bad), 'value: ' + bad);
    }
  }

  @IsTest
  static void phonesNeedTenToFifteenDigits() {
    for (
      String ok : new List<String>{
        '9876543210',
        '+91 98765 43210',
        '+91-80-1234-5678',
        null
      }
    ) {
      Assert.isFalse(refused('phone', ok), 'value: ' + ok);
    }
    for (
      String bad : new List<String>{
        '12345',
        'abc9876543210',
        '98765x43210',
        '+91 98765 43210 12345',
        '++919876543210'
      }
    ) {
      Assert.isTrue(refused('phone', bad), 'value: ' + bad);
    }
  }

  @IsTest
  static void birthdatesAndResults() {
    InputValidator.birthdate(Date.today().addYears(-17), 14, 'date of birth');
    for (
      Date bad : new List<Date>{
        Date.today().addDays(1),
        Date.today().addYears(-130),
        Date.today().addYears(-10)
      }
    ) {
      try {
        InputValidator.birthdate(bad, 14, 'date of birth');
        Assert.fail('Refused: ' + bad);
      } catch (AppException e) {
        Assert.isTrue(true);
      }
    }
    Assert.isTrue(InputValidator.isPercentage(91.25));
    Assert.isFalse(InputValidator.isPercentage(91.255));
    Assert.isFalse(InputValidator.isPercentage(101));
    Assert.isFalse(InputValidator.isPercentage(-1));
    Assert.isTrue(InputValidator.isResultYear(null));
    Assert.isFalse(InputValidator.isResultYear(Date.today().year() + 1));
    Assert.isFalse(InputValidator.isResultYear(1970));
  }

  private static CollegeAdmissionController.Qualification result(
    String level,
    Decimal pct,
    Integer year
  ) {
    CollegeAdmissionController.Qualification q = new CollegeAdmissionController.Qualification();
    q.level = level;
    q.percentage = pct;
    q.year = year;
    return q;
  }

  private static CollegeAdmissionController.Entrance rank(
    String exam,
    Integer value
  ) {
    CollegeAdmissionController.Entrance e = new CollegeAdmissionController.Entrance();
    e.exam = exam;
    e.rank = value;
    return e;
  }

  private static String marksError(
    List<CollegeAdmissionController.Qualification> qs,
    List<CollegeAdmissionController.Entrance> es
  ) {
    try {
      CollegePublicController.validateMarks(qs, es);
      return null;
    } catch (AppException e) {
      return e.getMessage();
    }
  }

  @IsTest
  static void marksRefuseDuplicatesAndBadValues() {
    Integer thisYear = Date.today().year();
    Assert.isNull(
      marksError(
        new List<CollegeAdmissionController.Qualification>{
          result('SSLC', 91, thisYear - 2),
          result('PUC', 92.5, thisYear)
        },
        new List<CollegeAdmissionController.Entrance>{ rank('KCET', 12400) }
      )
    );
    Assert.isTrue(
      marksError(
          new List<CollegeAdmissionController.Qualification>{
            result('SSLC', 91, null),
            result('SSLC', 80, null)
          },
          null
        )
        .contains('once')
    );
    Assert.isTrue(
      marksError(
          new List<CollegeAdmissionController.Qualification>{
            result('SSLC', 91, null)
          },
          new List<CollegeAdmissionController.Entrance>{
            rank('KCET', 1),
            rank('KCET', 2)
          }
        )
        .contains('once')
    );
    Assert.isNotNull(
      marksError(
        new List<CollegeAdmissionController.Qualification>{
          result('SSLC', 91.555, null)
        },
        null
      )
    );
    Assert.isNotNull(
      marksError(
        new List<CollegeAdmissionController.Qualification>{
          result('SSLC', 91, thisYear + 1)
        },
        null
      )
    );
    Assert.isNotNull(
      marksError(
        null,
        new List<CollegeAdmissionController.Entrance>{ rank('KCET', 0) }
      )
    );
  }
}
