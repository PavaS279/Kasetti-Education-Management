@IsTest
private class PricingServiceTest {
  private static Fee_Price__c price(
    Id courseId,
    Id branchId,
    String feeType,
    String mode,
    Decimal amount,
    Date fromDate,
    Date toDate
  ) {
    return new Fee_Price__c(
      Learning_Course__c = courseId,
      Branch__c = branchId,
      Fee_Type__c = feeType,
      Delivery_Mode__c = mode,
      Billing_Frequency__c = 'One-time',
      Amount__c = amount,
      Effective_From__c = fromDate,
      Effective_To__c = toDate,
      Active__c = true
    );
  }

  private static PricingService.QuoteRequest request(
    Id courseId,
    Id branchId,
    String mode,
    String code
  ) {
    PricingService.QuoteRequest r = new PricingService.QuoteRequest();
    r.courseId = courseId;
    r.branchId = branchId;
    r.deliveryMode = mode;
    r.discountCode = code;
    return r;
  }

  private class Fixture {
    LearningCourse course;
    Branch__c branchA;
    Branch__c branchB;
  }

  private static Fixture fixture() {
    Fixture f = new Fixture();
    f.course = TestDataFactory.createCourse('Physics');
    f.branchA = TestDataFactory.createBranch(); // tax 18%
    f.branchB = TestDataFactory.buildBranch();
    f.branchB.Tax_Rate__c = 0;
    insert f.branchB;
    Date today = Date.today();
    insert new List<Fee_Price__c>{
      price(f.course.Id, null, 'Tuition', null, 1000, today.addDays(-30), null),
      price(
        f.course.Id,
        f.branchA.Id,
        'Tuition',
        null,
        1200,
        today.addDays(-30),
        null
      ),
      price(
        f.course.Id,
        null,
        'Tuition',
        'Online',
        900,
        today.addDays(-30),
        null
      ),
      price(
        f.course.Id,
        null,
        'Admission',
        null,
        500,
        today.addDays(-30),
        null
      ),
      price(f.course.Id, null, 'Materials', null, 250, today.addDays(10), null)
    };
    Fee_Price__c inactive = price(
      f.course.Id,
      null,
      'Assessment',
      null,
      99,
      today.addDays(-30),
      null
    );
    inactive.Active__c = false;
    insert inactive;
    return f;
  }

  @IsTest
  static void resolvesMostSpecificPriceAndAppliesTax() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      PricingService.Quote branchQuote = PricingController.getQuote(
        request(f.course.Id, f.branchA.Id, 'Classroom', null)
      );
      Assert.areEqual(
        2,
        branchQuote.lines.size(),
        'Admission and tuition; future and inactive prices excluded'
      );
      Assert.areEqual(
        'Admission',
        branchQuote.lines[0].feeType,
        'Admission listed first'
      );
      Assert.areEqual(
        1200,
        branchQuote.lines[1].unitAmount,
        'Branch-specific tuition wins'
      );
      Assert.areEqual(1700, branchQuote.subtotal, 'Subtotal');
      Assert.areEqual(306, branchQuote.taxTotal, '18% tax');
      Assert.areEqual(2006, branchQuote.grandTotal, 'Grand total');

      PricingService.Quote onlineQuote = PricingService.quote(
        request(f.course.Id, f.branchB.Id, 'Online', null)
      );
      Assert.areEqual(
        900,
        onlineQuote.lines[1].unitAmount,
        'Mode-specific tuition wins over generic'
      );
      Assert.areEqual(1400, onlineQuote.grandTotal, 'No tax at branch B');

