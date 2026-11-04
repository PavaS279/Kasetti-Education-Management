/** Lightning controller for the transport desk. */
public with sharing class TransportController {
  @AuraEnabled
  public static List<TransportService.RouteSummary> getRoutes(Id branchId) {
    try {
      return TransportService.routes(branchId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static TransportService.RouteDetail getRoute(Id routeId) {
    try {
      return TransportService.route(routeId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static List<TransportService.LearnerOption> searchLearners(
    Id routeId,
    String term
  ) {
    try {
      return TransportService.searchLearners(routeId, term);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id assign(TransportService.AssignRequest request) {
    try {
      return TransportService.assign(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void changeStop(Id assignmentId, Id stopId) {
    try {
      TransportService.changeStop(assignmentId, stopId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void endAssignment(
    Id assignmentId,
    Date endDate,
    String reason
  ) {
    try {
      TransportService.endAssignment(assignmentId, endDate, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Integer notifyRoute(Id routeId, String message) {
    try {
      return TransportService.notifyRoute(routeId, message);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** Whether the user can create routes and stops (shows the set-up forms). */
  @AuraEnabled(cacheable=true)
  public static Boolean canManageRoutes() {
    return Schema.SObjectType.Transport_Route__c.isCreateable() &&
      Schema.SObjectType.Transport_Stop__c.isCreateable();
  }
}
