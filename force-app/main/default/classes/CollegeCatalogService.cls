/** Read-only catalogue used by the KT College app. */
public with sharing class CollegeCatalogService {
  public class Row {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String detail;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal metric;
  }

  public class Dashboard {
    @AuraEnabled
    public List<Row> campuses = new List<Row>();
    @AuraEnabled
    public List<Row> programmes = new List<Row>();
    @AuraEnabled
    public List<Row> branches = new List<Row>();
    @AuraEnabled
    public List<Row> campusBranches = new List<Row>();
    @AuraEnabled
    public List<Row> sections = new List<Row>();
    @AuraEnabled
    public List<Row> subjects = new List<Row>();
    @AuraEnabled
    public Integer sectionSubjects = 0;
  }

  public static Dashboard dashboard() {
    requireAccess();
    Dashboard result = new Dashboard();
    for (Branch__c campus : [
      SELECT Id, Name, Campus_Code__c, Active__c
      FROM Branch__c
      WHERE Institution_Type__c = 'College'
      WITH USER_MODE
      ORDER BY Name
      LIMIT 100
    ]) {
      result.campuses.add(
        row(
          campus.Id,
          campus.Name,
          'Campus ' + campus.Campus_Code__c,
          campus.Active__c ? 'Active' : 'Inactive',
          null
        )
      );
    }
    for (LearningProgram programme : [
      SELECT
        Id,
        Name,
        Programme_Code__c,
        Duration_Years__c,
        Terms_Per_Year__c,
        Active__c
      FROM LearningProgram
      WHERE Active__c = TRUE
      WITH USER_MODE
      ORDER BY Name
      LIMIT 100
    ]) {
      result.programmes.add(
        row(
          programme.Id,
          programme.Name,
          programme.Duration_Years__c +
            ' years · ' +
            programme.Terms_Per_Year__c +
            ' terms/year',
          programme.Active__c ? 'Active' : 'Inactive',
          null
        )
      );
    }
    for (LearningCourse branch : [
      SELECT Id, Name, Branch_Code__c, Curriculum_Version__c, Programme__r.Name
      FROM LearningCourse
      WHERE RecordType.DeveloperName = 'College_Branch'
      WITH USER_MODE
      ORDER BY Programme__r.Name, Name
      LIMIT 300
    ]) {
      result.branches.add(
        row(
          branch.Id,
          branch.Name,
          branch.Programme__r.Name +
            ' · curriculum ' +
            branch.Curriculum_Version__c,
          branch.Branch_Code__c,
          null
        )
      );
    }
    for (Campus_Branch__c offering : [
      SELECT
        Id,
        Name,
        Campus__r.Name,
        Branch__r.Name,
        Academic_Year__c,
        Admissions_Open__c,
        Intake_Regular__c,
        Intake_Lateral__c
      FROM Campus_Branch__c
      WITH USER_MODE
      ORDER BY Campus__r.Name, Branch__r.Name, Academic_Year__c
      LIMIT 500
    ]) {
      result.campusBranches.add(
        row(
          offering.Id,
          offering.Branch__r.Name,
          offering.Campus__r.Name + ' · ' + offering.Academic_Year__c,
          offering.Admissions_Open__c ? 'Admissions open' : 'Admissions closed',
          nvl(offering.Intake_Regular__c) + nvl(offering.Intake_Lateral__c)
        )
      );
    }
    Set<Id> visibleSectionIds = new Set<Id>();
    for (CourseOffering section : [
      SELECT
        Id,
        Name,
        Academic_Year__c,
        Year_Of_Study__c,
        Section_Code__c,
        Class_Status__c,
        EnrollmentCapacity,
        Campus_Branch__r.Campus__r.Name
      FROM CourseOffering
      WHERE RecordType.DeveloperName = 'College_Section'
      WITH USER_MODE
      ORDER BY Academic_Year__c DESC, Name
      LIMIT 500
    ]) {
      visibleSectionIds.add(section.Id);
      result.sections.add(
        row(
          section.Id,
          section.Name,
          section.Campus_Branch__r.Campus__r.Name +
            ' · Year ' +
            section.Year_Of_Study__c +
            ' · Section ' +
            section.Section_Code__c,
          section.Class_Status__c,
          section.EnrollmentCapacity
        )
      );
    }
    for (Subject__c subject : [
      SELECT
        Id,
        Name,
        Subject_Code__c,
        Year_Of_Study__c,
        Term__c,
        Branch__r.Name
      FROM Subject__c
      WITH USER_MODE
      ORDER BY Branch__r.Name, Year_Of_Study__c, Term__c, Subject_Code__c
      LIMIT 1000
    ]) {
      result.subjects.add(
        row(
          subject.Id,
          subject.Subject_Code__c + ' · ' + subject.Name,
          subject.Branch__r.Name +
            ' · Year ' +
            subject.Year_Of_Study__c +
            ' · Term ' +
            subject.Term__c,
          null,
          null
        )
      );
    }
    // Education Cloud's licensed permission set does not surface custom
    // master-detail child OLS reliably. Count only assignments whose parent
    // section was already returned in user mode; no inaccessible section can
    // contribute to this system-mode aggregate.
    result.sectionSubjects = visibleSectionIds.isEmpty()
      ? 0
      : [
          SELECT COUNT()
          FROM Section_Subject__c
          WHERE Section__c IN :visibleSectionIds
          WITH SYSTEM_MODE
        ];
    return result;
  }

  private static Row row(
    Id id,
    String name,
    String detail,
    String status,
    Decimal metric
  ) {
    Row value = new Row();
    value.id = id;
    value.name = name;
    value.detail = detail;
    value.status = status;
    value.metric = metric;
    return value;
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  private static void requireAccess() {
    List<Schema.SObjectType> required = new List<Schema.SObjectType>{
      Branch__c.SObjectType,
      LearningProgram.SObjectType,
      LearningCourse.SObjectType,
      Campus_Branch__c.SObjectType,
      CourseOffering.SObjectType,
      Subject__c.SObjectType
    };
    for (Schema.SObjectType objectType : required) {
      if (!objectType.getDescribe().isAccessible()) {
        throw new AppException(
          'You do not have access to the college catalogue (' +
            objectType.getDescribe().getName() +
            ').'
        );
      }
    }
  }
}
