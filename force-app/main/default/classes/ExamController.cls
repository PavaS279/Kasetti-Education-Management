/** Lightning controller for the exam desk (F4.10). */
public with sharing class ExamController {
  @AuraEnabled
  public static List<ExamService.ExamSummary> getExams(Id branchId) {
    try {
      return ExamService.exams(branchId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static ExamService.ExamDetail getExam(Id examId) {
    try {
      return ExamService.exam(examId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static ExamService.StepResult registerCandidates(Id examId) {
    try {
      return ExamService.registerCandidates(examId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static ExamService.StepResult checkEligibility(Id examId) {
    try {
      return ExamService.checkEligibility(examId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void overrideCandidate(Id candidateId, String reason) {
    try {
      ExamService.overrideCandidate(candidateId, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static ExamService.StepResult allocateSeats(
    Id examId,
    List<Id> roomIds
  ) {
    try {
      return ExamService.allocateSeats(examId, roomIds);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static ExamService.StepResult issueTickets(Id examId) {
    try {
      return ExamService.issueTickets(examId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static ExamService.MarkSheet getMarkSheet(Id paperId) {
    try {
      return ExamService.markSheet(paperId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void saveMarks(Id paperId, List<ExamService.MarkRow> rows) {
    try {
      ExamService.saveMarks(paperId, rows);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id publishMarks(Id paperId) {
    try {
      return ExamService.publishMarks(paperId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
