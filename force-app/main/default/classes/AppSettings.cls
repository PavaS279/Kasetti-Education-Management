/**
 * Read access to Education_Setting__mdt with typed accessors and defaults.
 * Branch-level overrides are resolved by callers (see BranchPolicy).
 */
public inherited sharing class AppSettings {
  @TestVisible
  private static Map<String, String> overrides = new Map<String, String>();
  private static Map<String, Education_Setting__mdt> settings;

  public static String getString(String key, String defaultValue) {
    if (overrides.containsKey(key)) {
      return overrides.get(key);
    }
    if (settings == null) {
      settings = Education_Setting__mdt.getAll();
    }
    Education_Setting__mdt setting = settings.get(key);
    return setting == null || String.isBlank(setting.Value__c)
      ? defaultValue
      : setting.Value__c;
  }

  public static Decimal getDecimal(String key, Decimal defaultValue) {
    String value = getString(key, null);
    try {
      return value == null ? defaultValue : Decimal.valueOf(value);
    } catch (TypeException e) {
      return defaultValue;
    }
  }

  public static Integer getInteger(String key, Integer defaultValue) {
    Decimal value = getDecimal(key, null);
    return value == null ? defaultValue : value.intValue();
  }

  public static Boolean getBoolean(String key, Boolean defaultValue) {
    String value = getString(key, null);
    return value == null ? defaultValue : Boolean.valueOf(value);
  }
}