      PricingService.QuoteRequest future = request(
        f.course.Id,
        f.branchB.Id,
        'Classroom',
        null
      );
      future.onDate = Date.today().addDays(15);
      Assert.areEqual(
        3,
        PricingService.quote(future).lines.size(),
        'Materials becomes effective later'
      );
    }
  }

  @IsTest
  static void appliesPercentageAndFixedDiscounts() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      insert new List<Discount__c>{
        new Discount__c(
          Name = 'Sibling',
          Code__c = 'sibling10',
          Discount_Type__c = 'Percentage',
          Value__c = 10,
          Fee_Type__c = 'Tuition',
          Active__c = true
        ),
        new Discount__c(
          Name = 'Welcome',
          Code__c = 'WELCOME300',
          Discount_Type__c = 'Fixed Amount',
          Value__c = 600,
          Active__c = true,
          Requires_Approval__c = true
        )
      };
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Discount__c WHERE Code__c = 'SIBLING10'],
        'Codes are stored in upper case'
      );

      PricingService.Quote sibling = PricingService.quote(
        request(f.course.Id, f.branchB.Id, 'Classroom', ' Sibling10 ')
      );
      Assert.areEqual(
        0,
        sibling.lines[0].discountAmount,
        'Admission not discounted'
      );
      Assert.areEqual(100, sibling.lines[1].discountAmount, '10% of tuition');
      Assert.areEqual(1400, sibling.grandTotal, '1500 - 100');
      Assert.isFalse(sibling.approvalRequired, 'No approval needed');

      PricingService.Quote welcome = PricingService.quote(
        request(f.course.Id, f.branchA.Id, 'Classroom', 'WELCOME300')
      );
      Assert.areEqual(
        500,
        welcome.lines[0].discountAmount,
        'Fixed amount fills the first line up to its value'
      );
      Assert.areEqual(
        100,
        welcome.lines[1].discountAmount,
        'Remainder applied to the next line'
      );
      Assert.areEqual(600, welcome.discountTotal, 'Whole fixed amount used');
      Assert.isTrue(welcome.approvalRequired, 'Approval flag surfaced');
      Assert.areEqual(
        PricingService.round((1700 - 600) * 1.18),
        welcome.grandTotal,
        'Tax after discount'
      );
    }
  }

  @IsTest
  static void rejectsInvalidDiscounts() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      LearningCourse otherCourse = TestDataFactory.createCourse('Chemistry');
      insert new List<Discount__c>{
        new Discount__c(
          Name = 'Off',
          Code__c = 'OFF',
          Discount_Type__c = 'Percentage',
          Value__c = 5,
          Active__c = false
        ),
        new Discount__c(
          Name = 'Old',
          Code__c = 'OLD',
          Discount_Type__c = 'Percentage',
          Value__c = 5,
          Active__c = true,
          Valid_To__c = Date.today().addDays(-1)
        ),
        new Discount__c(
          Name = 'Used',
          Code__c = 'USED',
          Discount_Type__c = 'Percentage',
          Value__c = 5,
          Active__c = true,
          Max_Uses__c = 1
        ),
        new Discount__c(
          Name = 'Chem',
          Code__c = 'CHEM',
          Discount_Type__c = 'Percentage',
          Value__c = 5,
          Active__c = true,
          Applies_To_Course__c = otherCourse.Id
        ),
        new Discount__c(
          Name = 'BranchA',
          Code__c = 'BRA',
          Discount_Type__c = 'Percentage',
          Value__c = 5,
          Active__c = true,
          Applies_To_Branch__c = f.branchA.Id
        ),
        new Discount__c(
          Name = 'Exam',
          Code__c = 'EXAM',
          Discount_Type__c = 'Percentage',
          Value__c = 5,
          Active__c = true,
          Fee_Type__c = 'Assessment'
        )
      };
      PricingService.recordUsage(
        [SELECT Id FROM Discount__c WHERE Code__c = 'USED'].Id
      );
      Assert.areEqual(
        1,
        [SELECT Times_Used__c FROM Discount__c WHERE Code__c = 'USED']
        .Times_Used__c,
        'Usage recorded'
      );

      Map<String, String> expected = new Map<String, String>{
        'NOPE' => 'does not exist',
        'OFF' => 'inactive',
        'OLD' => 'not valid',
        'USED' => 'usage limit',
        'CHEM' => 'course',
        'BRA' => 'branch',
        'EXAM' => 'does not apply to any fee'
      };
      for (String code : expected.keySet()) {
        PricingService.Quote q = PricingService.quote(
          request(f.course.Id, f.branchB.Id, 'Classroom', code)
        );
        Assert.isNull(q.discountId, code + ' must not apply');
        Assert.isTrue(
          String.join(q.warnings, ' ').contains(expected.get(code)),
          code + ': ' + q.warnings
        );
      }
      Assert.isNotNull(
        PricingService.quote(
            request(f.course.Id, f.branchA.Id, 'Classroom', 'BRA')
          )
          .discountId,
        'Branch-scoped code works at its branch'
      );
    }
  }

  @IsTest
  static void preventsOverlappingPrices() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Database.SaveResult overlap = Database.insert(
        price(f.course.Id, null, 'Tuition', null, 1100, Date.today(), null),
        false
      );
      Assert.isFalse(
        overlap.isSuccess(),
        'Overlapping global tuition rejected'
      );

      Fee_Price__c current = [
        SELECT Id
        FROM Fee_Price__c
        WHERE
          Learning_Course__c = :f.course.Id
          AND Fee_Type__c = 'Tuition'
          AND Branch__c = NULL
          AND Delivery_Mode__c = NULL
      ];
      PricingController.endPrice(current.Id, Date.today().addDays(30));
      insert price(
        f.course.Id,
        null,
        'Tuition',
        null,
        1100,
        Date.today().addDays(31),
        null
      );
      List<Fee_Price__c> batch = new List<Fee_Price__c>{
        price(
          f.course.Id,
          f.branchB.Id,
          'Tuition',
          null,
          800,
          Date.today(),
          Date.today().addDays(5)
        ),
        price(
          f.course.Id,
          f.branchB.Id,
          'Tuition',
          null,
          850,
          Date.today().addDays(3),
          null
        )
      };
      List<Database.SaveResult> results = Database.insert(batch, false);
      Assert.isTrue(results[0].isSuccess(), 'First price in batch saved');
      Assert.isFalse(
        results[1].isSuccess(),
        'Overlap within the same batch rejected'
      );
      Assert.areEqual(
        8,
        PricingController.getCoursePrices(f.course.Id).size(),
        'All saved prices listed'
      );
    }
  }

  @IsTest
  static void handlesMissingPricesAndBadRequests() {
    System.runAs(TestDataFactory.admin()) {
      LearningCourse course = TestDataFactory.createCourse('Unpriced');
      PricingService.Quote q = PricingService.quote(
        request(course.Id, null, null, null)
      );
      Assert.areEqual(0, q.grandTotal, 'Nothing to charge');
      Assert.isTrue(
        q.warnings[0].contains('No active price'),
        'Warns about missing price'
      );
      try {
        PricingController.getQuote(new PricingService.QuoteRequest());
        Assert.fail('Course is required');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('course'), e.getMessage());
      }
    }
  }

  @IsTest
  static void financeManagesPricesCounsellorOnlyQuotes() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      LearningCourse course = TestDataFactory.createCourse('Biology');
      User finance = TestDataFactory.createUserWithLicense(
        TestDataFactory.persona('KEM_Finance')
      );
      User counsellor = TestDataFactory.createCounsellor(branch.Id);
      System.runAs(finance) {
        Database.insert(
          price(course.Id, null, 'Tuition', null, 2000, Date.today(), null),
          AccessLevel.USER_MODE
        );
      }
      System.runAs(counsellor) {
        Assert.areEqual(
          2000,
          PricingController.getQuote(request(course.Id, branch.Id, null, null))
            .subtotal,
          'Counsellor can quote'
        );
        try {
          Database.insert(
            price(course.Id, null, 'Admission', null, 100, Date.today(), null),
            AccessLevel.USER_MODE
          );
          Assert.fail('Counsellor must not create prices');
        } catch (Exception e) {
          Assert.isNotNull(e.getMessage(), 'Denied');
        }
      }
    }
  }
}
