/** Lightning controller for the Einstein assistants and the AI console. */
public with sharing class AiController {
  @AuraEnabled
  public static AiService.Result draftEnquiryReply(Id leadId, String note) {
    try {
      return AiAssistantService.draftEnquiryReply(leadId, note);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** Records the reply as sent: a completed task on the enquiry, last contacted now, and the review outcome. */
  @AuraEnabled
  public static void recordEnquiryReply(
    Id leadId,
    String reply,
    Id interactionId
  ) {
    try {
      if (String.isBlank(reply)) {
        throw new AppException('The reply is empty.');
      }
      Task t = new Task(
        WhoId = leadId,
        Subject = 'Email reply (AI-assisted)',
        Description = reply.left(32000),
        Status = 'Completed',
        ActivityDate = Date.today(),
        TaskSubtype = 'Email'
      );
      insert as user t;
      update as user new Lead(Id = leadId, Last_Contacted__c = System.now());
      if (interactionId != null) {
        AiService.review(interactionId, 'Edited', reply, null, null);
      }
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static AiService.Result summarise(Id recordId) {
    try {
      return AiAssistantService.summarise(recordId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static AiService.Result learnerProgress(Id learnerAccountId) {
    try {
      return AiAssistantService.learnerProgress(learnerAccountId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static AiService.Result reportComment(Id enrolmentId) {
    try {
      return AiAssistantService.reportComment(enrolmentId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static List<AiAssistantService.CommentLearner> classLearners(
    Id offeringId
  ) {
    try {
      return AiAssistantService.classLearners(offeringId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void useReportComment(
    Id enrolmentId,
    String comment,
    Id interactionId
  ) {
    try {
      AiAssistantService.useReportComment(enrolmentId, comment, interactionId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static AiAssistantService.Answer askPolicy(String question) {
    try {
      return AiAssistantService.askPolicy(question);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void review(
    Id interactionId,
    String outcome,
    String finalText,
    Integer rating,
    String feedback
  ) {
    try {
      AiService.review(interactionId, outcome, finalText, rating, feedback);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static AiConsoleService.Console getConsole(Integer days) {
    try {
      return AiConsoleService.console(days);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static AiEvaluationService.RunSummary runEvaluation() {
    try {
      return AiEvaluationService.run(null);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** Whether the AI panels should show for this user (switch and permission). */
  @AuraEnabled(cacheable=true)
  public static Boolean isAvailable(String feature) {
    return AiService.canUse() &&
      (String.isBlank(feature)
        ? AiService.enabled()
        : AiService.featureEnabled(feature));
  }
}
