/**
 * Agentforce action: the planning forecast (new enrolments and seats,
 * invoicing and expected cash) for all branches or one, as text. The
 * figures come from ForecastService; no generative AI is used here.
 */
public with sharing class AgentForecast {
  public class Request {
    @InvocableVariable(
      label='Branch'
      description='Optional branch name, code or record Id. Leave empty for all branches.'
    )
    public String branch;
    @InvocableVariable(
      label='Months'
      description='How many months ahead, 1 to 6 (default 3).'
    )
    public Integer months;
  }

  public class Response {
    @InvocableVariable(
      label='Forecast'
      description='The forecast as short lines: enrolments with range and accuracy, admissions pipeline, seat shortfalls, invoicing and expected cash. Show it as is and mention the accuracy.'
    )
    public String forecast;
  }

  @InvocableMethod(
    label='Forecast KEM Enrolments and Revenue'
    description='Forecasts Kasetti new enrolments, seat shortfalls by course, invoicing and expected cash for the next months, for all branches or one, with accuracy from a backtest.'
    category='Kasetti Education'
  )
  public static List<Response> forecast(List<Request> requests) {
    List<Response> responses = new List<Response>();
    for (Request r : requests) {
      Response response = new Response();
      try {
        Id branchId = String.isBlank(r.branch)
          ? null
          : AgentBranchBrief.findBranch(r.branch).Id;
        response.forecast = describe(
          ForecastService.forecast(branchId, r.months)
        );
      } catch (Exception e) {
        response.forecast = AgentSupport.failure(e);
      }
      responses.add(response);
    }
    Logger.flush();
    return responses;
  }

  @TestVisible
  private static String describe(ForecastService.Forecast f) {
    List<String> lines = new List<String>();
    if (f.enrolments != null) {
      lines.add(
        'New enrolments: ' + points(f.enrolments) + accuracy(f.enrolments)
      );
      lines.add(
        'Admissions pipeline: about ' +
          f.pipelineExpected +
          ' enrolments expected from the current enquiries, applications, offers and waitlist.'
      );
      for (ForecastService.SeatRow s : f.seats) {
        if (s.status != 'OK') {
          lines.add(
            'Seats ' +
              s.status.toLowerCase() +
              ': ' +
              s.course +
              ' has ' +
              s.freeSeats +
              ' free seats for about ' +
              s.demand +
              ' expected learners.'
          );
        }
      }
    }
    if (f.revenue != null) {
      lines.add('Invoicing: ' + points(f.revenue) + accuracy(f.revenue));
      List<String> cash = new List<String>();
      for (ForecastService.CashRow c : f.cash) {
        cash.add(c.label + ' ' + c.expectedCash);
      }
      lines.add(
        'Expected cash: ' +
          String.join(cash, ', ') +
          ' (collection rate ' +
          (f.collectionRate == null ? 'unknown' : f.collectionRate + '%') +
          ', open receivables ' +
          f.openReceivables +
          ').'
      );
    }
    if (lines.isEmpty()) {
      return 'You do not have access to enrolment or finance figures.';
    }
    lines.addAll(f.notes);
    return String.join(lines, '\n');
  }

  private static String points(ForecastService.Series s) {
    List<String> parts = new List<String>();
    for (ForecastService.Point p : s.points) {
      if (p.isFuture) {
        parts.add(
          p.label + ' ' + p.forecast + ' (' + p.low + '–' + p.high + ')'
        );
      }
    }
    return String.join(parts, ', ');
  }

  private static String accuracy(ForecastService.Series s) {
    return '; accuracy ' +
      s.accuracy.toLowerCase() +
      (s.mape == null ? '' : ' (backtest error ' + s.mape + '%)') +
      '.';
  }
}
