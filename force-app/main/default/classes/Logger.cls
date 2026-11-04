/**
 * Application logger. Entries are buffered and published as Log_Event__e
 * (publish-immediately), then persisted to Error_Log__c by
 * LogEventTriggerHandler, so entries survive transaction rollback.
 *
 * Usage:
 *   Logger.error('EnrollmentService.enrol', e, recordId);
 *   Logger.flush();
 * error() flushes automatically; info/warn/debug are flushed on demand.
 */
public without sharing class Logger {
  public enum Level {
    DEBUG,
    INFO,
    WARN,
    ERROR,
    FATAL
  }

  private static final Integer MAX_TEXT = 131000;
  private static final List<Log_Event__e> BUFFER = new List<Log_Event__e>();
  @TestVisible
  private static List<Log_Event__e> published = new List<Log_Event__e>();
  private static String transactionId;
  private static Level threshold;

  public static void debug(String source, String message) {
    add(Level.DEBUG, source, message, null, null, null);
  }

  public static void info(String source, String message) {
    add(Level.INFO, source, message, null, null, null);
  }

  public static void warn(String source, String message, Id recordId) {
    add(Level.WARN, source, message, null, recordId, null);
  }

  public static void error(String source, Exception e, Id recordId) {
    add(Level.ERROR, source, e.getMessage(), e, recordId, null);
    flush();
  }

  public static void error(
    String source,
    String message,
    Id recordId,
    String context
  ) {
    add(Level.ERROR, source, message, null, recordId, context);
    flush();
  }

  /** Logs every failed row of a partial-success DML operation. */
  public static void errors(String source, List<Database.SaveResult> results) {
    for (Database.SaveResult result : results) {
      if (!result.isSuccess()) {
        List<String> messages = new List<String>();
        for (Database.Error err : result.getErrors()) {
          messages.add(err.getStatusCode() + ': ' + err.getMessage());
        }
        add(
          Level.ERROR,
          source,
          String.join(messages, '\n'),
          null,
          result.getId(),
          null
        );
      }
    }
    flush();
  }

  public static void flush() {
    if (BUFFER.isEmpty()) {
      return;
    }
    List<Log_Event__e> events = BUFFER.clone();
    BUFFER.clear();
    published.addAll(events);
    List<Database.SaveResult> results = EventBus.publish(events);
    for (Database.SaveResult result : results) {
      if (!result.isSuccess()) {
        System.debug(
          LoggingLevel.ERROR,
          'Log publish failed: ' + result.getErrors()
        );
      }
    }
  }

  private static void add(
    Level severity,
    String source,
    String message,
    Exception e,
    Id recordId,
    String context
  ) {
    System.debug(toSystemLevel(severity), source + ': ' + message);
    if (severity.ordinal() < getThreshold().ordinal()) {
      return;
    }
    BUFFER.add(
      new Log_Event__e(
        Severity__c = severity.name(),
        Source__c = truncate(source, 255),
        Message__c = truncate(message, MAX_TEXT),
        Exception_Type__c = e == null ? null : e.getTypeName(),
        Stack_Trace__c = e == null
          ? null
          : truncate(e.getStackTraceString(), MAX_TEXT),
        Record_Id__c = recordId,
        Context__c = truncate(context, MAX_TEXT),
        Transaction_Id__c = getTransactionId(),
        Running_User_Id__c = UserInfo.getUserId()
      )
    );
  }

  private static Level getThreshold() {
    if (threshold == null) {
      threshold = Level.INFO;
      String configured = AppSettings.getString('Log_Level', 'INFO');
      for (Level candidate : Level.values()) {
        if (candidate.name() == configured) {
          threshold = candidate;
        }
      }
    }
    return threshold;
  }

  private static String getTransactionId() {
    if (transactionId == null) {
      transactionId = Request.getCurrent().getRequestId();
    }
    return transactionId;
  }

  private static LoggingLevel toSystemLevel(Level severity) {
    switch on severity {
      when DEBUG {
        return LoggingLevel.DEBUG;
      }
      when INFO {
        return LoggingLevel.INFO;
      }
      when WARN {
        return LoggingLevel.WARN;
      }
      when else {
        return LoggingLevel.ERROR;
      }
    }
  }

  private static String truncate(String value, Integer maxLength) {
    return value == null ? null : value.abbreviate(maxLength);
  }
}
