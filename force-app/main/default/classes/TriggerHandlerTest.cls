@IsTest
private class TriggerHandlerTest {
  private class RecordingHandler extends TriggerHandler {
    public List<String> calls = new List<String>();
    protected override void beforeInsert(List<SObject> r) {
      calls.add('beforeInsert');
    }
    protected override void beforeUpdate(List<SObject> r, Map<Id, SObject> o) {
      calls.add('beforeUpdate');
    }
    protected override void beforeDelete(List<SObject> r) {
      calls.add('beforeDelete');
    }
    protected override void afterInsert(List<SObject> r) {
      calls.add('afterInsert');
    }
    protected override void afterUpdate(List<SObject> r, Map<Id, SObject> o) {
      calls.add('afterUpdate');
    }
    protected override void afterDelete(List<SObject> r) {
      calls.add('afterDelete');
    }
    protected override void afterUndelete(List<SObject> r) {
      calls.add('afterUndelete');
    }
    protected override String getHandlerName() {
      return 'RecordingHandler';
    }
    public List<SObject> changed(
      List<SObject> r,
      Map<Id, SObject> o,
      List<SObjectField> f
    ) {
      return changedRecords(r, o, f);
    }
  }

  @IsTest
  static void dispatchesEveryContext() {
    RecordingHandler handler = new RecordingHandler();
    handler.isTriggerExecuting = true;
    for (TriggerOperation op : TriggerOperation.values()) {
      handler.context = op;
      handler.run();
    }
    Assert.areEqual(
      7,
      handler.calls.size(),
      'Every trigger context should dispatch once'
    );
  }

  @IsTest
  static void doesNothingOutsideTrigger() {
    RecordingHandler handler = new RecordingHandler();
    handler.run();
    Assert.areEqual(
      0,
      handler.calls.size(),
      'Handler must not run outside trigger context'
    );
  }

  @IsTest
  static void bypassSkipsHandler() {
    RecordingHandler handler = new RecordingHandler();
    handler.isTriggerExecuting = true;
    handler.context = TriggerOperation.BEFORE_INSERT;
    TriggerHandler.bypass('RecordingHandler');
    Assert.isTrue(
      TriggerHandler.isBypassed('RecordingHandler'),
      'Bypass should be recorded'
    );
    handler.run();
    Assert.areEqual(0, handler.calls.size(), 'Bypassed handler must not run');
    TriggerHandler.clearBypass('RecordingHandler');
    handler.run();
    Assert.areEqual(
      1,
      handler.calls.size(),
      'Handler should run after bypass is cleared'
    );
  }

  @IsTest
  static void changedRecordsDetectsFieldChanges() {
    Branch__c oldBranch = new Branch__c(
      Id = TestUtil.fakeId(Branch__c.SObjectType),
      Name = 'A'
    );
    Branch__c sameBranch = new Branch__c(Id = oldBranch.Id, Name = 'A');
    Branch__c newBranch = new Branch__c(Id = oldBranch.Id, Name = 'B');
    RecordingHandler handler = new RecordingHandler();
    Map<Id, SObject> oldMap = new Map<Id, SObject>{ oldBranch.Id => oldBranch };
    Assert.areEqual(
      0,
      handler.changed(
          new List<SObject>{ sameBranch },
          oldMap,
          new List<SObjectField>{ Branch__c.Name }
        )
        .size(),
      'No change expected'
    );
    Assert.areEqual(
      1,
      handler.changed(
          new List<SObject>{ newBranch },
          oldMap,
          new List<SObjectField>{ Branch__c.Name }
        )
        .size(),
      'Change expected'
    );
    Assert.areEqual(
      1,
      handler.changed(
          new List<SObject>{ newBranch },
          null,
          new List<SObjectField>{ Branch__c.Name }
        )
        .size(),
      'Inserts always count as changed'
    );
  }
}
