/** Lightning boundary for the read-only KT College catalogue. */
public with sharing class CollegeCatalogController {
  public class RecordHeader {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String detail;
  }

  @AuraEnabled(cacheable=true)
  public static CollegeCatalogService.Dashboard getDashboard() {
    try {
      return CollegeCatalogService.dashboard();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static RecordHeader getRecordHeader(Id recordId) {
    try {
      if (recordId == null) {
        throw new AppException('Open a college branch or section.');
      }
      RecordHeader result = new RecordHeader();
      if (recordId.getSObjectType() == Branch__c.SObjectType) {
        Branch__c campus = [
          SELECT Name, Campus_Code__c, Active__c, Institution_Type__c
          FROM Branch__c
          WHERE Id = :recordId
          WITH USER_MODE
        ];
        if (campus.Institution_Type__c != 'College') {
          throw new AppException('This record is not a college campus.');
        }
        result.label = 'Campus';
        result.name = campus.Name;
        result.detail =
          'Campus ' +
          campus.Campus_Code__c +
          ' Â· ' +
          (campus.Active__c ? 'Active' : 'Inactive');
      } else if (recordId.getSObjectType() == LearningCourse.SObjectType) {
        LearningCourse branch = [
          SELECT
            Name,
            Branch_Code__c,
            Programme__r.Name,
            RecordType.DeveloperName
          FROM LearningCourse
          WHERE Id = :recordId
          WITH USER_MODE
        ];
        if (branch.RecordType.DeveloperName != 'College_Branch') {
          throw new AppException('This record is not a college branch.');
        }
        result.label = 'Branch';
        result.name = branch.Name;
        result.detail =
          branch.Programme__r.Name +
          ' · ' +
          branch.Branch_Code__c;
      } else if (recordId.getSObjectType() == CourseOffering.SObjectType) {
        CourseOffering section = [
          SELECT
            Name,
            Academic_Year__c,
            Year_Of_Study__c,
            Section_Code__c,
            Campus_Branch__r.Campus__r.Name,
            RecordType.DeveloperName
          FROM CourseOffering
          WHERE Id = :recordId
          WITH USER_MODE
        ];
        if (section.RecordType.DeveloperName != 'College_Section') {
          throw new AppException('This record is not a college section.');
        }
        result.label = 'Section';
        result.name = section.Name;
        result.detail =
          section.Campus_Branch__r.Campus__r.Name +
          ' · ' +
          section.Academic_Year__c +
          ' · Year ' +
          section.Year_Of_Study__c +
          ' · ' +
          section.Section_Code__c;
      } else if (recordId.getSObjectType() == LearningProgram.SObjectType) {
        LearningProgram programme = [
          SELECT
            Name,
            Programme_Code__c,
            Qualification_Level__c,
            Duration_Years__c,
            Active__c
          FROM LearningProgram
          WHERE Id = :recordId
          WITH USER_MODE
        ];
        result.label = 'Programme';
        result.name = programme.Name;
        result.detail =
          programme.Programme_Code__c +
          ' · ' +
          programme.Qualification_Level__c +
          ' · ' +
          programme.Duration_Years__c +
          ' years · ' +
          (programme.Active__c ? 'Active' : 'Inactive');
      } else if (recordId.getSObjectType() == Campus_Branch__c.SObjectType) {
        Campus_Branch__c campusBranch = [
          SELECT
            Name,
            Campus__r.Name,
            Branch__r.Name,
            Academic_Year__c,
            Admissions_Open__c
          FROM Campus_Branch__c
          WHERE Id = :recordId
          WITH USER_MODE
        ];
        result.label = 'Campus Branch';
        result.name = campusBranch.Name;
        result.detail =
          campusBranch.Campus__r.Name +
          ' · ' +
          campusBranch.Branch__r.Name +
          ' · ' +
          campusBranch.Academic_Year__c +
          ' · Admissions ' +
          (campusBranch.Admissions_Open__c ? 'open' : 'closed');
      } else if (recordId.getSObjectType() == Subject__c.SObjectType) {
        Subject__c subject = [
          SELECT
            Name,
            Subject_Code__c,
            Branch__r.Name,
            Year_Of_Study__c,
            Term__c,
            Active__c
          FROM Subject__c
          WHERE Id = :recordId
          WITH USER_MODE
        ];
        result.label = 'Subject';
        result.name = subject.Name;
        result.detail =
          subject.Subject_Code__c +
          ' · ' +
          subject.Branch__r.Name +
          ' · Year ' +
          subject.Year_Of_Study__c +
          ' · Term ' +
          subject.Term__c +
          ' · ' +
          (subject.Active__c ? 'Active' : 'Inactive');
      } else if (recordId.getSObjectType() == Section_Subject__c.SObjectType) {
        // Section Subject is private behind its visible section. Querying the
        // assignment in system mode avoids the org's custom-object OLS gap;
        // the USER_MODE parent query is the authorization boundary.
        Section_Subject__c assignment = [
          SELECT
            Name,
            Section__c,
            Section__r.Name,
            Subject__r.Name,
            Subject__r.Subject_Code__c,
            Faculty__c,
            Faculty__r.Name,
            Term__c,
            Status__c
          FROM Section_Subject__c
          WHERE Id = :recordId
          WITH SYSTEM_MODE
        ];
        CourseOffering visibleSection = [
          SELECT Id
          FROM CourseOffering
          WHERE Id = :assignment.Section__c
          WITH USER_MODE
        ];
        result.label = 'Section Subject';
        result.name = assignment.Subject__r.Name;
        result.detail =
          assignment.Section__r.Name +
          ' · ' +
          assignment.Subject__r.Subject_Code__c +
          ' · Term ' +
          assignment.Term__c +
          (assignment.Faculty__c == null
            ? ''
            : ' · ' + assignment.Faculty__r.Name) +
          ' · ' +
          assignment.Status__c;
      } else {
        throw new AppException(
          'This record is not supported by the KT College header.'
        );
      }
      return result;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
