/**
 * Small, explainable monthly forecasting (F4.8).
 *
 * Three candidate methods are backtested on the most recent months of the
 * history (the model is fitted without them and asked to predict them);
 * the one with the lowest error is used, and its error (MAPE) is reported
 * as the forecast's accuracy:
 *   - Average: mean of the last three months (stable demand);
 *   - Trend: Holt's linear exponential smoothing (growth or decline);
 *   - Seasonal: the same month last year scaled by the recent level
 *     (needs at least 15 months).
 * Ranges are an 80% band from the backtest errors, widening with the horizon.
 */
public with sharing class ForecastMath {
  public static final String AVERAGE = 'Average';
  public static final String TREND = 'Trend';
  public static final String SEASONAL = 'Seasonal';
  public static final Integer MIN_HISTORY = 6;
  public static final Integer HOLDOUT = 3;
  private static final Decimal Z80 = 1.28;

  public class Fit {
    public String method;
    public List<Decimal> forecasts = new List<Decimal>();
    public List<Decimal> lows = new List<Decimal>();
    public List<Decimal> highs = new List<Decimal>();
    /** Mean absolute percentage error of the backtest (null: not enough history). */
    public Decimal mape;
    public Integer historyMonths = 0;
  }

  /** Forecast for the next horizon months from monthly history (oldest first). */
  public static Fit fit(List<Decimal> history, Integer horizon) {
    List<Decimal> series = trimLeadingZeros(history);
    Fit result = new Fit();
    result.historyMonths = series.size();
    if (series.isEmpty()) {
      result.method = AVERAGE;
      for (Integer h = 0; h < horizon; h++) {
        result.forecasts.add(0);
        result.lows.add(0);
        result.highs.add(0);
      }
      return result;
    }
    String best = AVERAGE;
    List<Decimal> errors = new List<Decimal>();
    if (series.size() >= MIN_HISTORY) {
      Decimal bestMape;
      for (String method : candidates(series.size())) {
        List<Decimal> train = slice(series, 0, series.size() - HOLDOUT);
        List<Decimal> predicted = predict(method, train, HOLDOUT);
        List<Decimal> actual = slice(
          series,
          series.size() - HOLDOUT,
          series.size()
        );
        Decimal m = mape(actual, predicted);
        if (m != null && (bestMape == null || m < bestMape)) {
          bestMape = m;
          best = method;
          errors = new List<Decimal>();
          for (Integer i = 0; i < actual.size(); i++) {
            errors.add(actual[i] - predicted[i]);
          }
        }
      }
      result.mape = bestMape == null ? null : bestMape.setScale(1);
    }
    result.method = best;
    List<Decimal> forecasts = predict(best, series, horizon);
    Decimal spread = errors.isEmpty() ? spreadOf(series) : rms(errors);
    for (Integer h = 0; h < horizon; h++) {
      Decimal f = Math.max(0.0, forecasts[h]);
      Decimal band = Z80 * spread * Math.sqrt(Decimal.valueOf(h + 1));
      result.forecasts.add(f.setScale(2));
      result.lows.add(Math.max(0.0, f - band).setScale(2));
      result.highs.add((f + band).setScale(2));
    }
    return result;
  }

  @TestVisible
  private static List<String> candidates(Integer size) {
    List<String> methods = new List<String>{ AVERAGE, TREND };
    if (size >= 15) {
      methods.add(SEASONAL);
    }
    return methods;
  }

  @TestVisible
  private static List<Decimal> predict(
    String method,
    List<Decimal> series,
    Integer horizon
  ) {
    if (method == TREND) {
      return holt(series, horizon);
    }
    if (method == SEASONAL && series.size() >= 13) {
      return seasonal(series, horizon);
    }
    return average(series, horizon);
  }

  private static List<Decimal> average(List<Decimal> series, Integer horizon) {
    Integer n = Math.min(3, series.size());
    Decimal total = 0;
    for (Integer i = series.size() - n; i < series.size(); i++) {
      total += series[i];
    }
    Decimal level = n == 0 ? 0 : total / n;
    List<Decimal> result = new List<Decimal>();
    for (Integer h = 0; h < horizon; h++) {
      result.add(level);
    }
    return result;
  }

  /** Holt's linear method; smoothing chosen by the lowest one-step error. */
  private static List<Decimal> holt(List<Decimal> series, Integer horizon) {
    if (series.size() < 2) {
      return average(series, horizon);
    }
    Decimal bestError;
    Decimal bestLevel = 0;
    Decimal bestTrend = 0;
    for (Decimal alpha : new List<Decimal>{ 0.3, 0.5, 0.8 }) {
      for (Decimal beta : new List<Decimal>{ 0.1, 0.3 }) {
        Decimal level = series[0];
        Decimal trend = series[1] - series[0];
        Decimal error = 0;
        for (Integer t = 1; t < series.size(); t++) {
          Decimal expected = level + trend;
          error += (series[t] - expected) * (series[t] - expected);
          Decimal previous = level;
          level = alpha * series[t] + (1 - alpha) * (level + trend);
          trend = beta * (level - previous) + (1 - beta) * trend;
        }
        if (bestError == null || error < bestError) {
          bestError = error;
          bestLevel = level;
          bestTrend = trend;
        }
      }
    }
    List<Decimal> result = new List<Decimal>();
    for (Integer h = 1; h <= horizon; h++) {
      result.add(bestLevel + h * bestTrend);
    }
    return result;
  }

  /** Same month last year, scaled by the last three months against a year before. */
  private static List<Decimal> seasonal(List<Decimal> series, Integer horizon) {
    Integer n = series.size();
    Decimal recent = 0;
    Decimal yearBefore = 0;
    for (Integer i = n - 3; i < n; i++) {
      recent += series[i];
      yearBefore += series[i - 12];
    }
    Decimal scale = yearBefore == 0 ? 1 : recent / yearBefore;
    List<Decimal> result = new List<Decimal>();
    for (Integer h = 0; h < horizon; h++) {
      // Month n + h, a year earlier, repeating the last year for long horizons.
      Integer index = n + h - 12;
      while (index >= n) {
        index -= 12;
      }
      result.add(series[index] * scale);
    }
    return result;
  }

  /** Mean absolute percentage error over months with a non-zero actual. */
  @TestVisible
  private static Decimal mape(List<Decimal> actual, List<Decimal> predicted) {
    Decimal total = 0;
    Integer count = 0;
    for (Integer i = 0; i < actual.size(); i++) {
      if (actual[i] != null && actual[i] != 0) {
        total +=
          Math.abs(actual[i] - Math.max(0.0, predicted[i])) /
          Math.abs(actual[i]);
        count++;
      }
    }
    return count == 0 ? null : total / count * 100;
  }

  /** Accuracy band shown to staff for a backtest error. */
  public static String accuracy(Decimal mape) {
    if (mape == null) {
      return 'Not enough history';
    }
    if (mape <= 15) {
      return 'Good';
    }
    if (mape <= 35) {
      return 'Fair';
    }
    return 'Low';
  }

  private static Decimal rms(List<Decimal> errors) {
    Decimal total = 0;
    for (Decimal e : errors) {
      total += e * e;
    }
    return Math.sqrt(total / errors.size());
  }

  /** Spread of a short history: the standard deviation (or a third of the level). */
  private static Decimal spreadOf(List<Decimal> series) {
    if (series.size() < 2) {
      return series.isEmpty() ? 0 : Math.abs(series[0]) / 3;
    }
    Decimal mean = 0;
    for (Decimal v : series) {
      mean += v;
    }
    mean /= series.size();
    Decimal total = 0;
    for (Decimal v : series) {
      total += (v - mean) * (v - mean);
    }
    return Math.sqrt(total / (series.size() - 1));
  }

  @TestVisible
  private static List<Decimal> trimLeadingZeros(List<Decimal> history) {
    List<Decimal> result = new List<Decimal>();
    Boolean started = false;
    for (Decimal v : history == null ? new List<Decimal>() : history) {
      Decimal value = v == null ? 0 : v;
      if (started || value != 0) {
        started = true;
        result.add(value);
      }
    }
    return result;
  }

  private static List<Decimal> slice(
    List<Decimal> values,
    Integer fromIndex,
    Integer toIndex
  ) {
    List<Decimal> result = new List<Decimal>();
    for (Integer i = fromIndex; i < toIndex; i++) {
      result.add(values[i]);
    }
    return result;
  }
}
