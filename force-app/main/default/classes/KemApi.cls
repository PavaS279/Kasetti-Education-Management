/**
 * Shared plumbing for the KEM REST APIs: path parsing, JSON responses and
 * error mapping (400 invalid request, 403 not allowed, 404 not found,
 * 500 unexpected with a reference to the request).
 */
public with sharing class KemApi {
  /** Path segments after the API prefix, e.g. /kem/v1/lms/classes/X/roster → [classes, X, roster]. */
  public static List<String> segments(String prefix) {
    String uri = RestContext.request.requestURI;
    Integer at = uri.indexOf(prefix);
    String rest = at < 0 ? '' : uri.substring(at + prefix.length());
    List<String> parts = new List<String>();
    for (String part : rest.split('/')) {
      if (String.isNotBlank(part)) {
        parts.add(EncodingUtil.urlDecode(part, 'UTF-8'));
      }
    }
    return parts;
  }

  public static String param(String name) {
    return RestContext.request.params.get(name);
  }

  public static Integer intParam(String name) {
    String value = param(name);
    if (String.isBlank(value)) {
      return null;
    }
    if (!value.isNumeric()) {
      throw new AppException(name + ' must be a whole number.');
    }
    return Integer.valueOf(value);
  }

  public static Datetime datetimeParam(String name) {
    String value = param(name);
    if (String.isBlank(value)) {
      return null;
    }
    try {
      return (Datetime) JSON.deserialize('"' + value + '"', Datetime.class);
    } catch (Exception e) {
      throw new AppException(
        name + ' must be an ISO 8601 date-time, e.g. 2026-10-01T00:00:00Z.'
      );
    }
  }

  public static Date dateParam(String name) {
    String value = param(name);
    if (String.isBlank(value)) {
      return null;
    }
    try {
      return Date.valueOf(value);
    } catch (Exception e) {
      throw new AppException(name + ' must be a date, e.g. 2026-10-01.');
    }
  }

  public static String body() {
    Blob raw = RestContext.request.requestBody;
    return raw == null ? '' : raw.toString();
  }

  public static void ok(Integer statusCode, Object payload) {
    RestResponse response = RestContext.response;
    response.statusCode = statusCode;
    response.addHeader('Content-Type', 'application/json');
    response.responseBody = Blob.valueOf(JSON.serialize(payload, true));
  }

  public static void text(String contentType, String content) {
    RestResponse response = RestContext.response;
    response.statusCode = 200;
    response.addHeader('Content-Type', contentType);
    response.responseBody = Blob.valueOf(content);
  }

  public static void fail(Exception e, String source) {
    Integer status;
    String message = e.getMessage();
    if (e instanceof IntegrationService.ForbiddenException) {
      status = 403;
    } else if (e instanceof LmsService.NotFoundException) {
      status = 404;
    } else if (
      e instanceof AppException ||
      e instanceof JSONException ||
      e instanceof TypeException ||
      e instanceof StringException
    ) {
      status = 400;
    } else {
      Logger.error(source, e, null);
      Logger.flush();
      status = 500;
      message =
        'The request could not be completed. Reference: ' +
        Request.getCurrent().getRequestId();
    }
    ok(status, new Map<String, Object>{ 'error' => message });
  }

  public static void notFound() {
    ok(404, new Map<String, Object>{ 'error' => 'Unknown resource.' });
  }

  /** GET events and POST events/ack, shared by the LMS and ERP APIs. */
  public static Boolean handleEvents(
    String target,
    String method,
    List<String> path
  ) {
    if (path.isEmpty() || path[0] != 'events') {
      return false;
    }
    if (method == 'GET' && path.size() == 1) {
      ok(
        200,
        IntegrationService.pending(target, param('after'), intParam('limit'))
      );
      return true;
    }
    if (method == 'POST' && path.size() == 2 && path[1] == 'ack') {
      Ack ack = (Ack) JSON.deserialize(body(), Ack.class);
      ok(
        200,
        new Map<String, Object>{
          'acknowledged' => IntegrationService.acknowledge(
            ack.events,
            ack.success != false,
            ack.error
          )
        }
      );
      return true;
    }
    return false;
  }

  public class Ack {
    public List<String> events;
    public Boolean success;
    public String error;
  }
}
