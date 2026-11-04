/**
 * Agentforce action: a progress summary of one learner (classes,
 * attendance, results), written for staff to review before sharing.
 */
public with sharing class AgentLearnerSummary {
  public class Request {
    @InvocableVariable(
      label='Learner'
      description='The learner\'s name (or record Id) from the conversation. If no name was given, ask the user for it.'
      required=true
    )
    public String learner;
  }

  public class Response {
    @InvocableVariable(
      label='Summary'
      description='The learner progress summary. Show it to the user and remind them it is a draft to check before sharing with a family.'
    )
    public String summary;
    @InvocableVariable(
      label='Learner Id'
      description='The learner record Id, when one learner was found.'
    )
    public Id learnerId;
    @InvocableVariable(
      label='Learner name'
      description='The learner\'s full name.'
    )
    public String learnerName;
  }

  @InvocableMethod(
    label='Summarise a KEM Learner\'s Progress'
    description='Summarises a Kasetti learner\'s progress: their classes, attendance, recent results and suggested next steps. Use it when staff ask how a learner (student) is doing.'
    category='Kasetti Education'
  )
  public static List<Response> summarise(List<Request> requests) {
    AgentSupport.begin();
    List<Response> responses = new List<Response>();
    for (Request r : requests) {
      Response response = new Response();
      try {
        Account learner = (Account) AgentSupport.resolve(
          'Account',
          r.learner,
          'IsPersonAccount = TRUE',
          'learner'
        );
        response.learnerId = learner.Id;
        response.learnerName = learner.Name;
        response.summary = AiAssistantService.learnerProgress(learner.Id).text;
      } catch (Exception e) {
        response.summary = AgentSupport.failure(e);
      }
      responses.add(response);
    }
    AgentSupport.finish();
    return responses;
  }
}
