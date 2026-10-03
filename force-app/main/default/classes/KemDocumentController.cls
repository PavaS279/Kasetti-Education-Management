/**
 * Data for the PDF templates KEM_Offer_Letter, KEM_Invoice_Pdf and
 * KEM_Receipt_Pdf. The record comes from the "id" page parameter and is read in
 * user mode, so a user can only render documents for records they can see.
 */
public with sharing class KemDocumentController {
  public IndividualApplication application { get; private set; }
  public Student_Invoice__c invoice { get; private set; }
  public List<Invoice_Line__c> lines { get; private set; }
  public Student_Payment__c payment { get; private set; }
  public List<Payment_Allocation__c> allocations { get; private set; }
  public Branch__c branch { get; private set; }
  public List<FeeRow> fees { get; private set; }
  public Decimal feeTotal { get; private set; }
  public String institutionName { get; private set; }
  public Date today { get; private set; }
  public String currencyCode { get; private set; }

  /** Visualforce binds to properties only, so quote lines are copied here. */
  public class FeeRow {
    public String label { get; private set; }
    public String frequency { get; private set; }
    public Decimal amount { get; private set; }
    public Decimal discount { get; private set; }
    public Decimal tax { get; private set; }
    public Decimal total { get; private set; }
  }

  public KemDocumentController() {
    institutionName = AppSettings.getString(
      'Institution_Name',
      UserInfo.getOrganizationName()
    );
    today = Date.today();
    currencyCode = UserInfo.getDefaultCurrency();
    Id recordId = (Id) ApexPages.currentPage().getParameters().get('id');
    SObjectType type = recordId.getSObjectType();
    if (type == IndividualApplication.SObjectType) {
      loadApplication(recordId);
    } else if (type == Student_Invoice__c.SObjectType) {
      loadInvoice(recordId);
    } else if (type == Student_Payment__c.SObjectType) {
      loadPayment(recordId);
    }
  }

  public String branchAddress {
    get {
      if (branch == null) {
        return '';
      }
      List<String> parts = new List<String>();
      for (
        String part : new List<String>{
          branch.Street__c,
          branch.City__c,
          branch.State__c,
          branch.Postal_Code__c,
          branch.Country__c
        }
      ) {
        if (String.isNotBlank(part)) {
          parts.add(part);
        }
      }
      return String.join(parts, ', ');
    }
  }

  public String branchName {
    get {
      return branch == null ? '' : branch.Name;
    }
  }

  public String branchContact {
    get {
      if (branch == null) {
        return '';
      }
      List<String> parts = new List<String>();
      for (String part : new List<String>{ branch.Phone__c, branch.Email__c }) {
        if (String.isNotBlank(part)) {
          parts.add(part);
        }
      }
      return String.join(parts, ' · ');
    }
  }

  private void loadApplication(Id recordId) {
    application = [
      SELECT
        Name,
        Offer_Status__c,
        Offer_Expiry_Date__c,
        Decision_Date__c,
        Account.Name,
        Account.PersonMailingStreet,
        Account.PersonMailingCity,
        Learning_Course__c,
        Learning_Course__r.Name,
        Requested_Offering__r.Name,
        Requested_Offering__r.StartDate,
        Branch__c
      FROM IndividualApplication
      WHERE Id = :recordId
      WITH USER_MODE
    ];
    loadBranch(application.Branch__c);
    fees = new List<FeeRow>();
    feeTotal = 0;
    if (application.Learning_Course__c != null) {
      try {
        PricingService.QuoteRequest request = new PricingService.QuoteRequest();
        request.courseId = application.Learning_Course__c;
        request.branchId = application.Branch__c;
        PricingService.Quote quote = PricingService.quote(request);
        for (PricingService.QuoteLine line : quote.lines) {
          FeeRow row = new FeeRow();
          row.label = String.isBlank(line.description)
            ? line.feeType
            : line.description;
          row.frequency = line.frequency;
          row.amount = line.unitAmount;
          row.discount = line.discountAmount;
          row.tax = line.taxAmount;
          row.total = line.total;
          fees.add(row);
        }
        feeTotal = quote.grandTotal;
      } catch (Exception e) {
        // A missing price list must not block the letter; fees are confirmed at enrolment.
        Logger.error('KemDocumentController.loadApplication', e, recordId);
      }
    }
  }

  private void loadInvoice(Id recordId) {
    invoice = [
      SELECT
        Name,
        Status__c,
        Issue_Date__c,
        Due_Date__c,
        Subtotal__c,
        Discount_Total__c,
        Tax_Total__c,
        Total__c,
        Amount_Paid__c,
        Balance_Due__c,
        Bill_To__r.Name,
        Bill_To__r.Email,
        Bill_To__r.MailingStreet,
        Bill_To__r.MailingCity,
        Learner__r.Name,
        Enrolment__r.CourseOffering.Name,
        Branch__c
      FROM Student_Invoice__c
      WHERE Id = :recordId
      WITH USER_MODE
    ];
    lines = [
      SELECT
        Fee_Type__c,
        Description__c,
        Unit_Amount__c,
        Discount_Amount__c,
        Tax_Amount__c,
        Line_Total__c
      FROM Invoice_Line__c
      WHERE Student_Invoice__c = :recordId
      WITH SYSTEM_MODE
      ORDER BY Name
    ];
    loadBranch(invoice.Branch__c);
  }

  private void loadPayment(Id recordId) {
    payment = [
      SELECT
        Name,
        Receipt_Number__c,
        Amount__c,
        Method__c,
        Payment_Date__c,
        Reference__c,
        Status__c,
        Payer__r.Name,
        Learner__r.Name,
        Branch__c,
        Unallocated_Amount__c
      FROM Student_Payment__c
      WHERE Id = :recordId
      WITH USER_MODE
    ];
    allocations = [
      SELECT
        Amount__c,
        Student_Invoice__r.Name,
        Student_Invoice__r.Balance_Due__c,
        Student_Invoice__r.Branch__c
      FROM Payment_Allocation__c
      WHERE Student_Payment__c = :recordId
      WITH SYSTEM_MODE
      ORDER BY Name
    ];
    Id branchId = payment.Branch__c;
    if (branchId == null && !allocations.isEmpty()) {
      branchId = allocations[0].Student_Invoice__r.Branch__c;
    }
    loadBranch(branchId);
  }

  private void loadBranch(Id branchId) {
    if (branchId == null) {
      return;
    }
    branch = [
      SELECT
        Name,
        Email__c,
        Phone__c,
        Street__c,
        City__c,
        State__c,
        Postal_Code__c,
        Country__c
      FROM Branch__c
      WHERE Id = :branchId
      WITH SYSTEM_MODE
    ];
  }
}
