/** Lightning controller for the forecasts panel. */
public with sharing class ForecastController {
  @AuraEnabled
  public static ForecastService.Forecast getForecast(
    Id branchId,
    Integer horizon
  ) {
    try {
      return ForecastService.forecast(branchId, horizon);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** Einstein's explanation of the forecast (needs KEM AI User). */
  @AuraEnabled
  public static AiService.Result explainForecast(Id branchId, Integer horizon) {
    try {
      return ForecastService.explain(branchId, horizon);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
