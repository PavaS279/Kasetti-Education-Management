@IsTest
private class ForecastTest {
  private class StubProvider implements AiService.Provider {
    String lastMessage;
    public String complete(String model, String instructions, String message) {
      lastMessage = message;
      return 'Enrolments look steady. Maths seats are short: open another class.';
    }
  }

  private static List<Decimal> values(List<Integer> numbers) {
    List<Decimal> result = new List<Decimal>();
    for (Integer n : numbers) {
      result.add(n);
    }
    return result;
  }

  // ---------------------------------------------------------------- maths

  @IsTest
  static void growingSeriesUsesTrend() {
    ForecastMath.Fit fit = ForecastMath.fit(
      values(
        new List<Integer>{ 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21 }
      ),
      3
    );
    Assert.areEqual(ForecastMath.TREND, fit.method, 'Trend wins the backtest');
    Assert.areEqual(12, fit.historyMonths, 'History');
    Assert.isTrue(fit.mape < 5, 'Accurate on a straight line: ' + fit.mape);
    Assert.areEqual('Good', ForecastMath.accuracy(fit.mape), 'Accuracy band');
    Assert.isTrue(
      Math.abs(fit.forecasts[0] - 22) < 1 &&
        Math.abs(fit.forecasts[2] - 24) < 1.5,
      'Continues the line: ' + fit.forecasts
    );
    Assert.isTrue(
      fit.lows[2] <= fit.forecasts[2] && fit.highs[2] >= fit.forecasts[2],
      'Range around the forecast'
    );
  }

  @IsTest
  static void flatSeriesUsesAverage() {
    ForecastMath.Fit fit = ForecastMath.fit(
      values(new List<Integer>{ 0, 0, 5, 5, 5, 5, 5, 5, 5 }),
      2
    );
    Assert.areEqual(7, fit.historyMonths, 'Leading zeros trimmed');
    Assert.areEqual(
      ForecastMath.AVERAGE,
      fit.method,
      'Average for flat demand'
    );
    Assert.isTrue(fit.forecasts[1] == 5, 'Level: ' + fit.forecasts);
    Assert.isTrue(fit.mape == 0, 'No backtest error: ' + fit.mape);
  }

  @IsTest
  static void seasonalSeriesUsesLastYear() {
    List<Integer> pattern = new List<Integer>{
      5,
      5,
      5,
      5,
      5,
      5,
      5,
      5,
      5,
      30,
      20,
      5
    };
    List<Integer> history = new List<Integer>();
    history.addAll(pattern);
    history.addAll(pattern);
    ForecastMath.Fit fit = ForecastMath.fit(values(history), 2);
    Assert.areEqual(ForecastMath.SEASONAL, fit.method, 'Seasonal pattern');
    Assert.isTrue(fit.mape == 0, 'Peaks predicted exactly: ' + fit.mape);
    Assert.isTrue(
      fit.forecasts[0] == 5 && fit.forecasts[1] == 5,
      'Quiet months repeat: ' + fit.forecasts
    );
    Assert.isTrue(
      ForecastMath.candidates(24).contains(ForecastMath.SEASONAL),
      'Candidate'
    );
    Assert.isFalse(
      ForecastMath.candidates(12).contains(ForecastMath.SEASONAL),
      'Needs 15 months'
    );
  }

  @IsTest
  static void shortOrEmptyHistory() {
    ForecastMath.Fit fit = ForecastMath.fit(
      values(new List<Integer>{ 4, 6 }),
      3
    );
    Assert.isNull(fit.mape, 'No backtest under 6 months');
    Assert.areEqual(
      'Not enough history',
      ForecastMath.accuracy(fit.mape),
      'Label'
    );
    Assert.isTrue(fit.forecasts[0] == 5, 'Average of what there is');
    ForecastMath.Fit empty = ForecastMath.fit(new List<Decimal>(), 2);
    Assert.isTrue(empty.forecasts[1] == 0, 'Nothing to forecast');
    Assert.isNull(
      ForecastMath.mape(
        values(new List<Integer>{ 0, 0 }),
        values(new List<Integer>{ 1, 2 })
      ),
      'No error from zero actuals'
    );
    Assert.areEqual('Fair', ForecastMath.accuracy(25), 'Fair');
    Assert.areEqual('Low', ForecastMath.accuracy(50), 'Low');
  }

