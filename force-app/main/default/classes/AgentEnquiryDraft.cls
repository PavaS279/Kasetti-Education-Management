/**
 * Agentforce action: drafts a reply to an enquiry from the enquiry, live
 * course prices and upcoming classes. Nothing is sent: the counsellor
 * reviews and sends it from the enquiry page.
 */
public with sharing class AgentEnquiryDraft {
  public class Request {
    @InvocableVariable(
      label='Enquiry'
      description='The enquirer\'s name (or enquiry record Id) from the conversation.'
      required=true
    )
    public String enquiry;
    @InvocableVariable(
      label='Counsellor note'
      description='Optional points the counsellor wants in the reply, for example a trial class offer.'
    )
    public String note;
  }

  public class Response {
    @InvocableVariable(
      label='Draft reply'
      description='The draft email reply. Show it and tell the user it has not been sent: they can edit and send it from the enquiry page (AI reply panel).'
    )
    public String draft;
    @InvocableVariable(
      label='Enquiry Id'
      description='The enquiry (Lead) record Id.'
    )
    public Id enquiryId;
  }

  @InvocableMethod(
    label='Draft a KEM Enquiry Reply'
    description='Drafts an email reply to a Kasetti enquiry (prospective learner or parent) using the course they asked about, current fees and upcoming class dates. The draft is never sent automatically.'
    category='Kasetti Education'
  )
  public static List<Response> draft(List<Request> requests) {
    AgentSupport.begin();
    List<Response> responses = new List<Response>();
    for (Request r : requests) {
      Response response = new Response();
      try {
        SObject lead = AgentSupport.resolve(
          'Lead',
          r.enquiry,
          'IsConverted = FALSE',
          'open enquiry'
        );
        response.enquiryId = lead.Id;
        response.draft = AiAssistantService.draftEnquiryReply(lead.Id, r.note)
          .text;
      } catch (Exception e) {
        response.draft = AgentSupport.failure(e);
      }
      responses.add(response);
    }
    return responses;
  }
}
