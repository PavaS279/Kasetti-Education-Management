/**
 * Offline evaluation of the AI prompts against the live model: every active
 * AI_Eval_Case__mdt supplies token values and checks (phrases that must or
 * must not appear, word limit, valid JSON). Results are stored as
 * AI_Evaluation__c rows per run, so prompt or model changes can be compared.
 */
public with sharing class AiEvaluationService {
  public class RunSummary {
    @AuraEnabled
    public String runLabel;
    @AuraEnabled
    public Integer cases = 0;
    @AuraEnabled
    public Integer passed = 0;
    @AuraEnabled
    public Decimal averageScore;
    @AuraEnabled
    public Integer averageLatencyMs;
  }

  /** Runs every active case (or those of one prompt). Administrators only. */
  public static RunSummary run(String promptName) {
    if (!OpsService.isAdmin()) {
      throw new AppException('Only administrators can run AI evaluations.');
    }
    List<AI_Eval_Case__mdt> cases = [
      SELECT
        DeveloperName,
        Prompt__c,
        Context_Json__c,
        Must_Contain__c,
        Must_Not_Contain__c,
        Expect_Json__c
      FROM AI_Eval_Case__mdt
      WHERE Active__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY Prompt__c, DeveloperName
      LIMIT 50
    ];
    String label = 'Run ' + System.now().format('yyyy-MM-dd HH:mm');
    List<AI_Evaluation__c> rows = new List<AI_Evaluation__c>();
    // All callouts first, then every write (a callout cannot follow a write).
    AiService.deferLogs = true;
    AiService.channel = AiService.CHANNEL_EVALUATION;
    try {
      for (AI_Eval_Case__mdt c : cases) {
        if (String.isNotBlank(promptName) && c.Prompt__c != promptName) {
          continue;
        }
        rows.add(evaluate(c, label));
      }
    } finally {
      AiService.deferLogs = false;
      AiService.channel = AiService.CHANNEL_IN_APP;
    }
    AiService.flushLogs();
    new Writer().insertRows(rows);
    return summarise(label, rows);
  }

  @TestVisible
  private static AI_Evaluation__c evaluate(AI_Eval_Case__mdt c, String label) {
    AiService.Prompt prompt = AiService.prompt(c.Prompt__c);
    Map<String, String> values = new Map<String, String>();
    if (String.isNotBlank(c.Context_Json__c)) {
      Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
        c.Context_Json__c
      );
      for (String key : raw.keySet()) {
        values.put(
          key,
          raw.get(key) == null ? '' : String.valueOf(raw.get(key))
        );
      }
    }
    AiService.Result result = AiService.generate(
      c.Prompt__c,
      values,
      null,
      null
    );
    String text = result.text == null ? '' : result.text;
    List<String> notes = new List<String>();
    Integer checks = 0;
    Integer ok = 0;
    if (!result.ok) {
      notes.add('FAIL model error: ' + result.error);
      checks++;
    }
    for (String phrase : split(c.Must_Contain__c)) {
      checks++;
      if (text.containsIgnoreCase(phrase)) {
        ok++;
      } else {
        notes.add('FAIL missing "' + phrase + '"');
      }
    }
    for (String phrase : split(c.Must_Not_Contain__c)) {
      checks++;
      if (!text.containsIgnoreCase(phrase)) {
        ok++;
      } else {
        notes.add('FAIL contains "' + phrase + '"');
      }
    }
    if (prompt.maxWords != null) {
      checks++;
      Integer count = text.split('\\s+').size();
      // Allow 20% over the stated limit.
      if (count <= prompt.maxWords * 1.2) {
        ok++;
      } else {
        notes.add('FAIL ' + count + ' words (limit ' + prompt.maxWords + ')');
      }
    }
    if (c.Expect_Json__c) {
      checks++;
      try {
        JSON.deserializeUntyped(AiJson.strip(text));
        ok++;
      } catch (Exception e) {
        notes.add('FAIL not valid JSON');
      }
    }
    Decimal score = checks == 0
      ? 100
      : (Decimal.valueOf(ok) / checks * 100).setScale(1);
    return new AI_Evaluation__c(
      Run_Label__c = label,
      Prompt_Name__c = c.Prompt__c,
      Prompt_Version__c = prompt.version,
      Case_Name__c = c.DeveloperName,
      Model__c = result.model,
      Passed__c = result.ok && ok == checks,
      Score__c = score,
      Checks__c = notes.isEmpty()
        ? 'All ' + checks + ' checks passed'
        : String.join(notes, '\n').left(255),
      Response__c = text.left(32000),
      Latency_Ms__c = result.latencyMs
    );
  }

  public static RunSummary latest() {
    List<AI_Evaluation__c> last = [
      SELECT Run_Label__c
      FROM AI_Evaluation__c
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (last.isEmpty()) {
      return null;
    }
    String label = last[0].Run_Label__c;
    return summarise(
      label,
      [
        SELECT Passed__c, Score__c, Latency_Ms__c
        FROM AI_Evaluation__c
        WHERE Run_Label__c = :label
        WITH SYSTEM_MODE
      ]
    );
  }

  private static RunSummary summarise(
    String label,
    List<AI_Evaluation__c> rows
  ) {
    RunSummary s = new RunSummary();
    s.runLabel = label;
    Decimal scores = 0;
    Decimal latency = 0;
    for (AI_Evaluation__c r : rows) {
      s.cases++;
      s.passed += r.Passed__c ? 1 : 0;
      scores += r.Score__c == null ? 0 : r.Score__c;
      latency += r.Latency_Ms__c == null ? 0 : r.Latency_Ms__c;
    }
    if (s.cases > 0) {
      s.averageScore = (scores / s.cases).setScale(1);
      s.averageLatencyMs = (latency / s.cases).intValue();
    }
    return s;
  }

  private static List<String> split(String value) {
    List<String> parts = new List<String>();
    if (String.isBlank(value)) {
      return parts;
    }
    for (String p : value.split('\\|')) {
      if (String.isNotBlank(p)) {
        parts.add(p.trim());
      }
    }
    return parts;
  }

  private without sharing class Writer {
    void insertRows(List<AI_Evaluation__c> rows) {
      Database.insert(rows, AccessLevel.SYSTEM_MODE);
    }
  }
}
