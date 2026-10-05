/**
 * Operations console (F2.9): is everything that runs on its own running, and
 * what is waiting for a person?
 *
 *  - Scheduled jobs: every KemJobs schedule, its state and next/last run.
 *  - Background runs: KEM batch and queueable jobs of the last 7 days, with
 *    failures and item errors.
 *  - Error log: ERROR/FATAL entries of the last 7 days by source, newest first.
 *  - Exception queues: work items that need a person (reconciliation
 *    exceptions, refunds awaiting approval, sessions needing cover, undelivered
 *    messages, overdue invoices, offers about to expire).
 *
 * For administrators only (read access to the error log). Actions: re-arm the
 * schedules and run a recurring job now.
 */
public with sharing class OpsService {
  private static final Set<String> KEM_CLASSES = new Set<String>{
    'RecurringBillingJob',
    'OfferExpiryJob',
    'WaitlistOfferJob',
    'MessageJob',
    'MessageService',
    'DocumentService',
    'OpsService'
  };
  private static final Set<String> FAILED = new Set<String>{
    'Failed',
    'Aborted'
  };

  public class Schedule {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public Datetime nextRun;
    @AuraEnabled
    public Datetime lastRun;
    @AuraEnabled
    public String cron;
    @AuraEnabled
    public Boolean missing;
  }

  public class Run {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String job;
    @AuraEnabled
    public String jobType;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer itemsProcessed;
    @AuraEnabled
    public Integer totalItems;
    @AuraEnabled
    public Integer errors;
    @AuraEnabled
    public String detail;
    @AuraEnabled
    public Datetime createdDate;
    @AuraEnabled
    public Datetime completedDate;
    @AuraEnabled
    public Boolean problem;
  }

  public class Queue {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Integer count;
    @AuraEnabled
    public String hint;
    /** ok, warning or error, when count is above zero. */
    @AuraEnabled
    public String severity;
  }

  public class ErrorSource {
    @AuraEnabled
    public String source;
    @AuraEnabled
    public Integer count;
  }

  public class Console {
    /** healthy, attention or failing. */
    @AuraEnabled
    public String health;
    @AuraEnabled
    public List<String> issues = new List<String>();
    @AuraEnabled
    public List<Schedule> schedules = new List<Schedule>();
    @AuraEnabled
    public List<Run> runs = new List<Run>();
    @AuraEnabled
    public List<Queue> queues = new List<Queue>();
    @AuraEnabled
    public List<ErrorSource> errorSources = new List<ErrorSource>();
    @AuraEnabled
    public List<Error_Log__c> recentErrors = new List<Error_Log__c>();
    @AuraEnabled
    public Integer errorsLast24h = 0;
    @AuraEnabled
    public Datetime generatedAt;
  }

  public static Console console() {
    assertAdmin();
    Console result = new Console();
    result.generatedAt = System.now();
    addSchedules(result);
    addRuns(result);
    addErrors(result);
    addQueues(result);
    result.health = result.issues.isEmpty()
      ? 'healthy'
      : hasFailure(result) ? 'failing' : 'attention';
    return result;
  }

  /** Schedules any KEM job that is not scheduled. Returns how many were added. */
  public static Integer ensureSchedules() {
    assertAdmin();
    return KemJobs.scheduleAll();
  }

  /** Runs a recurring job now, outside its schedule. Returns the async job Id. */
  public static Id runNow(String jobName) {
    assertAdmin();
    switch on jobName {
      when 'KEM Recurring Billing' {
        return Database.executeBatch(new RecurringBillingJob(), 20);
      }
      when 'KEM Offer Expiry' {
        return Database.executeBatch(new OfferExpiryJob(), 200);
      }
      when 'KEM Waitlist Offers' {
        return System.enqueueJob(new RunSchedulable(new WaitlistOfferJob()));
      }
      when 'KEM Payment Reminders' {
        return System.enqueueJob(new RunSchedulable(new MessageJob(true)));
      }
      when 'KEM Message Dispatch' {
        return System.enqueueJob(new MessageService.DispatchJob());
      }
      when else {
        throw new AppException('Unknown job: ' + jobName);
      }
    }
  }

  /** Runs a schedulable's work from a queueable (for "Run now"). */
  public class RunSchedulable implements Queueable {
    private final Schedulable job;

    public RunSchedulable(Schedulable job) {
      this.job = job;
    }

    public void execute(QueueableContext context) {
      job.execute(null);
    }
  }

  // --------------------------------------------------------------- sections

  private static void addSchedules(Console result) {
    Map<String, CronTrigger> byName = new Map<String, CronTrigger>();
    for (CronTrigger job : [
      SELECT
        CronJobDetail.Name,
        State,
        NextFireTime,
        PreviousFireTime,
        CronExpression
      FROM CronTrigger
      WHERE CronJobDetail.Name LIKE 'KEM %'
    ]) {
      byName.put(job.CronJobDetail.Name, job);
    }
    for (String name : KemJobs.jobNames()) {
      Schedule schedule = new Schedule();
      schedule.name = name;
      CronTrigger job = byName.get(name);
      schedule.missing = job == null;
      if (job == null) {
        schedule.state = 'NOT SCHEDULED';
        result.issues.add(name + ' is not scheduled.');
      } else {
        schedule.state = job.State;
        schedule.nextRun = job.NextFireTime;
        schedule.lastRun = job.PreviousFireTime;
        schedule.cron = job.CronExpression;
        if (
          job.State != 'WAITING' &&
          job.State != 'ACQUIRED' &&
          job.State != 'EXECUTING'
        ) {
          result.issues.add(name + ' is ' + job.State + '.');
        }
      }
      result.schedules.add(schedule);
    }
  }

  private static void addRuns(Console result) {
    Datetime since = System.now().addDays(-7);
    for (AsyncApexJob job : [
      SELECT
        Id,
        ApexClass.Name,
        JobType,
        Status,
        JobItemsProcessed,
        TotalJobItems,
        NumberOfErrors,
        ExtendedStatus,
        CreatedDate,
        CompletedDate
      FROM AsyncApexJob
      WHERE
        CreatedDate >= :since
        AND ApexClass.Name IN :KEM_CLASSES
        AND JobType IN ('BatchApex', 'Queueable', 'ScheduledApex')
      ORDER BY CreatedDate DESC
      LIMIT 50
    ]) {
      Run run = new Run();
      run.id = job.Id;
      run.job = job.ApexClass?.Name;
      run.jobType = job.JobType;
      run.status = job.Status;
      run.itemsProcessed = job.JobItemsProcessed;
      run.totalItems = job.TotalJobItems;
      run.errors = job.NumberOfErrors;
      run.detail = job.ExtendedStatus;
      run.createdDate = job.CreatedDate;
      run.completedDate = job.CompletedDate;
      run.problem =
        FAILED.contains(job.Status) ||
        (job.NumberOfErrors != null &&
        job.NumberOfErrors > 0);
      if (run.problem) {
        result.issues.add(
          run.job +
            ' ' +
            job.Status.toLowerCase() +
            ' on ' +
            job.CreatedDate.format() +
            (String.isBlank(job.ExtendedStatus)
              ? '.'
              : ': ' + job.ExtendedStatus)
        );
      }
      result.runs.add(run);
    }
  }

  private static void addErrors(Console result) {
    Datetime week = System.now().addDays(-7);
    Datetime day = System.now().addDays(-1);
    Set<String> serious = new Set<String>{ 'ERROR', 'FATAL' };
    for (AggregateResult row : [
      SELECT Source__c source, COUNT(Id) total
      FROM Error_Log__c
      WHERE CreatedDate >= :week AND Severity__c IN :serious
      WITH USER_MODE
      GROUP BY Source__c
      ORDER BY COUNT(Id) DESC
      LIMIT 10
    ]) {
      ErrorSource source = new ErrorSource();
      source.source = (String) row.get('source');
      source.count = (Integer) row.get('total');
      result.errorSources.add(source);
    }
    result.recentErrors = [
      SELECT
        Id,
        Name,
        Severity__c,
        Source__c,
        Message__c,
        Record_Id__c,
        CreatedDate
      FROM Error_Log__c
      WHERE CreatedDate >= :week AND Severity__c IN :serious
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 20
    ];
    result.errorsLast24h = [
      SELECT COUNT()
      FROM Error_Log__c
      WHERE CreatedDate >= :day AND Severity__c IN :serious
      WITH USER_MODE
    ];
    if (result.errorsLast24h > 0) {
      result.issues.add(
        result.errorsLast24h + ' error(s) logged in the last 24 hours.'
      );
    }
  }

  private static void addQueues(Console result) {
    Datetime hourAgo = System.now().addHours(-1);
    Datetime soon = System.now().addHours(24);
    Datetime now = System.now();
    result.queues.add(
      queue(
        'reconciliation',
        'Reconciliation exceptions',
        [
          SELECT COUNT()
          FROM Student_Payment__c
          WHERE
            Status__c = 'Confirmed'
            AND Reconciliation_Status__c = 'Exception'
          WITH SYSTEM_MODE
        ],
        'Finance Desk → Reconciliation exceptions',
        'warning'
      )
    );
    result.queues.add(
      queue(
        'refunds',
        'Refunds awaiting approval',
        [
          SELECT COUNT()
          FROM Refund__c
          WHERE Status__c = 'Requested'
          WITH SYSTEM_MODE
        ],
        'Finance Desk → Refunds',
        'warning'
      )
    );
    result.queues.add(
      queue(
        'payouts',
        'Approved refunds to pay out',
        [
          SELECT COUNT()
          FROM Refund__c
          WHERE Status__c = 'Approved'
          WITH SYSTEM_MODE
        ],
        'Finance Desk → Refunds',
        'warning'
      )
    );
    result.queues.add(
      queue(
        'cover',
        'Sessions needing cover',
        [
          SELECT COUNT()
          FROM Class_Session__c
          WHERE Needs_Cover__c = TRUE AND Start__c >= :now
          WITH SYSTEM_MODE
        ],
        'Home → Cover Desk',
        'error'
      )
    );
    result.queues.add(
      queue(
        'messages_failed',
        'Messages failed (7 days)',
        [
          SELECT COUNT()
          FROM Message__c
          WHERE Status__c = 'Failed' AND CreatedDate = LAST_N_DAYS:7
          WITH SYSTEM_MODE
        ],
        'Check the email deliverability and the status detail on the message',
        'error'
      )
    );
    result.queues.add(
      queue(
        'messages_stuck',
        'Emails queued over an hour',
        [
          SELECT COUNT()
          FROM Message__c
          WHERE Status__c = 'Queued' AND CreatedDate < :hourAgo
          WITH SYSTEM_MODE
        ],
        'Run KEM Message Dispatch',
        'error'
      )
    );
    result.queues.add(
      queue(
        'overdue',
        'Overdue invoices',
        [
          SELECT COUNT()
          FROM Student_Invoice__c
          WHERE Overdue__c = TRUE
          WITH SYSTEM_MODE
        ],
        'Finance Desk → Overdue invoices (reminders go out daily)',
        'ok'
      )
    );
    result.queues.add(
      queue(
        'offers',
        'Waitlist offers expiring in 24 h',
        [
          SELECT COUNT()
          FROM Waitlist_Entry__c
          WHERE Status__c = 'Offered' AND Offer_Expires__c <= :soon
          WITH SYSTEM_MODE
        ],
        'Class page → Waitlist',
        'ok'
      )
    );
    for (Queue q : result.queues) {
      if (q.count > 0 && q.severity == 'error') {
        result.issues.add(q.count + ' ' + q.label.toLowerCase() + '.');
      }
    }
  }

  private static Queue queue(
    String key,
    String label,
    Integer count,
    String hint,
    String severity
  ) {
    Queue q = new Queue();
    q.key = key;
    q.label = label;
    q.count = count;
    q.hint = hint;
    q.severity = severity;
    return q;
  }

  private static Boolean hasFailure(Console result) {
    for (Schedule s : result.schedules) {
      if (s.missing) {
        return true;
      }
    }
    for (Run r : result.runs) {
      if (r.problem) {
        return true;
      }
    }
    return false;
  }

  public static Boolean isAdmin() {
    return Schema.SObjectType.Error_Log__c.isAccessible() &&
      Schema.SObjectType.Error_Log__c.isUpdateable();
  }

  private static void assertAdmin() {
    if (!isAdmin()) {
      throw new AppException('The operations console is for administrators.');
    }
  }
}
