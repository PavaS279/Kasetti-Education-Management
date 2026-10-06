/**
 * Einstein generative AI for Kasetti Education Management.
 *
 * Every assistant goes through generate(): the prompt comes from the
 * AI_Prompt__mdt catalogue (versioned instructions and template), the call
 * goes through the Einstein Models API and therefore the Einstein Trust
 * Layer (data masking, zero retention, audit), and every call is logged as
 * an AI_Interaction__c with model, prompt version, latency and outcome.
 * Staff then record whether they accepted, edited or rejected the result
 * (review()), which is how the benefit of AI is measured.
 *
 * Controls: Education Setting AI_Enabled (kill switch), AI_Disabled_Features
 * (per feature), the KEM Use AI custom permission, and AI_Model.
 *
 * Callouts: generate() makes a callout, so callers must not have pending DML
 * in the same transaction; the interaction is written after the callout.
 */
public with sharing class AiService {
  public static final String PERMISSION = 'KEM_Use_AI';
  public static final String DEFAULT_MODEL = 'sfdc_ai__DefaultGPT4Omni';

  /** Pluggable model access: Einstein in the org, a stub in tests. */
  public interface Provider {
    String complete(String model, String instructions, String message);
  }

  /** Test seam: the provider used instead of Einstein. */
  @TestVisible
  private static Provider testProvider;

  public class Result {
    @AuraEnabled
    public Boolean ok = false;
    @AuraEnabled
    public String text;
    @AuraEnabled
    public Id interactionId;
    @AuraEnabled
    public String feature;
    @AuraEnabled
    public String model;
    @AuraEnabled
    public Integer latencyMs;
    @AuraEnabled
    public String error;
  }

  public class Prompt {
    public String name;
    public String feature;
    public Integer version;
    public String instructions;
    public String template;
    public String model;
    public Integer maxWords;
    public Decimal minutesSaved;
  }

  // ---------------------------------------------------------------- access

  public static Boolean enabled() {
    return AppSettings.getString('AI_Enabled', 'On') == 'On';
  }

  public static Boolean featureEnabled(String feature) {
    if (!enabled()) {
      return false;
    }
    for (
      String part : AppSettings.getString('AI_Disabled_Features', '').split(',')
    ) {
      if (part.trim().equalsIgnoreCase(feature)) {
        return false;
      }
    }
    return true;
  }

  public static Boolean canUse() {
    return FeatureManagement.checkPermission(PERMISSION);
  }

  /** Throws a readable error when AI may not be used for this feature by this user. */
  public static void assertAllowed(String feature) {
    if (!enabled()) {
      throw new AppException(
        'AI assistants are switched off for the institution.'
      );
    }
    if (!featureEnabled(feature)) {
      throw new AppException('The ' + feature + ' assistant is switched off.');
    }
    if (!canUse()) {
      throw new AppException(
        'You do not have access to the AI assistants (KEM AI User).'
      );
    }
  }

  // ---------------------------------------------------------------- generation

  /** Renders the prompt with the values, calls Einstein and logs the interaction. */
  public static Result generate(
    String promptName,
    Map<String, String> values,
    Id recordId,
    Id branchId
  ) {
    Prompt prompt = prompt(promptName);
    assertAllowed(prompt.feature);
    String message = render(prompt.template, values);
    String instructions =
      prompt.instructions +
      (prompt.maxWords == null
        ? ''
        : '\nKeep the answer under ' + prompt.maxWords + ' words.');
    Result result = new Result();
    result.feature = prompt.feature;
    result.model = String.isBlank(prompt.model)
      ? AppSettings.getString('AI_Model', DEFAULT_MODEL)
      : prompt.model;
    Long started = System.currentTimeMillis();
    try {
      result.text = provider().complete(result.model, instructions, message);
      result.text = result.text == null ? '' : result.text.trim();
      result.ok = String.isNotBlank(result.text);
      if (!result.ok) {
        result.error = 'The model returned no text.';
      }
    } catch (Exception e) {
      result.error = e.getMessage();
      Logger.error('AiService.generate', e, recordId);
    }
    result.latencyMs = Integer.valueOf(System.currentTimeMillis() - started);
    result.interactionId = log(
      prompt,
      result,
      recordId,
      branchId,
      message.length()
    );
    return result;
  }

  /** Same as generate() but throws when the model fails, for callers that need text. */
  public static Result generateOrFail(
    String promptName,
    Map<String, String> values,
    Id recordId,
    Id branchId
  ) {
    Result result = generate(promptName, values, recordId, branchId);
    if (!result.ok) {
      throw new AppException(
        'The AI assistant could not answer just now. Please try again. (' +
          String.valueOf(result.error).left(150) +
          ')'
      );
    }
    return result;
  }

  @TestVisible
  private static String render(String template, Map<String, String> values) {
    String text = template == null ? '' : template;
    if (values != null) {
      for (String key : values.keySet()) {
        String value = values.get(key);
        text = text.replace('{{' + key + '}}', value == null ? '' : value);
      }
    }
    return text.replaceAll('\\{\\{\\w+\\}\\}', '');
  }

  public static Prompt prompt(String name) {
    List<AI_Prompt__mdt> rows = [
      SELECT
        DeveloperName,
        Feature__c,
        Version__c,
        Instructions__c,
        Template__c,
        Model__c,
        Max_Words__c,
        Minutes_Saved__c,
        Active__c
      FROM AI_Prompt__mdt
      WHERE DeveloperName = :name
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (rows.isEmpty() || !rows[0].Active__c) {
      throw new AppException('AI prompt ' + name + ' is not available.');
    }
    AI_Prompt__mdt row = rows[0];
    Prompt p = new Prompt();
    p.name = row.DeveloperName;
    p.feature = row.Feature__c;
    p.version = row.Version__c == null ? 1 : row.Version__c.intValue();
    p.instructions = row.Instructions__c == null ? '' : row.Instructions__c;
    p.template = row.Template__c;
    p.model = row.Model__c;
    p.maxWords = row.Max_Words__c == null ? null : row.Max_Words__c.intValue();
    p.minutesSaved = row.Minutes_Saved__c;
    return p;
  }

  private static Provider provider() {
    if (Test.isRunningTest()) {
      return testProvider != null ? testProvider : new EchoProvider();
    }
    return new EinsteinProvider();
  }

  /** Einstein Models API (chat generations) through the Trust Layer. */
  public class EinsteinProvider implements Provider {
    public String complete(String model, String instructions, String message) {
      aiplatform.ModelsAPI.createChatGenerations_Request request = new aiplatform.ModelsAPI.createChatGenerations_Request();
      request.modelName = model;
      aiplatform.ModelsAPI_ChatGenerationsRequest body = new aiplatform.ModelsAPI_ChatGenerationsRequest();
      List<aiplatform.ModelsAPI_ChatMessageRequest> messages = new List<aiplatform.ModelsAPI_ChatMessageRequest>();
      if (String.isNotBlank(instructions)) {
        aiplatform.ModelsAPI_ChatMessageRequest systemMessage = new aiplatform.ModelsAPI_ChatMessageRequest();
        systemMessage.role = 'system';
        systemMessage.content = instructions;
        messages.add(systemMessage);
      }
      aiplatform.ModelsAPI_ChatMessageRequest userMessage = new aiplatform.ModelsAPI_ChatMessageRequest();
      userMessage.role = 'user';
      userMessage.content = message;
      messages.add(userMessage);
      body.messages = messages;
      request.body = body;
      try {
        aiplatform.ModelsAPI.createChatGenerations_Response response = new aiplatform.ModelsAPI()
          .createChatGenerations(request);
        return response.Code200.generationDetails.generations[0].content;
      } catch (aiplatform.ModelsAPI.createChatGenerations_ResponseException e) {
        throw new AppException(
          'Einstein returned ' + e.responseCode + ': ' + e.getMessage()
        );
      }
    }
  }

  /** Default test provider: echoes the message so tests can see what was sent. */
  @TestVisible
  private class EchoProvider implements Provider {
    public String complete(String model, String instructions, String message) {
      return 'ECHO: ' + message;
    }
  }

  // ---------------------------------------------------------------- review

  /**
   * Records what the reviewer did with a result: Accepted (used unchanged),
   * Edited (used after changes; finalText measures how much), Rejected.
   */
  public static void review(
    Id interactionId,
    String outcome,
    String finalText,
    Integer rating,
    String feedback
  ) {
    if (
      !new Set<String>{ 'Accepted', 'Edited', 'Rejected', 'Not Applicable' }
        .contains(outcome)
    ) {
      throw new AppException('Choose Accepted, Edited or Rejected.');
    }
    if (rating != null && (rating < 1 || rating > 5)) {
      throw new AppException('Rating must be between 1 and 5.');
    }
    List<AI_Interaction__c> rows = [
      SELECT Id, OwnerId, Response__c, Prompt_Name__c, Outcome__c
      FROM AI_Interaction__c
      WHERE Id = :interactionId
      WITH SYSTEM_MODE
    ];
    if (
      rows.isEmpty() ||
      (rows[0].OwnerId != UserInfo.getUserId() && !OpsService.isAdmin())
    ) {
      throw new AppException('AI interaction not found.');
    }
    AI_Interaction__c row = rows[0];
    Decimal ratio = 0;
    String resolved = outcome;
    if (outcome == 'Accepted' || outcome == 'Edited') {
      ratio = editRatio(row.Response__c, finalText);
      resolved = ratio == 0 ? 'Accepted' : 'Edited';
    }
    Decimal minutes = 0;
    if (resolved == 'Accepted' || resolved == 'Edited') {
      Decimal perTask = 0;
      for (AI_Prompt__mdt p : [
        SELECT Minutes_Saved__c
        FROM AI_Prompt__mdt
        WHERE DeveloperName = :row.Prompt_Name__c
        WITH SYSTEM_MODE
      ]) {
        perTask = p.Minutes_Saved__c == null ? 0 : p.Minutes_Saved__c;
      }
      // Heavily edited drafts save less: scale by the share kept.
      minutes = (perTask * (1 - Math.min(ratio, 100) / 100)).setScale(1);
    }
    new Writer()
      .updateInteraction(
        new AI_Interaction__c(
          Id = row.Id,
          Outcome__c = resolved,
          Edit_Ratio__c = ratio,
          Rating__c = rating,
          Feedback__c = feedback == null ? null : feedback.left(255),
          Reviewed_By__c = UserInfo.getUserId(),
          Reviewed_On__c = System.now(),
          Minutes_Saved__c = minutes
        )
      );
  }

  /**
   * Replaces the stored response with a comparable form (for example
   * extracted fields as "Label: value" lines) before staff review it.
   */
  public static void replaceResponse(Id interactionId, String text) {
    new Writer()
      .updateInteraction(
        new AI_Interaction__c(
          Id = interactionId,
          Response__c = text == null ? null : text.left(32000)
        )
      );
  }

  /** Share of words changed between the draft and the text used (0-100). */
  @TestVisible
  private static Decimal editRatio(String draft, String finalText) {
    if (finalText == null) {
      return 0;
    }
    List<String> a = words(draft);
    List<String> b = words(finalText);
    if (a.isEmpty() && b.isEmpty()) {
      return 0;
    }
    // Word-level edit distance over at most 400 words each (bounded CPU).
    Integer n = Math.min(a.size(), 400);
    Integer m = Math.min(b.size(), 400);
    List<Integer> previous = new List<Integer>();
    for (Integer j = 0; j <= m; j++) {
      previous.add(j);
    }
    for (Integer i = 1; i <= n; i++) {
      List<Integer> current = new List<Integer>{ i };
      for (Integer j = 1; j <= m; j++) {
        Integer cost = a[i - 1] == b[j - 1] ? 0 : 1;
        current.add(
          Math.min(
            Math.min(current[j - 1] + 1, previous[j] + 1),
            previous[j - 1] + cost
          )
        );
      }
      previous = current;
    }
    Decimal distance = previous[m];
    return Math.min(100, (distance / Math.max(n, m) * 100)).setScale(1);
  }

  private static List<String> words(String text) {
    List<String> result = new List<String>();
    if (String.isBlank(text)) {
      return result;
    }
    for (String w : text.toLowerCase().split('\\s+')) {
      if (String.isNotBlank(w)) {
        result.add(w);
      }
    }
    return result;
  }

  // ---------------------------------------------------------------- logging

  /**
   * When true, interactions are kept in memory until flushLogs(), so several
   * callouts can run in one transaction (a callout cannot follow a write).
   */
  public static Boolean deferLogs = false;

  /**
   * Where requests come from: In-app (assistant panels, reviewed by staff),
   * Agentforce (actions in an agent conversation) or Evaluation.
   */
  public static String channel = CHANNEL_IN_APP;
  public static final String CHANNEL_IN_APP = 'In-app';
  public static final String CHANNEL_AGENT = 'Agentforce';
  public static final String CHANNEL_EVALUATION = 'Evaluation';
  private static List<AI_Interaction__c> pendingLogs = new List<AI_Interaction__c>();

  /** Writes interactions held while deferLogs was on; returns how many. */
  public static Integer flushLogs() {
    Integer count = pendingLogs.size();
    if (count > 0) {
      new Writer().insertInteractions(pendingLogs);
      pendingLogs = new List<AI_Interaction__c>();
    }
    return count;
  }

  private static Id log(
    Prompt prompt,
    Result result,
    Id recordId,
    Id branchId,
    Integer inputChars
  ) {
    AI_Interaction__c row = new AI_Interaction__c(
      Feature__c = prompt.feature,
      Prompt_Name__c = prompt.name,
      Prompt_Version__c = prompt.version,
      Model__c = result.model,
      Record_Id__c = recordId,
      Branch__c = branchId,
      Status__c = result.ok ? 'Succeeded' : 'Failed',
      Latency_Ms__c = result.latencyMs,
      Input_Chars__c = inputChars,
      Output_Chars__c = result.text == null ? 0 : result.text.length(),
      Response__c = result.text == null ? null : result.text.left(32000),
      Error__c = result.error == null ? null : result.error.left(255),
      Channel__c = channel,
      // Only in-app drafts come back for a staff review.
      Outcome__c = result.ok && channel == CHANNEL_IN_APP
        ? 'Pending Review'
        : 'Not Applicable'
    );
    if (deferLogs) {
      pendingLogs.add(row);
      return null;
    }
    try {
      new Writer().insertInteraction(row);
      return row.Id;
    } catch (Exception e) {
      Logger.error('AiService.log', e, recordId);
      return null;
    }
  }

  /** The interaction log is system-managed; users read their own rows. */
  private without sharing class Writer {
    void insertInteraction(AI_Interaction__c row) {
      Database.insert(row, AccessLevel.SYSTEM_MODE);
    }
    void insertInteractions(List<AI_Interaction__c> rows) {
      Database.insert(rows, AccessLevel.SYSTEM_MODE);
    }
    void updateInteraction(AI_Interaction__c row) {
      Database.update(row, AccessLevel.SYSTEM_MODE);
    }
  }
}
