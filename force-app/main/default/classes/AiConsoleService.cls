/**
 * Measured benefit of the AI assistants: usage, review outcomes, edit size,
 * ratings, minutes saved, latency and failures per feature, plus the latest
 * offline evaluation. Administrators see everyone's use; others their own.
 */
public with sharing class AiConsoleService {
  public class FeatureStats {
    @AuraEnabled
    public String feature;
    @AuraEnabled
    public Integer calls = 0;
    @AuraEnabled
    public Integer failed = 0;
    @AuraEnabled
    public Integer reviewed = 0;
    @AuraEnabled
    public Integer accepted = 0;
    @AuraEnabled
    public Integer edited = 0;
    @AuraEnabled
    public Integer rejected = 0;
    @AuraEnabled
    public Decimal acceptanceRate;
    @AuraEnabled
    public Decimal averageEdit;
    @AuraEnabled
    public Decimal averageRating;
    @AuraEnabled
    public Integer averageLatencyMs;
    @AuraEnabled
    public Decimal minutesSaved = 0;
    private Decimal editSum = 0;
    private Decimal editCount = 0;
    private Decimal ratingSum = 0;
    private Decimal ratingCount = 0;
    private Decimal latencySum = 0;
    private Decimal latencyCount = 0;
  }

  public class Console {
    @AuraEnabled
    public Boolean enabled;
    @AuraEnabled
    public String model;
    @AuraEnabled
    public String disabledFeatures;
    @AuraEnabled
    public Boolean canUse;
    @AuraEnabled
    public Boolean isAdmin;
    @AuraEnabled
    public Integer days;
    @AuraEnabled
    public List<FeatureStats> features = new List<FeatureStats>();
    @AuraEnabled
    public FeatureStats totals = new FeatureStats();
    @AuraEnabled
    public Integer users = 0;
    @AuraEnabled
    public AiEvaluationService.RunSummary evaluation;
  }

  public static Console console(Integer days) {
    Integer span = days == null || days <= 0 ? 30 : Math.min(days, 365);
    Console c = new Console();
    c.days = span;
    c.enabled = AiService.enabled();
    c.model = AppSettings.getString('AI_Model', AiService.DEFAULT_MODEL);
    c.disabledFeatures = AppSettings.getString('AI_Disabled_Features', '');
    c.canUse = AiService.canUse();
    c.isAdmin = OpsService.isAdmin();
    Datetime since = System.now().addDays(-span);
    Id me = UserInfo.getUserId();
    String scope = c.isAdmin ? '' : ' AND OwnerId = :me';
    Map<String, Object> binds = new Map<String, Object>{
      'since' => since,
      'me' => me
    };
    Map<String, FeatureStats> byFeature = new Map<String, FeatureStats>();
    for (
      AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT Feature__c feature, Status__c status, Outcome__c outcome, COUNT(Id) total, AVG(Edit_Ratio__c) edit, ' +
          'AVG(Rating__c) rating, AVG(Latency_Ms__c) latency, SUM(Minutes_Saved__c) minutes ' +
          'FROM AI_Interaction__c WHERE CreatedDate >= :since' +
          scope +
          ' GROUP BY Feature__c, Status__c, Outcome__c',
        binds,
        AccessLevel.SYSTEM_MODE
      )
    ) {
      String feature = (String) row.get('feature');
      if (!byFeature.containsKey(feature)) {
        FeatureStats fs = new FeatureStats();
        fs.feature = feature;
        byFeature.put(feature, fs);
      }
      add(byFeature.get(feature), row);
      add(c.totals, row);
    }
    List<String> names = new List<String>(byFeature.keySet());
    names.sort();
    for (String name : names) {
      c.features.add(finish(byFeature.get(name)));
    }
    c.totals.feature = 'All features';
    finish(c.totals);
    Object users = ((List<AggregateResult>) Database.queryWithBinds(
        'SELECT COUNT_DISTINCT(OwnerId) users FROM AI_Interaction__c WHERE CreatedDate >= :since' +
        scope,
        binds,
        AccessLevel.SYSTEM_MODE
      ))[0]
      .get('users');
    c.users = users == null ? 0 : (Integer) users;
    if (c.isAdmin) {
      c.evaluation = AiEvaluationService.latest();
    }
    return c;
  }

  private static void add(FeatureStats fs, AggregateResult row) {
    Integer total = (Integer) row.get('total');
    String status = (String) row.get('status');
    String outcome = (String) row.get('outcome');
    fs.calls += total;
    if (status != 'Succeeded') {
      fs.failed += total;
    }
    if (outcome == 'Accepted') {
      fs.accepted += total;
    } else if (outcome == 'Edited') {
      fs.edited += total;
    } else if (outcome == 'Rejected') {
      fs.rejected += total;
    }
    if (outcome == 'Accepted' || outcome == 'Edited' || outcome == 'Rejected') {
      fs.reviewed += total;
    }
    fs.minutesSaved += row.get('minutes') == null
      ? 0
      : (Decimal) row.get('minutes');
    if (row.get('edit') != null && outcome == 'Edited') {
      fs.editSum += (Decimal) row.get('edit') * total;
      fs.editCount += total;
    }
    if (row.get('rating') != null) {
      fs.ratingSum += (Decimal) row.get('rating') * total;
      fs.ratingCount += total;
    }
    if (row.get('latency') != null) {
      fs.latencySum += (Decimal) row.get('latency') * total;
      fs.latencyCount += total;
    }
  }

  private static FeatureStats finish(FeatureStats fs) {
    fs.acceptanceRate = fs.reviewed == 0
      ? null
      : (Decimal.valueOf(fs.accepted + fs.edited) /
          fs.reviewed *
          100)
          .setScale(1);
    fs.averageEdit = fs.editCount == 0
      ? null
      : (fs.editSum / fs.editCount).setScale(1);
    fs.averageRating = fs.ratingCount == 0
      ? null
      : (fs.ratingSum / fs.ratingCount).setScale(1);
    fs.averageLatencyMs = fs.latencyCount == 0
      ? null
      : (fs.latencySum / fs.latencyCount).intValue();
    fs.minutesSaved = fs.minutesSaved.setScale(1);
    return fs;
  }
}
