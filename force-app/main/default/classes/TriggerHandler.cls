/**
 * Base class for all trigger handlers.
 *
 * Each trigger contains a single line: `new XyzTriggerHandler().run();`.
 * Subclasses override only the context methods they need. Handlers can be
 * disabled declaratively through Trigger_Control__mdt (DeveloperName equals
 * the handler class name) or programmatically through bypass().
 */
public virtual inherited sharing class TriggerHandler {
  private static final Set<String> BYPASSED = new Set<String>();
  private static Map<String, Trigger_Control__mdt> controls;

  @TestVisible
  private TriggerOperation context;
  @TestVisible
  private Boolean isTriggerExecuting;

  public TriggerHandler() {
    this.context = Trigger.operationType;
    this.isTriggerExecuting = Trigger.isExecuting;
  }

  public void run() {
    if (!isTriggerExecuting || context == null || isDisabled()) {
      return;
    }
    switch on context {
      when BEFORE_INSERT {
        beforeInsert(Trigger.new);
      }
      when BEFORE_UPDATE {
        beforeUpdate(Trigger.new, Trigger.oldMap);
      }
      when BEFORE_DELETE {
        beforeDelete(Trigger.old);
      }
      when AFTER_INSERT {
        afterInsert(Trigger.new);
      }
      when AFTER_UPDATE {
        afterUpdate(Trigger.new, Trigger.oldMap);
      }
      when AFTER_DELETE {
        afterDelete(Trigger.old);
      }
      when AFTER_UNDELETE {
        afterUndelete(Trigger.new);
      }
    }
  }

  protected virtual void beforeInsert(List<SObject> newRecords) {
  }
  protected virtual void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
  }
  protected virtual void beforeDelete(List<SObject> oldRecords) {
  }
  protected virtual void afterInsert(List<SObject> newRecords) {
  }
  protected virtual void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
  }
  protected virtual void afterDelete(List<SObject> oldRecords) {
  }
  protected virtual void afterUndelete(List<SObject> newRecords) {
  }

  /** Name used for bypass and Trigger_Control__mdt lookups. */
  protected virtual String getHandlerName() {
    return String.valueOf(this).substringBefore(':');
  }

  public static void bypass(String handlerName) {
    BYPASSED.add(handlerName);
  }

  public static void clearBypass(String handlerName) {
    BYPASSED.remove(handlerName);
  }

  public static Boolean isBypassed(String handlerName) {
    return BYPASSED.contains(handlerName);
  }

  @TestVisible
  private Boolean isDisabled() {
    String name = getHandlerName();
    if (BYPASSED.contains(name)) {
      return true;
    }
    if (controls == null) {
      controls = new Map<String, Trigger_Control__mdt>();
      for (
        Trigger_Control__mdt control : Trigger_Control__mdt.getAll().values()
      ) {
        controls.put(control.DeveloperName, control);
      }
    }
    Trigger_Control__mdt control = controls.get(name);
    return control != null && control.Disabled__c;
  }

  /** Returns the records whose value in any of the given fields changed. */
  protected List<SObject> changedRecords(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap,
    List<SObjectField> fields
  ) {
    List<SObject> changed = new List<SObject>();
    for (SObject record : newRecords) {
      SObject oldRecord = oldMap == null ? null : oldMap.get(record.Id);
      for (SObjectField field : fields) {
        if (oldRecord == null || record.get(field) != oldRecord.get(field)) {
          changed.add(record);
          break;
        }
      }
    }
    return changed;
  }
}
