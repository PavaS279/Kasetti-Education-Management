/**
 * Agentforce action: learners at risk of leaving (from the retention risk
 * scores), optionally for one branch. No generative AI: live data only.
 */
public with sharing class AgentAtRiskLearners {
  public static final Integer MAX_ROWS = 15;

  public class Request {
    @InvocableVariable(
      label='Branch'
      description='Optional branch name, code or record Id. Leave empty for all branches the user can see.'
    )
    public String branch;
    @InvocableVariable(
      label='Risk level'
      description='High, Medium or All (default All).'
    )
    public String level;
  }

  public class Response {
    @InvocableVariable(
      label='Learners at risk'
      description='One line per learner: name, class, branch, risk score and reasons, and follow-up status. Show as a list.'
    )
    public String learners;
    @InvocableVariable(
      label='High risk count'
      description='Number of high-risk enrolments.'
    )
    public Integer high = 0;
    @InvocableVariable(
      label='Medium risk count'
      description='Number of medium-risk enrolments.'
    )
    public Integer medium = 0;
  }

  @InvocableMethod(
    label='List KEM Learners at Risk'
    description='Lists Kasetti learners at risk of dropping out (low attendance, absences in a row, overdue fees, falling results) with their risk reasons and follow-up status, for all branches or one branch.'
    category='Kasetti Education'
  )
  public static List<Response> findAtRisk(List<Request> requests) {
    List<Response> responses = new List<Response>();
    for (Request r : requests) {
      Response response = new Response();
      try {
        Id branchId = String.isBlank(r.branch)
          ? null
          : AgentBranchBrief.findBranch(r.branch).Id;
        String level = String.isBlank(r.level) ? 'All' : r.level.trim();
        if (!new Set<String>{ 'All', 'High', 'Medium' }.contains(level)) {
          level = 'All';
        }
        RetentionService.Desk desk = RetentionService.desk(branchId, level);
        response.high = desk.high;
        response.medium = desk.medium;
        response.learners = describe(desk.atRisk);
      } catch (Exception e) {
        response.learners = AgentSupport.failure(e);
      }
      responses.add(response);
    }
    return responses;
  }

  @TestVisible
  private static String describe(List<RetentionService.AtRisk> rows) {
    if (rows.isEmpty()) {
      return 'No learners are currently flagged at risk.';
    }
    List<String> lines = new List<String>();
    for (Integer i = 0; i < Math.min(rows.size(), MAX_ROWS); i++) {
      RetentionService.AtRisk row = rows[i];
      lines.add(
        '- ' +
          row.learner +
          ' (' +
          row.className +
          (row.branch == null ? '' : ', ' + row.branch) +
          '): ' +
          row.level +
          ' risk, score ' +
          row.score +
          (String.isBlank(row.reasons) ? '' : '; ' + row.reasons) +
          (String.isBlank(row.status) ? '' : '; follow-up: ' + row.status)
      );
    }
    if (rows.size() > MAX_ROWS) {
      lines.add(
        '…and ' + (rows.size() - MAX_ROWS) + ' more in the Retention desk.'
      );
    }
    return String.join(lines, '\n');
  }
}
