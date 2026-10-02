/**
 * Resolves course prices and builds fee quotes.
 *
 * Price resolution (per fee type and billing frequency): active prices for the
 * course effective on the quote date; a branch-specific price beats a global
 * one, then a delivery-mode-specific price beats a generic one. Discounts are
 * validated (active, dates, usage, scope) and applied to eligible lines; tax is
 * the branch policy rate applied after discount. Amounts round half-up to 2dp.
 */
public with sharing class PricingService {
  public class QuoteRequest {
    @AuraEnabled
    public Id courseId { get; set; }
    @AuraEnabled
    public Id branchId { get; set; }
    @AuraEnabled
    public String deliveryMode { get; set; }
    @AuraEnabled
    public Date onDate { get; set; }
    @AuraEnabled
    public String discountCode { get; set; }
  }

  public class QuoteLine {
    @AuraEnabled
    public Id feePriceId;
    @AuraEnabled
    public String feeType;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String frequency;
    @AuraEnabled
    public Decimal unitAmount = 0;
    @AuraEnabled
    public Decimal discountAmount = 0;
    @AuraEnabled
    public Decimal taxRate = 0;
    @AuraEnabled
    public Decimal taxAmount = 0;
    @AuraEnabled
    public Decimal total = 0;
  }

  public class Quote {
    @AuraEnabled
    public List<QuoteLine> lines = new List<QuoteLine>();
    @AuraEnabled
    public Decimal subtotal = 0;
    @AuraEnabled
    public Decimal discountTotal = 0;
    @AuraEnabled
    public Decimal taxTotal = 0;
    @AuraEnabled
    public Decimal grandTotal = 0;
    @AuraEnabled
    public Id discountId;
    @AuraEnabled
    public String discountCode;
    @AuraEnabled
    public Boolean approvalRequired = false;
    @AuraEnabled
    public List<String> warnings = new List<String>();
  }

  public static Quote quote(QuoteRequest request) {
    if (request == null || request.courseId == null) {
      throw new AppException('Select a course to price.');
    }
    Date onDate = request.onDate == null ? Date.today() : request.onDate;
    Branch__c branch = loadBranch(request.branchId);
    Decimal taxRate = new BranchPolicy(branch).taxRate();

    Quote result = new Quote();
    for (
      Fee_Price__c price : resolvePrices(
        request.courseId,
        request.branchId,
        request.deliveryMode,
        onDate
      )
    ) {
      QuoteLine line = new QuoteLine();
      line.feePriceId = price.Id;
      line.feeType = price.Fee_Type__c;
      line.frequency = price.Billing_Frequency__c;
      line.description = String.isBlank(price.Description__c)
        ? price.Learning_Course__r.Name + ' — ' + price.Fee_Type__c
        : price.Description__c;
      line.unitAmount = price.Amount__c;
      line.taxRate = taxRate;
      result.lines.add(line);
    }
    if (result.lines.isEmpty()) {
      result.warnings.add(
        'No active price is set for this course on ' + onDate.format() + '.'
      );
    }
    applyDiscount(result, request, onDate);
    for (QuoteLine line : result.lines) {
      Decimal taxable = line.unitAmount - line.discountAmount;
      line.taxAmount = round(taxable * line.taxRate);
      line.total = round(taxable + line.taxAmount);
      result.subtotal += line.unitAmount;
      result.discountTotal += line.discountAmount;
      result.taxTotal += line.taxAmount;
      result.grandTotal += line.total;
    }
    return result;
  }

  /** Most specific active price per fee type and frequency. */
  public static List<Fee_Price__c> resolvePrices(
    Id courseId,
    Id branchId,
    String deliveryMode,
    Date onDate
  ) {
    Map<String, Fee_Price__c> best = new Map<String, Fee_Price__c>();
    Map<String, Integer> bestScore = new Map<String, Integer>();
    for (Fee_Price__c price : [
      SELECT
        Id,
        Name,
        Fee_Type__c,
        Billing_Frequency__c,
        Amount__c,
        Branch__c,
        Delivery_Mode__c,
        Description__c,
        Effective_From__c,
        Effective_To__c,
        Learning_Course__c,
        Learning_Course__r.Name
      FROM Fee_Price__c
      WHERE
        Learning_Course__c = :courseId
        AND Active__c = TRUE
        AND Effective_From__c <= :onDate
        AND (Effective_To__c = NULL
        OR Effective_To__c >= :onDate)
        AND (Branch__c = NULL
        OR Branch__c = :branchId)
      WITH USER_MODE
      ORDER BY Effective_From__c DESC
    ]) {
      if (
        price.Delivery_Mode__c != null &&
        price.Delivery_Mode__c != deliveryMode
      ) {
        continue;
      }
      Integer score =
        (price.Branch__c != null ? 2 : 0) +
        (price.Delivery_Mode__c != null ? 1 : 0);
      String key = price.Fee_Type__c + '|' + price.Billing_Frequency__c;
      if (!bestScore.containsKey(key) || score > bestScore.get(key)) {
        best.put(key, price);
        bestScore.put(key, score);
      }
    }
    List<Fee_Price__c> ordered = best.values();
    ordered.sort(new FeeTypeOrder());
    return ordered;
  }

  /** Validates a discount code for a course/branch on a date; returns null with a warning when not usable. */
  public static Discount__c findDiscount(
    String code,
    Id courseId,
    Id branchId,
    Date onDate,
    List<String> warnings
  ) {
    if (String.isBlank(code)) {
      return null;
    }
    String normalized = code.trim().toUpperCase();
    List<Discount__c> discounts = [
      SELECT
        Id,
        Code__c,
        Discount_Type__c,
        Value__c,
        Fee_Type__c,
        Applies_To_Course__c,
        Applies_To_Branch__c,
        Valid_From__c,
        Valid_To__c,
        Active__c,
        Max_Uses__c,
        Times_Used__c,
        Requires_Approval__c
      FROM Discount__c
      WHERE Code__c = :normalized
      WITH USER_MODE
      LIMIT 1
    ];
    String problem;
    Discount__c discount = discounts.isEmpty() ? null : discounts[0];
    if (discount == null) {
      problem = 'Discount code ' + normalized + ' does not exist.';
    } else if (!discount.Active__c) {
      problem = 'Discount code ' + normalized + ' is inactive.';
    } else if (
      (discount.Valid_From__c != null && onDate < discount.Valid_From__c) ||
      (discount.Valid_To__c != null &&
      onDate > discount.Valid_To__c)
    ) {
      problem =
        'Discount code ' +
        normalized +
        ' is not valid on ' +
        onDate.format() +
        '.';
    } else if (
      discount.Max_Uses__c != null &&
      (discount.Times_Used__c == null ? 0 : discount.Times_Used__c) >=
      discount.Max_Uses__c
    ) {
      problem = 'Discount code ' + normalized + ' has reached its usage limit.';
    } else if (
      discount.Applies_To_Course__c != null &&
      discount.Applies_To_Course__c != courseId
    ) {
      problem =
        'Discount code ' +
        normalized +
        ' does not apply to this course.';
    } else if (
      discount.Applies_To_Branch__c != null &&
      discount.Applies_To_Branch__c != branchId
    ) {
      problem =
        'Discount code ' +
        normalized +
        ' does not apply to this branch.';
    }
    if (problem != null) {
      warnings.add(problem);
      return null;
    }
    return discount;
  }

  private static void applyDiscount(
    Quote result,
    QuoteRequest request,
    Date onDate
  ) {
    Discount__c discount = findDiscount(
      request.discountCode,
      request.courseId,
      request.branchId,
      onDate,
      result.warnings
    );
    if (discount == null) {
      return;
    }
    Decimal remainingFixed = discount.Discount_Type__c == 'Fixed Amount'
      ? discount.Value__c
      : 0;
    Boolean applied = false;
    for (QuoteLine line : result.lines) {
      if (
        discount.Fee_Type__c != null &&
        discount.Fee_Type__c != line.feeType
      ) {
        continue;
      }
      if (discount.Discount_Type__c == 'Percentage') {
        line.discountAmount = round(line.unitAmount * discount.Value__c / 100);
      } else {
        line.discountAmount = round(Math.min(remainingFixed, line.unitAmount));
        remainingFixed -= line.discountAmount;
      }
      applied = applied || line.discountAmount > 0;
    }
    if (!applied) {
      result.warnings.add(
        'Discount code ' +
          discount.Code__c +
          ' does not apply to any fee on this quote.'
      );
      return;
    }
    result.discountId = discount.Id;
    result.discountCode = discount.Code__c;
    result.approvalRequired = discount.Requires_Approval__c;
    if (discount.Requires_Approval__c) {
      result.warnings.add(
        'Discount ' +
          discount.Code__c +
          ' requires finance approval before invoicing.'
      );
    }
  }

  /** Records that a discount was used (called when an enrolment confirms a quote). */
  public static void recordUsage(Id discountId) {
    if (discountId == null) {
      return;
    }
    Discount__c discount = [
      SELECT Id, Times_Used__c
      FROM Discount__c
      WHERE Id = :discountId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    discount.Times_Used__c =
      (discount.Times_Used__c == null ? 0 : discount.Times_Used__c) + 1;
    Database.update(discount, AccessLevel.SYSTEM_MODE);
  }

  public static Decimal round(Decimal value) {
    return value == null ? 0 : value.setScale(2, System.RoundingMode.HALF_UP);
  }

  private static Branch__c loadBranch(Id branchId) {
    if (branchId == null) {
      return null;
    }
    List<Branch__c> branches = [
      SELECT
        Id,
        Tax_Rate__c,
        Invoice_Due_Days__c,
        Invoice_Prefix__c,
        Attendance_Threshold__c
      FROM Branch__c
      WHERE Id = :branchId
      WITH USER_MODE
    ];
    return branches.isEmpty() ? null : branches[0];
  }

  private class FeeTypeOrder implements Comparator<Fee_Price__c> {
    private final List<String> order = new List<String>{
      'Admission',
      'Tuition',
      'Materials',
      'Assessment',
      'Other'
    };
    public Integer compare(Fee_Price__c a, Fee_Price__c b) {
      return order.indexOf(a.Fee_Type__c) - order.indexOf(b.Fee_Type__c);
    }
  }
}
