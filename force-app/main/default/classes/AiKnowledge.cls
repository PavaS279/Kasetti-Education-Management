/**
 * Knowledge for the policy assistant: AI_Knowledge__mdt articles ranked by
 * word overlap with the question, with {{Setting:Key}} tokens replaced by the
 * live Education Setting values, so answers quote the institution's current
 * policy rather than numbers frozen in text.
 */
public with sharing class AiKnowledge {
  private static final Set<String> STOP_WORDS = new Set<String>{
    'the',
    'and',
    'for',
    'are',
    'can',
    'how',
    'what',
    'when',
    'who',
    'why',
    'does',
    'did',
    'with',
    'from',
    'this',
    'that',
    'have',
    'has',
    'will',
    'our',
    'their',
    'there',
    'about',
    'into',
    'than',
    'then',
    'they',
    'you',
    'your',
    'not',
    'any',
    'all',
    'per',
    'its',
    'was'
  };

  public static List<AI_Knowledge__mdt> retrieve(
    String question,
    Integer count
  ) {
    Set<String> terms = terms(question);
    List<Scored> scored = new List<Scored>();
    for (AI_Knowledge__mdt article : [
      SELECT DeveloperName, MasterLabel, Topic__c, Keywords__c, Body__c
      FROM AI_Knowledge__mdt
      WHERE Active__c = TRUE
      WITH SYSTEM_MODE
      LIMIT 200
    ]) {
      Set<String> heading = terms(
        article.MasterLabel + ' ' + article.Topic__c + ' ' + article.Keywords__c
      );
      Set<String> body = terms(article.Body__c);
      Decimal score = 0;
      for (String term : terms) {
        if (heading.contains(term) || heading.contains(singular(term))) {
          score += 3;
        } else if (body.contains(term) || body.contains(singular(term))) {
          score += 1;
        }
      }
      if (score > 0) {
        scored.add(new Scored(article, score));
      }
    }
    scored.sort();
    List<AI_Knowledge__mdt> result = new List<AI_Knowledge__mdt>();
    for (Scored s : scored) {
      if (result.size() < count) {
        result.add(s.article);
      }
    }
    return result;
  }

  /** Replaces {{Setting:Key}} with the current setting value. */
  public static String render(String body) {
    if (body == null) {
      return '';
    }
    Matcher m = Pattern.compile('\\{\\{Setting:(\\w+)\\}\\}').matcher(body);
    String result = body;
    while (m.find()) {
      String value = AppSettings.getString(m.group(1), 'not set');
      result = result.replace(
        m.group(0),
        String.isBlank(value) ? 'not set' : value
      );
    }
    return result;
  }

  @TestVisible
  private static Set<String> terms(String text) {
    Set<String> result = new Set<String>();
    if (String.isBlank(text)) {
      return result;
    }
    for (String word : text.toLowerCase().split('[^a-z0-9]+')) {
      if (word.length() >= 3 && !STOP_WORDS.contains(word)) {
        result.add(word);
      }
    }
    return result;
  }

  private static String singular(String word) {
    return word.endsWith('s') && word.length() > 3 ? word.removeEnd('s') : word;
  }

  private class Scored implements Comparable {
    AI_Knowledge__mdt article;
    Decimal score;
    Scored(AI_Knowledge__mdt article, Decimal score) {
      this.article = article;
      this.score = score;
    }
    public Integer compareTo(Object other) {
      Decimal o = ((Scored) other).score;
      return score == o ? 0 : (score > o ? -1 : 1);
    }
  }
}
