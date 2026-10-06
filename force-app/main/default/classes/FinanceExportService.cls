/**
 * Generic ERP finance export: the ledger of a date range as balanced
 * double-entry journal lines (CSV or JSON).
 *
 * | Document                       | Debit                         | Credit                         |
 * | ------------------------------ | ----------------------------- | ------------------------------ |
 * | Invoice issued (issue date)    | Receivables (total)           | Revenue (net), Tax             |
 * | Invoice cancelled              | Revenue, Tax                  | Receivables (reversal)         |
 * | Payment confirmed              | Bank or Cash                  | Receivables                    |
 * | Credit applied to an invoice   | Customer credit               | Receivables                    |
 * | Credit note: overpayment       | Receivables                   | Customer credit                |
 * | Credit note: other origins     | Credit allowance              | Customer credit                |
 * | Refund paid                    | Customer credit               | Bank                           |
 *
 * Account codes come from Education Settings ERP_Account_*. Reads run as the
 * user, so finance users, administrators and the integration user can export.
 */
public with sharing class FinanceExportService {
  public static final Integer MAX_DAYS = 92;
  private static final String SOURCE = 'FinanceExportService';

  private static final Map<String, List<String>> ACCOUNTS = new Map<String, List<String>>{
    'Receivable' => new List<String>{
      'ERP_Account_Receivable',
      '1100',
      'Accounts receivable'
    },
    'Bank' => new List<String>{ 'ERP_Account_Bank', '1010', 'Bank' },
    'Cash' => new List<String>{ 'ERP_Account_Cash', '1000', 'Cash' },
    'Revenue' => new List<String>{
      'ERP_Account_Revenue',
      '4000',
      'Tuition and fees revenue'
    },
    'Tax' => new List<String>{ 'ERP_Account_Tax', '2200', 'Tax payable' },
    'Credit' => new List<String>{
      'ERP_Account_Customer_Credit',
      '2300',
      'Customer credit'
    },
    'Allowance' => new List<String>{
      'ERP_Account_Credit_Allowance',
      '4900',
      'Credits and allowances'
    }
  };

  public class JournalLine {
    @AuraEnabled
    public String entryId;
    @AuraEnabled
    public Date entryDate;
    @AuraEnabled
    public String documentType;
    @AuraEnabled
    public String documentNumber;
    @AuraEnabled
    public Id documentId;
    @AuraEnabled
    public String branchCode;
    @AuraEnabled
    public String account;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Decimal debit = 0;
    @AuraEnabled
    public Decimal credit = 0;
    @AuraEnabled
    public String learner;
    @AuraEnabled
    public String payer;
    @AuraEnabled
    public String reference;
    @AuraEnabled
    public String description;
  }

  public class AccountTotal {
    @AuraEnabled
    public String account;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Decimal debit = 0;
    @AuraEnabled
    public Decimal credit = 0;
  }

  public class Journal {
    @AuraEnabled
    public Date fromDate;
    @AuraEnabled
    public Date toDate;
    @AuraEnabled
    public String branchCode;
    @AuraEnabled
    public List<JournalLine> lines = new List<JournalLine>();
    @AuraEnabled
    public List<AccountTotal> accounts = new List<AccountTotal>();
    @AuraEnabled
    public Integer documents = 0;
    @AuraEnabled
    public Decimal totalDebit = 0;
    @AuraEnabled
    public Decimal totalCredit = 0;
    @AuraEnabled
    public Boolean balanced = true;
  }

  public class ExportSummary {
    @AuraEnabled
    public Id exportId;
    @AuraEnabled
    public String exportNumber;
    @AuraEnabled
    public Date fromDate;
    @AuraEnabled
    public Date toDate;
    @AuraEnabled
    public String branchName;
    @AuraEnabled
    public String runType;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer lines;
    @AuraEnabled
    public Integer documents;
    @AuraEnabled
    public Decimal totalDebit;
    @AuraEnabled
    public Decimal totalCredit;
    @AuraEnabled
    public Id fileId;
    @AuraEnabled
    public Datetime createdAt;
    @AuraEnabled
    public String createdBy;
  }

  // ------------------------------------------------------------- journal

  public static Journal journal(Date fromDate, Date toDate, Id branchId) {
    validateRange(fromDate, toDate);
    assertCanExport();
    Journal result = new Journal();
    result.fromDate = fromDate;
    result.toDate = toDate;
    if (branchId != null) {
      result.branchCode = [
        SELECT Branch_Code__c
        FROM Branch__c
        WHERE Id = :branchId
        WITH USER_MODE
      ]
      .Branch_Code__c;
    }
    Set<Id> documents = new Set<Id>();
    invoices(result, fromDate, toDate, branchId, documents);
    payments(result, fromDate, toDate, branchId, documents);
    creditNotes(result, fromDate, toDate, branchId, documents);
    refunds(result, fromDate, toDate, branchId, documents);
    result.documents = documents.size();
    Map<String, AccountTotal> byAccount = new Map<String, AccountTotal>();
    for (JournalLine line : result.lines) {
      result.totalDebit += line.debit;
      result.totalCredit += line.credit;
      if (!byAccount.containsKey(line.account)) {
        AccountTotal total = new AccountTotal();
        total.account = line.account;
        total.accountName = line.accountName;
        byAccount.put(line.account, total);
      }
      byAccount.get(line.account).debit += line.debit;
      byAccount.get(line.account).credit += line.credit;
    }
    List<String> codes = new List<String>(byAccount.keySet());
    codes.sort();
    for (String code : codes) {
      result.accounts.add(byAccount.get(code));
    }
    result.balanced = result.totalDebit == result.totalCredit;
    return result;
  }

  private static void invoices(
    Journal result,
    Date fromDate,
    Date toDate,
    Id branchId,
    Set<Id> documents
  ) {
    Datetime fromTime = Datetime.newInstance(
      fromDate,
      Time.newInstance(0, 0, 0, 0)
    );
    Datetime toTime = Datetime.newInstance(
      toDate.addDays(1),
      Time.newInstance(0, 0, 0, 0)
    );
    String query =
      'SELECT Id, Name, Issue_Date__c, Status__c, Total__c, Tax_Total__c, LastModifiedDate, ' +
      'Branch__r.Branch_Code__c, Learner__r.Name, Bill_To__r.Name, Billing_Period__c ' +
      'FROM Student_Invoice__c WHERE Issue_Date__c != null AND ' +
      '((Issue_Date__c >= :fromDate AND Issue_Date__c <= :toDate AND Status__c != \'Draft\') ' +
      'OR (Status__c = \'Cancelled\' AND LastModifiedDate >= :fromTime AND LastModifiedDate < :toTime))' +
      (branchId == null ? '' : ' AND Branch__c = :branchId') +
      ' ORDER BY Issue_Date__c, Name LIMIT 20000';
    Map<String, Object> binds = new Map<String, Object>{
      'fromDate' => fromDate,
      'toDate' => toDate,
      'fromTime' => fromTime,
      'toTime' => toTime,
      'branchId' => branchId
    };
    for (
      Student_Invoice__c invoice : (List<Student_Invoice__c>) Database.queryWithBinds(
        query,
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      Decimal total = nvl(invoice.Total__c);
      Decimal tax = nvl(invoice.Tax_Total__c);
      Decimal net = total - tax;
      String description =
        'Invoice' +
        (String.isBlank(invoice.Billing_Period__c)
          ? ''
          : ' ' + invoice.Billing_Period__c);
      Boolean issuedInRange =
        invoice.Issue_Date__c >= fromDate &&
        invoice.Issue_Date__c <= toDate;
      if (issuedInRange) {
        documents.add(invoice.Id);
        Context c = new Context(
          result,
          'Invoice',
          invoice.Name,
          invoice.Id,
          invoice.Issue_Date__c
        );
        c.branchCode = invoice.Branch__r?.Branch_Code__c;
        c.learner = invoice.Learner__r?.Name;
        c.payer = invoice.Bill_To__r?.Name;
        c.description = description;
        c.debit('Receivable', total);
        c.credit('Revenue', net);
        c.credit('Tax', tax);
      }
      Date cancelledOn = invoice.LastModifiedDate.date();
      if (
        invoice.Status__c == 'Cancelled' &&
        cancelledOn >= fromDate &&
        cancelledOn <= toDate
      ) {
        documents.add(invoice.Id);
        Context c = new Context(
          result,
          'Invoice Cancellation',
          invoice.Name,
          invoice.Id,
          cancelledOn
        );
        c.branchCode = invoice.Branch__r?.Branch_Code__c;
        c.learner = invoice.Learner__r?.Name;
        c.payer = invoice.Bill_To__r?.Name;
        c.description = 'Cancellation of ' + description.toLowerCase();
        c.debit('Revenue', net);
        c.debit('Tax', tax);
        c.credit('Receivable', total);
      }
    }
  }

  private static void payments(
    Journal result,
    Date fromDate,
    Date toDate,
    Id branchId,
    Set<Id> documents
  ) {
    String query =
      'SELECT Id, Name, Payment_Date__c, Amount__c, Method__c, Reference__c, Gateway_Transaction_Id__c, ' +
      'Receipt_Number__c, Branch__r.Branch_Code__c, Learner__r.Name, Payer__r.Name, Student_Invoice__r.Name ' +
      'FROM Student_Payment__c WHERE Status__c = \'Confirmed\' ' +
      'AND Payment_Date__c >= :fromDate AND Payment_Date__c <= :toDate' +
      (branchId == null ? '' : ' AND Branch__c = :branchId') +
      ' ORDER BY Payment_Date__c, Name LIMIT 20000';
    for (
      Student_Payment__c payment : (List<Student_Payment__c>) Database.queryWithBinds(
        query,
        new Map<String, Object>{
          'fromDate' => fromDate,
          'toDate' => toDate,
          'branchId' => branchId
        },
        AccessLevel.USER_MODE
      )
    ) {
      documents.add(payment.Id);
      Boolean creditApplied = payment.Method__c == CreditService.CREDIT_METHOD;
      Context c = new Context(
        result,
        creditApplied ? 'Credit Application' : 'Payment',
        String.isBlank(payment.Receipt_Number__c)
          ? payment.Name
          : payment.Receipt_Number__c,
        payment.Id,
        payment.Payment_Date__c
      );
      c.branchCode = payment.Branch__r?.Branch_Code__c;
      c.learner = payment.Learner__r?.Name;
      c.payer = payment.Payer__r?.Name;
      c.reference = firstNonBlank(
        payment.Gateway_Transaction_Id__c,
        payment.Reference__c
      );
      c.description =
        payment.Method__c +
        (payment.Student_Invoice__r == null
          ? ''
          : ' for ' + payment.Student_Invoice__r.Name);
      Decimal amount = nvl(payment.Amount__c);
      c.debit(
        creditApplied
          ? 'Credit'
          : (payment.Method__c == 'Cash' ? 'Cash' : 'Bank'),
        amount
      );
      c.credit('Receivable', amount);
    }
  }

  private static void creditNotes(
    Journal result,
    Date fromDate,
    Date toDate,
    Id branchId,
    Set<Id> documents
  ) {
    String query =
      'SELECT Id, Name, Issue_Date__c, Amount__c, Origin__c, Reason__c, ' +
      'Branch__r.Branch_Code__c, Learner__r.Name, Bill_To__r.Name ' +
      'FROM Credit_Note__c WHERE Status__c != \'Void\' ' +
      'AND Issue_Date__c >= :fromDate AND Issue_Date__c <= :toDate' +
      (branchId == null ? '' : ' AND Branch__c = :branchId') +
      ' ORDER BY Issue_Date__c, Name LIMIT 20000';
    for (
      Credit_Note__c note : (List<Credit_Note__c>) Database.queryWithBinds(
        query,
        new Map<String, Object>{
          'fromDate' => fromDate,
          'toDate' => toDate,
          'branchId' => branchId
        },
        AccessLevel.USER_MODE
      )
    ) {
      documents.add(note.Id);
      Context c = new Context(
        result,
        'Credit Note',
        note.Name,
        note.Id,
        note.Issue_Date__c
      );
      c.branchCode = note.Branch__r?.Branch_Code__c;
      c.learner = note.Learner__r?.Name;
      c.payer = note.Bill_To__r?.Name;
      c.description =
        note.Origin__c +
        (String.isBlank(note.Reason__c) ? '' : ': ' + note.Reason__c);
      Decimal amount = nvl(note.Amount__c);
      c.debit(
        note.Origin__c == 'Overpayment' ? 'Receivable' : 'Allowance',
        amount
      );
      c.credit('Credit', amount);
    }
  }

  private static void refunds(
    Journal result,
    Date fromDate,
    Date toDate,
    Id branchId,
    Set<Id> documents
  ) {
    String query =
      'SELECT Id, Name, Paid_On__c, Amount__c, Method__c, Reference__c, ' +
      'Branch__r.Branch_Code__c, Payee__r.Name, Credit_Note__r.Name ' +
      'FROM Refund__c WHERE Status__c = \'Paid\' ' +
      'AND Paid_On__c >= :fromDate AND Paid_On__c <= :toDate' +
      (branchId == null ? '' : ' AND Branch__c = :branchId') +
      ' ORDER BY Paid_On__c, Name LIMIT 20000';
    for (
      Refund__c refund : (List<Refund__c>) Database.queryWithBinds(
        query,
        new Map<String, Object>{
          'fromDate' => fromDate,
          'toDate' => toDate,
          'branchId' => branchId
        },
        AccessLevel.USER_MODE
      )
    ) {
      documents.add(refund.Id);
      Context c = new Context(
        result,
        'Refund',
        refund.Name,
        refund.Id,
        refund.Paid_On__c
      );
      c.branchCode = refund.Branch__r?.Branch_Code__c;
      c.payer = refund.Payee__r?.Name;
      c.reference = refund.Reference__c;
      c.description =
        'Refund by ' +
        refund.Method__c +
        (refund.Credit_Note__r == null
          ? ''
          : ' of ' + refund.Credit_Note__r.Name);
      Decimal amount = nvl(refund.Amount__c);
      c.debit('Credit', amount);
      c.credit('Bank', amount);
    }
  }

  /** Builds the lines of one document. */
  private class Context {
    Journal journal;
    String documentType;
    String documentNumber;
    Id documentId;
    Date entryDate;
    String branchCode;
    String learner;
    String payer;
    String reference;
    String description;
    Integer seq = 0;

    Context(
      Journal journal,
      String documentType,
      String documentNumber,
      Id documentId,
      Date entryDate
    ) {
      this.journal = journal;
      this.documentType = documentType;
      this.documentNumber = documentNumber;
      this.documentId = documentId;
      this.entryDate = entryDate;
    }

    void debit(String key, Decimal amount) {
      add(key, amount, true);
    }

    void credit(String key, Decimal amount) {
      add(key, amount, false);
    }

    void add(String key, Decimal amount, Boolean isDebit) {
      if (amount == null || amount == 0) {
        return;
      }
      seq++;
      JournalLine line = new JournalLine();
      line.entryId =
        documentNumber +
        (documentType == 'Invoice Cancellation' ? '-X' : '') +
        '-' +
        seq;
      line.entryDate = entryDate;
      line.documentType = documentType;
      line.documentNumber = documentNumber;
      line.documentId = documentId;
      line.branchCode = branchCode;
      line.account = accountCode(key);
      line.accountName = ACCOUNTS.get(key)[2];
      line.learner = learner;
      line.payer = payer;
      line.reference = reference;
      line.description = description;
      Decimal value = amount.setScale(2);
      // A negative amount swaps sides so every line is positive.
      if ((value > 0) == isDebit) {
        line.debit = value.abs();
      } else {
        line.credit = value.abs();
      }
      journal.lines.add(line);
    }
  }

  public static String accountCode(String key) {
    List<String> config = ACCOUNTS.get(key);
    return AppSettings.getString(config[0], config[1]);
  }

  // ------------------------------------------------------------------ CSV

  public static String toCsv(Journal journal) {
    List<String> rows = new List<String>{
      'Entry ID,Date,Document Type,Document Number,Branch,Account,Account Name,Debit,Credit,Learner,Payer,Reference,Description'
    };
    for (JournalLine line : journal.lines) {
      rows.add(
        String.join(
          new List<String>{
            csv(line.entryId),
            csv(String.valueOf(line.entryDate)),
            csv(line.documentType),
            csv(line.documentNumber),
            csv(line.branchCode),
            csv(line.account),
            csv(line.accountName),
            line.debit.setScale(2).toPlainString(),
            line.credit.setScale(2).toPlainString(),
            csv(line.learner),
            csv(line.payer),
            csv(line.reference),
            csv(line.description)
          },
          ','
        )
      );
    }
    return String.join(rows, '\r\n') + '\r\n';
  }

  @TestVisible
  private static String csv(String value) {
    if (value == null) {
      return '';
    }
    // Neutralise spreadsheet formulas and quote every text value.
    String safe = value;
    if (safe.length() > 0 && '=+-@'.contains(safe.left(1))) {
      safe = '\'' + safe;
    }
    return '"' + safe.replace('"', '""') + '"';
  }

  // --------------------------------------------------------------- exports

  /** Builds the journal, saves the CSV as a file and records the export. */
  public static ExportSummary export(
    Date fromDate,
    Date toDate,
    Id branchId,
    String runType
  ) {
    if (!Schema.SObjectType.Finance_Export__c.isCreateable()) {
      throw new AppException(
        'You do not have permission to export the finance journal.'
      );
    }
    Journal journal = journal(fromDate, toDate, branchId);
    String label =
      'KEM journal ' +
      String.valueOf(fromDate) +
      (fromDate == toDate ? '' : ' to ' + String.valueOf(toDate)) +
      (journal.branchCode == null ? '' : ' ' + journal.branchCode);
    ContentVersion file = new ContentVersion(
      Title = label,
      PathOnClient = label.replace(' ', '_') + '.csv',
      VersionData = Blob.valueOf(toCsv(journal))
    );
    insert as user file;
    Id documentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :file.Id
      WITH USER_MODE
    ]
    .ContentDocumentId;
    Finance_Export__c record = new Finance_Export__c(
      From_Date__c = fromDate,
      To_Date__c = toDate,
      Branch__c = branchId,
      Run_Type__c = runType,
      Status__c = 'Completed',
      Line_Count__c = journal.lines.size(),
      Document_Count__c = journal.documents,
      Total_Debit__c = journal.totalDebit,
      Total_Credit__c = journal.totalCredit,
      File_Id__c = documentId
    );
    new Writer().insertRecord(record);
    new Writer()
      .link(
        new ContentDocumentLink(
          ContentDocumentId = documentId,
          LinkedEntityId = record.Id,
          ShareType = 'V'
        )
      );
    Logger.info(
      SOURCE,
      label +
        ': ' +
        journal.lines.size() +
        ' lines, ' +
        journal.documents +
        ' documents.'
    );
    return summary(load(record.Id));
  }

  public static List<ExportSummary> recent(Integer count) {
    List<ExportSummary> rows = new List<ExportSummary>();
    for (Finance_Export__c record : [
      SELECT
        Id,
        Name,
        From_Date__c,
        To_Date__c,
        Branch__r.Name,
        Run_Type__c,
        Status__c,
        Line_Count__c,
        Document_Count__c,
        Total_Debit__c,
        Total_Credit__c,
        File_Id__c,
        CreatedDate,
        CreatedBy.Name
      FROM Finance_Export__c
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT :count
    ]) {
      rows.add(summary(record));
    }
    return rows;
  }

  /** Scheduled daily export of yesterday ('KEM Finance Export', 03:15) when ERP_Daily_Export is On. */
  public static ExportSummary dailyExport() {
    if (AppSettings.getString('ERP_Daily_Export', 'On') != 'On') {
      return null;
    }
    Date yesterday = Date.today().addDays(-1);
    return export(yesterday, yesterday, null, 'Scheduled');
  }

  private static Finance_Export__c load(Id exportId) {
    return [
      SELECT
        Id,
        Name,
        From_Date__c,
        To_Date__c,
        Branch__r.Name,
        Run_Type__c,
        Status__c,
        Line_Count__c,
        Document_Count__c,
        Total_Debit__c,
        Total_Credit__c,
        File_Id__c,
        CreatedDate,
        CreatedBy.Name
      FROM Finance_Export__c
      WHERE Id = :exportId
      WITH SYSTEM_MODE
    ];
  }

  private static ExportSummary summary(Finance_Export__c record) {
    ExportSummary s = new ExportSummary();
    s.exportId = record.Id;
    s.exportNumber = record.Name;
    s.fromDate = record.From_Date__c;
    s.toDate = record.To_Date__c;
    s.branchName = record.Branch__r?.Name;
    s.runType = record.Run_Type__c;
    s.status = record.Status__c;
    s.lines = record.Line_Count__c == null
      ? 0
      : record.Line_Count__c.intValue();
    s.documents = record.Document_Count__c == null
      ? 0
      : record.Document_Count__c.intValue();
    s.totalDebit = record.Total_Debit__c;
    s.totalCredit = record.Total_Credit__c;
    s.fileId = record.File_Id__c;
    s.createdAt = record.CreatedDate;
    s.createdBy = record.CreatedBy?.Name;
    return s;
  }

  // --------------------------------------------------------------- helpers

  private static void validateRange(Date fromDate, Date toDate) {
    if (fromDate == null || toDate == null) {
      throw new AppException('Choose the from and to dates.');
    }
    if (toDate < fromDate) {
      throw new AppException('The to date must be on or after the from date.');
    }
    if (fromDate.daysBetween(toDate) >= MAX_DAYS) {
      throw new AppException('Export at most ' + MAX_DAYS + ' days at a time.');
    }
  }

  private static void assertCanExport() {
    if (
      !Schema.SObjectType.Finance_Export__c.isCreateable() &&
      !FeatureManagement.checkPermission(IntegrationService.PERMISSION)
    ) {
      throw new AppException(
        'You do not have permission to export the finance journal.'
      );
    }
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  private static String firstNonBlank(String a, String b) {
    return String.isNotBlank(a) ? a : b;
  }

  /** Export records are system-managed; the file link needs no extra access. */
  private without sharing class Writer {
    void insertRecord(Finance_Export__c record) {
      Database.insert(record, AccessLevel.SYSTEM_MODE);
    }
    void link(ContentDocumentLink link) {
      Database.insert(link, AccessLevel.SYSTEM_MODE);
    }
  }
}