  // ---------------------------------------------------------------- service

  @IsTest
  static void forecastFromHistoryPipelineSeatsAndCash() {
    TestDataFactory.createReferenceData();
    User admin = TestDataFactory.admin();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.assignPermissionSets(
        admin.Id,
        new List<String>{ 'KEM_AI_User' }
      );
    }
    StubProvider stub = new StubProvider();
    AiService.testProvider = stub;
    System.runAs(admin) {
      MessageService.disabled = true;
      IntegrationService.disabled = true;
      Branch__c branch = TestDataFactory.buildBranch();
      branch.Branch_Code__c = 'FC-01';
      insert branch;
      LearningCourse course = TestDataFactory.createCourse('Forecast Maths');
      insert new Fee_Price__c(
        Learning_Course__c = course.Id,
        Branch__c = branch.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Monthly',
        Amount__c = 1000,
        Effective_From__c = Date.today().addYears(-2)
      );
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        8
      );
      insert TestDataFactory.buildEnquiry(branch.Id);
      List<Account> learners = new List<Account>();
      for (Integer i = 0; i < 7; i++) {
        learners.add(
          PersonAccountService.buildPerson(
            'Fc' + i,
            'Learner' + i,
            null,
            null,
            branch.Id,
            'Learner'
          )
        );
      }
      insert learners;
      List<Id> enrolmentIds = new List<Id>();
      for (Account learner : learners) {
        EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
        request.learnerAccountId = learner.Id;
        request.offeringId = offering.Id;
        enrolmentIds.add(EnrolmentService.enrol(request).enrolmentId);
      }
      // One new enrolment in each of the last seven months.
      Date month = Date.today().toStartOfMonth();
      for (Integer i = 0; i < enrolmentIds.size(); i++) {
        Test.setCreatedDate(
          enrolmentIds[i],
          Datetime.newInstance(
            month.addMonths(-(i + 1)).addDays(9),
            Time.newInstance(10, 0, 0, 0)
          )
        );
      }
      Test.startTest();
      BillingService.createInvoice(enrolmentIds[0], true);
      ForecastService.Forecast f = ForecastController.getForecast(branch.Id, 3);
      Assert.isTrue(f.showEnrolments && f.showFinance, 'Admin sees both');
      Assert.areEqual(3, f.horizon, 'Horizon');
      Assert.areEqual(7, f.enrolments.historyMonths, 'Seven months of history');
      Assert.areEqual(
        ForecastMath.AVERAGE,
        f.enrolments.method,
        'Steady intake'
      );
      Assert.areEqual('Good', f.enrolments.accuracy, 'Backtested');
      Assert.isTrue(
        f.enrolments.nextTotal == 3,
        'One a month: ' + f.enrolments.nextTotal
      );
      Assert.areEqual(15, f.enrolments.points.size(), '12 past + 3 future');
      Assert.isTrue(f.enrolments.points[14].isFuture, 'Future points last');

      Assert.areEqual(4, f.pipeline.size(), 'Four stages');
      Assert.areEqual(1, f.pipeline[0].count, 'Open enquiry');
      Assert.isTrue(f.pipeline[0].assumed, 'No closed enquiries yet');
      Assert.isTrue(
        f.pipeline[0].rate == 21,
        '30% x 70% assumed: ' + f.pipeline[0].rate
      );

      Assert.areEqual(1, f.seats.size(), 'One course');
      ForecastService.SeatRow seats = f.seats[0];
      Assert.isTrue(
        seats.freeSeats == 1,
        '8 seats, 7 taken: ' + seats.freeSeats
      );
      Assert.isTrue(
        seats.demand == 3,
        'All intake in this course: ' + seats.demand
      );
      Assert.areEqual('Short', seats.status, 'Not enough seats');

      Assert.areEqual(3, f.cash.size(), 'Cash per month');
      Assert.isTrue(f.openReceivables > 0, 'Open invoice counted');
      Assert.isTrue(
        f.cash[0].dueFromOpen > 0 || f.cash[1].dueFromOpen > 0,
        'Due soon'
      );
      Assert.isTrue(
        String.join(f.notes, ' ').contains('Forecast Maths'),
        'Seat shortfall noted: ' + f.notes
      );

