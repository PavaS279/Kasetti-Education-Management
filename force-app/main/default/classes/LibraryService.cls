/**
 * Library and resources: a branch catalogue of books, devices and kits lent
 * to learners.
 *
 * - Issue: an active item with a free copy, to a learner of the branch who
 *   has no overdue loan. Due after the item's loan days (Education Setting
 *   Library_Loan_Days, default 14).
 * - Renew: before the due date, at most Library_Max_Renewals times (2).
 * - Return: late returns are fined per day (item daily fine or
 *   Library_Daily_Fine), capped at Library_Max_Fine.
 * - Lost: the replacement cost plus any late fine; the copy leaves stock.
 * - Fines are settled at the desk as Paid or Waived.
 * - The daily 'KEM Library' job marks overdue loans and reminds the fee payer
 *   on days 1, 7 and 14 (Library_Overdue message).
 *
 * Writes run without sharing after the permission check (create access on
 * loans), because copy counts and loan fields are system-managed.
 */
public with sharing class LibraryService {
  public static final Set<String> OPEN = new Set<String>{
    'On Loan',
    'Overdue'
  };
  private static final Set<Integer> REMINDER_DAYS = new Set<Integer>{
    1,
    7,
    14
  };

  public class ItemRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String itemType;
    @AuraEnabled
    public String author;
    @AuraEnabled
    public String location;
    @AuraEnabled
    public Integer copies;
    @AuraEnabled
    public Integer available;
    @AuraEnabled
    public Boolean active;
  }

  public class LoanRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String loanNumber;
    @AuraEnabled
    public Id itemId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String itemCode;
    @AuraEnabled
    public String borrower;
    @AuraEnabled
    public Id learnerAccountId;
    @AuraEnabled
    public Date loanedOn;
    @AuraEnabled
    public Date dueOn;
    @AuraEnabled
    public Date returnedOn;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer daysOverdue = 0;
    @AuraEnabled
    public Integer renewals = 0;
    @AuraEnabled
    public Boolean canRenew = false;
    @AuraEnabled
    public Decimal fine;
    @AuraEnabled
    public String fineStatus;
  }

  public class Desk {
    @AuraEnabled
    public List<ItemRow> items = new List<ItemRow>();
    @AuraEnabled
    public List<LoanRow> loans = new List<LoanRow>();
    @AuraEnabled
    public List<LoanRow> finesDue = new List<LoanRow>();
    @AuraEnabled
    public Integer titles = 0;
    @AuraEnabled
    public Integer copies = 0;
    @AuraEnabled
    public Integer onLoan = 0;
    @AuraEnabled
    public Integer overdue = 0;
    @AuraEnabled
    public Decimal finesOutstanding = 0;
    @AuraEnabled
    public Boolean canLend = false;
    @AuraEnabled
    public Boolean canManageItems = false;
  }

  public class LearnerOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
  }

  // ---------------------------------------------------------------- desk

  public static Desk desk(Id branchId, String search) {
    if (branchId == null) {
      throw new AppException('Open the library from a branch.');
    }
    Desk result = new Desk();
    result.canLend = Schema.SObjectType.Library_Loan__c.isCreateable();
    result.canManageItems = Schema.SObjectType.Library_Item__c.isCreateable();
    String term = String.isBlank(search) ? null : '%' + search.trim() + '%';
    String query =
      'SELECT Id, Name, Item_Code__c, Item_Type__c, Author__c, Location__c, Copies_Total__c, ' +
      'Copies_Available__c, Active__c FROM Library_Item__c WHERE Branch__c = :branchId' +
      (term == null
        ? ''
        : ' AND (Name LIKE :term OR Item_Code__c LIKE :term OR Author__c LIKE :term OR Subject__c LIKE :term)') +
      ' ORDER BY Active__c DESC, Name LIMIT 200';
    for (
      Library_Item__c item : (List<Library_Item__c>) Database.queryWithBinds(
        query,
        new Map<String, Object>{ 'branchId' => branchId, 'term' => term },
        AccessLevel.USER_MODE
      )
    ) {
      result.items.add(itemRow(item));
    }
    AggregateResult totals = [
      SELECT COUNT(Id) titles, SUM(Copies_Total__c) copies
      FROM Library_Item__c
      WHERE Branch__c = :branchId AND Active__c = TRUE
      WITH USER_MODE
    ];
    result.titles = (Integer) totals.get('titles');
    result.copies = totals.get('copies') == null
      ? 0
      : ((Decimal) totals.get('copies')).intValue();
    for (
      Library_Loan__c loan : loans(
        'Branch__c = :scopeId AND Status__c IN :open',
        branchId
      )
    ) {
      LoanRow row = loanRow(loan);
      result.loans.add(row);
      result.onLoan++;
      if (row.daysOverdue > 0) {
        result.overdue++;
      }
    }
    for (
      Library_Loan__c loan : loans(
        'Branch__c = :scopeId AND Fine_Status__c = \'Due\'',
        branchId
      )
    ) {
      LoanRow row = loanRow(loan);
      result.finesDue.add(row);
      result.finesOutstanding += row.fine == null ? 0 : row.fine;
    }
    return result;
  }

  /** Loans of a learner (current and the last year), for Learner 360 and the portal. */
  public static List<LoanRow> learnerLoans(Id learnerContactId) {
    List<LoanRow> rows = new List<LoanRow>();
    Date since = Date.today().addYears(-1);
    for (Library_Loan__c loan : [
      SELECT
        Id,
        Name,
        Item__c,
        Item__r.Name,
        Item__r.Item_Code__c,
        Borrower__r.Name,
        Learner_Account__c,
        Loaned_On__c,
        Due_On__c,
        Returned_On__c,
        Status__c,
        Renewals__c,
        Fine_Amount__c,
        Fine_Status__c
      FROM Library_Loan__c
      WHERE
        Borrower__c = :learnerContactId
        AND (Status__c IN :OPEN
        OR Loaned_On__c >= :since)
      WITH SYSTEM_MODE
      ORDER BY Loaned_On__c DESC
      LIMIT 50
    ]) {
      rows.add(loanRow(loan));
    }
    return rows;
  }

  /** Learners of the branch matching a name, for the issue form. */
  public static List<LearnerOption> findLearners(Id branchId, String search) {
    List<LearnerOption> options = new List<LearnerOption>();
    if (String.isBlank(search) || search.trim().length() < 2) {
      return options;
    }
    String term = '%' + search.trim() + '%';
    for (Account learner : [
      SELECT Id, Name, PersonEmail
      FROM Account
      WHERE IsPersonAccount = TRUE AND Name LIKE :term AND Branch__c = :branchId
      WITH USER_MODE
      ORDER BY Name
      LIMIT 20
    ]) {
      LearnerOption option = new LearnerOption();
      option.label =
        learner.Name +
        (String.isBlank(learner.PersonEmail)
          ? ''
          : ' · ' + learner.PersonEmail);
      option.value = learner.Id;
      options.add(option);
    }
    return options;
  }

  // ---------------------------------------------------------------- lending

  public static Id issue(Id itemId, Id learnerAccountId) {
    assertCanLend();
    if (itemId == null || learnerAccountId == null) {
      throw new AppException('Choose the item and the learner.');
    }
    Library_Item__c item = [
      SELECT
        Id,
        Name,
        Branch__c,
        Active__c,
        Copies_Total__c,
        Copies_On_Loan__c,
        Loan_Days__c
      FROM Library_Item__c
      WHERE Id = :itemId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (!item.Active__c) {
      throw new AppException(item.Name + ' is not available for lending.');
    }
    Decimal onLoan = item.Copies_On_Loan__c == null
      ? 0
      : item.Copies_On_Loan__c;
    if (onLoan >= item.Copies_Total__c) {
      throw new AppException('All copies of ' + item.Name + ' are on loan.');
    }
    Account learner = [
      SELECT Id, Name, PersonContactId, Branch__c
      FROM Account
      WHERE Id = :learnerAccountId
      WITH USER_MODE
    ];
    Integer overdue = [
      SELECT COUNT()
      FROM Library_Loan__c
      WHERE
        Borrower__c = :learner.PersonContactId
        AND (Status__c = 'Overdue'
        OR (Status__c = 'On Loan'
        AND Due_On__c < TODAY))
      WITH SYSTEM_MODE
    ];
    if (overdue > 0) {
      throw new AppException(
        learner.Name + ' has an overdue loan. Return it before borrowing again.'
      );
    }
    Integer days = item.Loan_Days__c != null
      ? item.Loan_Days__c.intValue()
      : AppSettings.getInteger('Library_Loan_Days', 14);
    Library_Loan__c loan = new Library_Loan__c(
      Item__c = item.Id,
      Borrower__c = learner.PersonContactId,
      Learner_Account__c = learner.Id,
      Branch__c = item.Branch__c,
      Loaned_On__c = Date.today(),
      Due_On__c = Date.today().addDays(days),
      Status__c = 'On Loan',
      Renewals__c = 0,
      Fine_Status__c = 'None',
      Issued_By__c = UserInfo.getUserId()
    );
    Writer writer = new Writer();
    writer.insertLoan(loan);
    writer.updateItem(
      new Library_Item__c(Id = item.Id, Copies_On_Loan__c = onLoan + 1)
    );
    return loan.Id;
  }

  public static void renew(Id loanId) {
    assertCanLend();
    Library_Loan__c loan = loadLoan(loanId);
    if (!OPEN.contains(loan.Status__c)) {
      throw new AppException('Only items on loan can be renewed.');
    }
    if (loan.Due_On__c < Date.today()) {
      throw new AppException('Overdue items must be returned, not renewed.');
    }
    Integer renewals = loan.Renewals__c == null
      ? 0
      : loan.Renewals__c.intValue();
    Integer maxRenewals = AppSettings.getInteger('Library_Max_Renewals', 2);
    if (renewals >= maxRenewals) {
      throw new AppException(
        'This loan has already been renewed ' + maxRenewals + ' times.'
      );
    }
    Integer days = loan.Item__r.Loan_Days__c != null
      ? loan.Item__r.Loan_Days__c.intValue()
      : AppSettings.getInteger('Library_Loan_Days', 14);
    new Writer()
      .updateLoan(
        new Library_Loan__c(
          Id = loan.Id,
          Due_On__c = loan.Due_On__c.addDays(days),
          Renewals__c = renewals + 1
        )
      );
  }

  /** Returns the copy; a late return is fined. Returns the fine (0 when on time). */
  public static Decimal returnLoan(Id loanId, String condition) {
    assertCanLend();
    Library_Loan__c loan = loadLoan(loanId);
    if (!OPEN.contains(loan.Status__c)) {
      throw new AppException('This item has already been returned.');
    }
    Decimal fine = lateFine(loan, Date.today());
    Writer writer = new Writer();
    writer.updateLoan(
      new Library_Loan__c(
        Id = loan.Id,
        Status__c = 'Returned',
        Returned_On__c = Date.today(),
        Return_Condition__c = condition == 'Damaged' ? 'Damaged' : 'Good',
        Fine_Amount__c = fine,
        Fine_Status__c = fine > 0 ? 'Due' : 'None'
      )
    );
    releaseCopy(writer, loan.Item__c, false);
    return fine;
  }

  /** The copy is lost: replacement cost plus any late fine; the copy leaves stock. */
  public static Decimal markLost(Id loanId) {
    assertCanLend();
    Library_Loan__c loan = loadLoan(loanId);
    if (!OPEN.contains(loan.Status__c)) {
      throw new AppException('Only items on loan can be marked lost.');
    }
    Decimal replacement = loan.Item__r.Replacement_Cost__c == null
      ? 0
      : loan.Item__r.Replacement_Cost__c;
    Decimal fine = replacement + lateFine(loan, Date.today());
    Writer writer = new Writer();
    writer.updateLoan(
      new Library_Loan__c(
        Id = loan.Id,
        Status__c = 'Lost',
        Returned_On__c = Date.today(),
        Fine_Amount__c = fine,
        Fine_Status__c = fine > 0 ? 'Due' : 'None'
      )
    );
    releaseCopy(writer, loan.Item__c, true);
    return fine;
  }

  public static void settleFine(Id loanId, String outcome) {
    assertCanLend();
    if (outcome != 'Paid' && outcome != 'Waived') {
      throw new AppException('Choose Paid or Waived.');
    }
    Library_Loan__c loan = loadLoan(loanId);
    if (loan.Fine_Status__c != 'Due') {
      throw new AppException('There is no fine due on this loan.');
    }
    new Writer()
      .updateLoan(
        new Library_Loan__c(
          Id = loan.Id,
          Fine_Status__c = outcome,
          Notes__c = ((String.isBlank(loan.Notes__c)
              ? ''
              : loan.Notes__c + '\n') +
            'Fine ' +
            outcome.toLowerCase() +
            ' by ' +
            UserInfo.getName() +
            ' on ' +
            Date.today().format())
            .left(255)
        )
      );
  }

  @TestVisible
  private static Decimal lateFine(Library_Loan__c loan, Date onDate) {
    Integer late = loan.Due_On__c == null
      ? 0
      : loan.Due_On__c.daysBetween(onDate);
    if (late <= 0) {
      return 0;
    }
    Decimal daily = loan.Item__r?.Daily_Fine__c != null
      ? loan.Item__r.Daily_Fine__c
      : AppSettings.getDecimal('Library_Daily_Fine', 5);
    Decimal cap = AppSettings.getDecimal('Library_Max_Fine', 500);
    return Math.min(daily * late, cap).setScale(2);
  }

  private static void releaseCopy(Writer writer, Id itemId, Boolean lost) {
    Library_Item__c item = [
      SELECT Id, Copies_Total__c, Copies_On_Loan__c
      FROM Library_Item__c
      WHERE Id = :itemId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    Decimal onLoan = item.Copies_On_Loan__c == null
      ? 0
      : item.Copies_On_Loan__c;
    Library_Item__c change = new Library_Item__c(
      Id = item.Id,
      Copies_On_Loan__c = Math.max(0, onLoan - 1)
    );
    if (lost) {
      Decimal remaining = Math.max(0, item.Copies_Total__c - 1);
      if (remaining == 0) {
        change.Active__c = false;
        remaining = 1; // keep the record valid; it is inactive with no copy to lend
        change.Copies_On_Loan__c = 1;
      }
      change.Copies_Total__c = remaining;
    }
    writer.updateItem(change);
  }

  // ---------------------------------------------------------------- overdue job

  /** Marks overdue loans and sends reminders on days 1, 7 and 14. Returns reminders created. */
  public static Integer processOverdue(Date today) {
    List<Library_Loan__c> loans = [
      SELECT
        Id,
        Status__c,
        Due_On__c,
        Borrower__c,
        Borrower__r.Name,
        Learner_Account__c,
        Branch__c,
        Item__r.Name,
        Item__r.Daily_Fine__c
      FROM Library_Loan__c
      WHERE Status__c IN :OPEN AND Due_On__c < :today
      WITH SYSTEM_MODE
      LIMIT 5000
    ];
    List<Library_Loan__c> updates = new List<Library_Loan__c>();
    List<Library_Loan__c> remind = new List<Library_Loan__c>();
    Set<Id> borrowers = new Set<Id>();
    for (Library_Loan__c loan : loans) {
      if (loan.Status__c != 'Overdue') {
        updates.add(new Library_Loan__c(Id = loan.Id, Status__c = 'Overdue'));
      }
      if (REMINDER_DAYS.contains(loan.Due_On__c.daysBetween(today))) {
        remind.add(loan);
        borrowers.add(loan.Borrower__c);
      }
    }
    new Writer().updateLoans(updates);
    if (remind.isEmpty()) {
      return 0;
    }
    Map<Id, Id> payers = MessageService.feePayersOf(borrowers);
    Decimal defaultFine = AppSettings.getDecimal('Library_Daily_Fine', 5);
    List<MessageService.Notice> notices = new List<MessageService.Notice>();
    for (Library_Loan__c loan : remind) {
      Integer days = loan.Due_On__c.daysBetween(today);
      MessageService.Notice notice = new MessageService.Notice();
      notice.recipientId = payers.get(loan.Borrower__c);
      notice.learnerContactId = loan.Borrower__c;
      notice.learnerAccountId = loan.Learner_Account__c;
      notice.branchId = loan.Branch__c;
      notice.relatedId = loan.Id;
      notice.dedupSuffix = String.valueOf(days);
      notice.values.put('LearnerName', loan.Borrower__r?.Name);
      notice.values.put('ItemTitle', loan.Item__r?.Name);
      notice.values.put('DueDate', loan.Due_On__c.format());
      notice.values.put('DaysOverdue', String.valueOf(days));
      notice.values.put(
        'DailyFine',
        MessageService.money(
          loan.Item__r?.Daily_Fine__c != null
            ? loan.Item__r.Daily_Fine__c
            : defaultFine
        )
      );
      notices.add(notice);
    }
    return MessageService.notify('Library_Overdue', notices);
  }

  // ---------------------------------------------------------------- helpers

  private static void assertCanLend() {
    if (!Schema.SObjectType.Library_Loan__c.isCreateable()) {
      throw new AppException(
        'You do not have permission to lend library items.'
      );
    }
  }

  private static Library_Loan__c loadLoan(Id loanId) {
    List<Library_Loan__c> rows = [
      SELECT
        Id,
        Name,
        Item__c,
        Item__r.Loan_Days__c,
        Item__r.Daily_Fine__c,
        Item__r.Replacement_Cost__c,
        Status__c,
        Due_On__c,
        Renewals__c,
        Fine_Status__c,
        Notes__c
      FROM Library_Loan__c
      WHERE Id = :loanId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Loan not found.');
    }
    return rows[0];
  }

  private static List<Library_Loan__c> loans(String filter, Id scopeId) {
    return (List<Library_Loan__c>) Database.queryWithBinds(
      'SELECT Id, Name, Item__c, Item__r.Name, Item__r.Item_Code__c, Borrower__r.Name, Learner_Account__c, ' +
        'Loaned_On__c, Due_On__c, Returned_On__c, Status__c, Renewals__c, Fine_Amount__c, Fine_Status__c ' +
        'FROM Library_Loan__c WHERE ' +
        filter +
        ' ORDER BY Due_On__c LIMIT 200',
      new Map<String, Object>{ 'scopeId' => scopeId, 'open' => OPEN },
      AccessLevel.USER_MODE
    );
  }

  private static ItemRow itemRow(Library_Item__c item) {
    ItemRow row = new ItemRow();
    row.id = item.Id;
    row.title = item.Name;
    row.code = item.Item_Code__c;
    row.itemType = item.Item_Type__c;
    row.author = item.Author__c;
    row.location = item.Location__c;
    row.copies = item.Copies_Total__c == null
      ? 0
      : item.Copies_Total__c.intValue();
    row.available = item.Copies_Available__c == null
      ? 0
      : item.Copies_Available__c.intValue();
    row.active = item.Active__c;
    return row;
  }

  private static LoanRow loanRow(Library_Loan__c loan) {
    LoanRow row = new LoanRow();
    row.id = loan.Id;
    row.loanNumber = loan.Name;
    row.itemId = loan.Item__c;
    row.title = loan.Item__r?.Name;
    row.itemCode = loan.Item__r?.Item_Code__c;
    row.borrower = loan.Borrower__r?.Name;
    row.learnerAccountId = loan.Learner_Account__c;
    row.loanedOn = loan.Loaned_On__c;
    row.dueOn = loan.Due_On__c;
    row.returnedOn = loan.Returned_On__c;
    row.status = loan.Status__c;
    row.renewals = loan.Renewals__c == null ? 0 : loan.Renewals__c.intValue();
    if (
      OPEN.contains(loan.Status__c) &&
      loan.Due_On__c != null &&
      loan.Due_On__c < Date.today()
    ) {
      row.daysOverdue = loan.Due_On__c.daysBetween(Date.today());
    }
    row.canRenew =
      OPEN.contains(loan.Status__c) &&
      row.daysOverdue == 0 &&
      row.renewals < AppSettings.getInteger('Library_Max_Renewals', 2);
    row.fine = loan.Fine_Amount__c;
    row.fineStatus = loan.Fine_Status__c;
    return row;
  }

  private without sharing class Writer {
    void insertLoan(Library_Loan__c loan) {
      Database.insert(loan, AccessLevel.SYSTEM_MODE);
    }
    void updateLoan(Library_Loan__c loan) {
      Database.update(loan, AccessLevel.SYSTEM_MODE);
    }
    void updateLoans(List<Library_Loan__c> loans) {
      Database.update(loans, AccessLevel.SYSTEM_MODE);
    }
    void updateItem(Library_Item__c item) {
      Database.update(item, AccessLevel.SYSTEM_MODE);
    }
  }
}
