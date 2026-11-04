/** Helpers for model output that should be JSON. */
public with sharing class AiJson {
  /** Removes Markdown code fences and text around the outermost JSON object or array. */
  public static String strip(String text) {
    if (text == null) {
      return '';
    }
    String t = text.trim();
    t = t.replaceAll('^```(json)?', '').replaceAll('```$', '').trim();
    Integer objectStart = t.indexOf('{');
    Integer arrayStart = t.indexOf('[');
    Integer start = objectStart < 0
      ? arrayStart
      : (arrayStart < 0 ? objectStart : Math.min(objectStart, arrayStart));
    if (start < 0) {
      return t;
    }
    Integer endIndex = t.charAt(start) == 123
      ? t.lastIndexOf('}')
      : t.lastIndexOf(']');
    return endIndex > start ? t.substring(start, endIndex + 1) : t;
  }

  public static Map<String, Object> parseObject(String text) {
    Object parsed = JSON.deserializeUntyped(strip(text));
    if (!(parsed instanceof Map<String, Object>)) {
      throw new AppException('The AI answer was not in the expected format.');
    }
    return (Map<String, Object>) parsed;
  }
}
