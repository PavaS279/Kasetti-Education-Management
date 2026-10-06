/**
 * Agentforce action: answers a staff question about the institution's
 * policies from the KEM knowledge base and live settings only, with sources.
 */
public with sharing class AgentPolicyAnswer {
  public class Request {
    @InvocableVariable(
      label='Question'
      description='The staff member\'s question about fees, payments, refunds, attendance, admissions, waitlists, grading, library, messaging or AI use, in their own words.'
      required=true
    )
    public String question;
  }

  public class Response {
    @InvocableVariable(
      label='Answer'
      description='The answer, written only from the institution\'s policies. Show it to the user as is.'
    )
    public String answer;
    @InvocableVariable(
      label='Sources'
      description='The policy articles the answer is based on. Always show them after the answer.'
    )
    public String sources;
    @InvocableVariable(
      label='Confident'
      description='False when the policies do not clearly answer the question; then tell the user to check with an administrator.'
    )
    public Boolean confident = false;
  }

  @InvocableMethod(
    label='Answer a KEM Policy Question'
    description='Answers questions about Kasetti institution policies and procedures (fees and invoices, payments, refunds and credit, attendance, admissions and offers, waitlists and transfers, grading and report cards, library, messaging consent, AI use) from the institution\'s knowledge base, with sources. Never answer these questions without this action.'
    category='Kasetti Education'
  )
  public static List<Response> answer(List<Request> requests) {
    AgentSupport.begin();
    List<Response> responses = new List<Response>();
    for (Request r : requests) {
      Response response = new Response();
      try {
        AiAssistantService.Answer a = AiAssistantService.askPolicy(r.question);
        response.answer = a.answer;
        response.sources = String.join(a.sources, '; ');
        response.confident = a.confident == true;
      } catch (Exception e) {
        response.answer = AgentSupport.failure(e);
      }
      responses.add(response);
    }
    AgentSupport.finish();
    return responses;
  }
}