      AiService.Result explained = ForecastController.explainForecast(
        branch.Id,
        3
      );
      Assert.isTrue(explained.ok, 'Explained');
      Assert.areEqual('Forecast Narrative', explained.feature, 'Feature');
      Assert.isTrue(
        stub.lastMessage.contains('Seats by course: Forecast Maths') &&
        stub.lastMessage.contains('Short'),
        'Facts given to the model'
      );

      AgentForecast.Request r = new AgentForecast.Request();
      r.branch = 'fc-01';
      r.months = 2;
      AgentForecast.Request missing = new AgentForecast.Request();
      missing.branch = 'Nowhere';
      List<AgentForecast.Response> responses = AgentForecast.forecast(
        new List<AgentForecast.Request>{ r, missing }
      );
      Test.stopTest();
      Assert.isTrue(
        responses[0].forecast.contains('Seats short: Forecast Maths'),
        responses[0].forecast
      );
      Assert.isTrue(
        responses[0].forecast.contains('Expected cash'),
        'Cash line'
      );
      Assert.isTrue(
        responses[1].forecast.startsWith('I could not find a branch'),
        responses[1].forecast
      );
    }
  }

  @IsTest
  static void shortHistoryUsesPipelineAndCommittedFees() {
    ForecastService.Series enrolments = new ForecastService.Series();
    ForecastService.Series invoiced = new ForecastService.Series();
    for (Integer i = 0; i < 3; i++) {
      ForecastService.Point p = new ForecastService.Point();
      p.isFuture = true;
      p.forecast = 0;
      enrolments.points.add(p);
      ForecastService.Point q = new ForecastService.Point();
      q.isFuture = true;
      q.forecast = 0;
      invoiced.points.add(q);
    }
    List<ForecastService.PipelineRow> pipeline = new List<ForecastService.PipelineRow>();
    for (Integer n : new List<Integer>{ 4, 1 }) {
      ForecastService.PipelineRow r = new ForecastService.PipelineRow();
      r.count = n;
      r.expected = n == 4 ? 3.2 : 1.0;
      pipeline.add(r);
    }
    ForecastService.fromPipeline(enrolments, pipeline);
    Assert.areEqual('Pipeline', enrolments.method, 'Method');
    Assert.isTrue(
      enrolments.nextTotal == 4,
      '4.2 rounds to 4: ' + enrolments.nextTotal
    );
    Assert.isTrue(
      enrolments.points[0].forecast == 2 &&
        enrolments.points[1].forecast == 1 &&
        enrolments.points[2].forecast == 1,
      'Earliest months first'
    );
    Assert.isTrue(
      enrolments.points[0].high == 2 &&
        enrolments.points[2].high == 1 &&
        enrolments.points[1].low == 0,
      'Range up to every item enrolling'
    );

    List<ForecastService.CashRow> cash = new List<ForecastService.CashRow>();
    for (Integer amount : new List<Integer>{ 0, 11800, 11800 }) {
      ForecastService.CashRow c = new ForecastService.CashRow();
      c.committedBilling = amount;
      cash.add(c);
    }
    ForecastService.fromCommittedFees(invoiced, cash);
    Assert.areEqual('Committed fees', invoiced.method, 'Method');
    Assert.isTrue(invoiced.nextTotal == 23600, 'Total: ' + invoiced.nextTotal);
    Assert.isTrue(invoiced.points[1].forecast == 11800, 'Per month');

    ForecastService.Series untouched = new ForecastService.Series();
    untouched.method = 'Average';
    ForecastService.fromPipeline(
      untouched,
      new List<ForecastService.PipelineRow>()
    );
    ForecastService.fromCommittedFees(
      untouched,
      new List<ForecastService.CashRow>()
    );
    Assert.areEqual('Average', untouched.method, 'Nothing known: unchanged');
  }

  @IsTest
  static void teachersSeeNoFigures() {
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      ForecastService.Forecast f = ForecastController.getForecast(null, 9);
      Assert.areEqual(6, f.horizon, 'Horizon capped');
      Assert.isFalse(f.showFinance, 'No finance for teachers');
      try {
        ForecastController.explainForecast(null, 3);
        Assert.fail('No KEM AI User');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('KEM AI User'), e.getMessage());
      }
      Assert.areEqual(
        'You do not have access to enrolment or finance figures.',
        AgentForecast.describe(new ForecastService.Forecast()),
        'Nothing to show'
      );
    }
  }
}
