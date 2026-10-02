/** Lightning controller for the enrolment wizard and class roster. */
public with sharing class EnrolmentController {
  public class RosterRow {
    @AuraEnabled
    public Id enrolmentId;
    @AuraEnabled
    public Id learnerAccountId;
    @AuraEnabled
    public String learnerName;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Decimal agreedTotal;
    @AuraEnabled
    public String discountCode;
    @AuraEnabled
    public String discountApproval;
    @AuraEnabled
    public String billingStatus;
  }

  public class Roster {
    @AuraEnabled
    public CourseOffering offering;
    @AuraEnabled
    public List<RosterRow> rows = new List<RosterRow>();
    @AuraEnabled
    public Integer seatsTaken;
    @AuraEnabled
    public Boolean canApproveDiscounts;
  }

  @AuraEnabled(cacheable=true)
  public static Roster getRoster(Id offeringId) {
    try {
      Roster roster = new Roster();
      List<CourseOffering> offerings = [
        SELECT
          Id,
          Name,
          LearningCourseId,
          LearningCourse.Name,
          Branch__c,
          Branch__r.Name,
          Room__r.Name,
          Delivery_Mode__c,
          Class_Status__c,
          EnrollmentCapacity,
          Seats_Taken__c,
          Seats_Available__c,
          StartDate,
          EndDate,
          PrimaryFaculty.Name,
          Teacher_User__r.Name
        FROM CourseOffering
        WHERE Id = :offeringId
        WITH USER_MODE
      ];
      if (offerings.isEmpty()) {
        throw new AppException('Class not found or not accessible.');
      }
      roster.offering = offerings[0];
      roster.canApproveDiscounts = FeatureManagement.checkPermission(
        EnrolmentService.APPROVE_PERMISSION
      );
      Integer taken = 0;
      for (CourseOfferingParticipant p : [
        SELECT
          Id,
          ParticipantAccountId,
          ParticipantContact.Name,
          ParticipationStatus,
          StartDate,
          Agreed_Total__c,
          Discount__r.Code__c,
          Discount_Approval_Status__c,
          Billing_Status__c
        FROM CourseOfferingParticipant
        WHERE
          CourseOfferingId = :offeringId
          AND ParticipantAffiliation = 'Student'
        WITH USER_MODE
        ORDER BY ParticipantContact.Name
      ]) {
        RosterRow row = new RosterRow();
        row.enrolmentId = p.Id;
        row.learnerAccountId = p.ParticipantAccountId;
        row.learnerName = p.ParticipantContact.Name;
        row.status = p.ParticipationStatus;
        row.startDate = p.StartDate;
        row.agreedTotal = p.Agreed_Total__c;
        row.discountCode = p.Discount__r?.Code__c;
        row.discountApproval = p.Discount_Approval_Status__c;
        row.billingStatus = p.Billing_Status__c;
        roster.rows.add(row);
        if (SeatService.SEAT_STATUSES.contains(p.ParticipationStatus)) {
          taken++;
        }
      }
      roster.seatsTaken = taken;
      return roster;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** Classes a learner can join: open or running, optionally for one course and branch. */
  @AuraEnabled(cacheable=true)
  public static List<CourseOffering> getEnrollableClasses(
    Id courseId,
    Id branchId
  ) {
    try {
      String query =
        'SELECT Id, Name, LearningCourseId, LearningCourse.Name, Branch__r.Name, Delivery_Mode__c, Class_Status__c, ' +
        'EnrollmentCapacity, Seats_Taken__c, Seats_Available__c, StartDate, EndDate, PrimaryFaculty.Name ' +
        'FROM CourseOffering WHERE Class_Status__c IN (\'Open\', \'In Progress\')';
      if (courseId != null) {
        query += ' AND LearningCourseId = :courseId';
      }
      if (branchId != null) {
        query += ' AND Branch__c = :branchId';
      }
      query += ' ORDER BY StartDate ASC NULLS LAST LIMIT 100';
      return (List<CourseOffering>) Database.queryWithBinds(
        query,
        new Map<String, Object>{
          'courseId' => courseId,
          'branchId' => branchId
        },
        AccessLevel.USER_MODE
      );
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static EnrolmentService.Preview previewEnrolment(
    EnrolmentService.EnrolmentRequest request
  ) {
    try {
      return EnrolmentService.preview(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static EnrolmentService.EnrolmentResult enrol(
    EnrolmentService.EnrolmentRequest request
  ) {
    try {
      return EnrolmentService.enrol(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void withdraw(
    Id enrolmentId,
    String reason,
    Date effectiveDate
  ) {
    try {
      EnrolmentService.withdraw(enrolmentId, reason, effectiveDate);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void decideDiscount(Id enrolmentId, Boolean approve) {
    try {
      EnrolmentService.decideDiscount(enrolmentId, approve);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static List<Account> searchLearners(String term) {
    try {
      List<Account> learners = new List<Account>();
      for (Account person : LearnerService.searchPeople(term)) {
        if (LearnerService.isLearner(person.KEM_Role__c)) {
          learners.add(person);
        }
      }
      return learners;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
