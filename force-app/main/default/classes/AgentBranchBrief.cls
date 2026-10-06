/**
 * Agentforce action: a short briefing on a branch (seats, attendance,
 * enquiries, retention risk and, for finance users, fees) from live figures.
 */
public with sharing class AgentBranchBrief {
  public class Request {
    @InvocableVariable(
      label='Branch'
      description='The branch (centre or campus) name, code or record Id from the conversation.'
      required=true
    )
    public String branch;
  }

  public class Response {
    @InvocableVariable(
      label='Briefing'
      description='The branch briefing. Show it to the user as is.'
    )
    public String briefing;
    @InvocableVariable(label='Branch Id' description='The branch record Id.')
    public Id branchId;
  }

  @InvocableMethod(
    label='Brief Me on a KEM Branch'
    description='Gives a short briefing on how a Kasetti branch is doing: seats filled, attendance, open enquiries, learners at risk and fees outstanding. Use it for questions like "How is the Whitefield branch doing?".'
    category='Kasetti Education'
  )
  public static List<Response> brief(List<Request> requests) {
    AgentSupport.begin();
    List<Response> responses = new List<Response>();
    for (Request r : requests) {
      Response response = new Response();
      try {
        SObject branch = findBranch(r.branch);
        response.branchId = branch.Id;
        response.briefing = AiAssistantService.branchBrief(branch.Id).text;
      } catch (Exception e) {
        response.briefing = AgentSupport.failure(e);
      }
      responses.add(response);
    }
    return responses;
  }

  /** Branch by code first (exact), then by Id or name. */
  public static SObject findBranch(String value) {
    if (String.isNotBlank(value)) {
      String code = value.trim().toUpperCase();
      List<Branch__c> byCode = [
        SELECT Id, Name
        FROM Branch__c
        WHERE Branch_Code__c = :code
        WITH USER_MODE
        LIMIT 1
      ];
      if (!byCode.isEmpty()) {
        return byCode[0];
      }
    }
    return AgentSupport.resolve('Branch__c', value, null, 'branch');
  }
}
