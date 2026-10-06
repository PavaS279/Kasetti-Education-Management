/**
 * Generic LMS API (runs as the integration user with the KEM Integration persona).
 *
 * GET  /services/apexrest/kem/v1/lms/classes?branch=BLR-01&status=Open&modifiedSince=2026-10-01T00:00:00Z
 * GET  /services/apexrest/kem/v1/lms/classes/{classId}
 * GET  /services/apexrest/kem/v1/lms/classes/{classId}/roster
 * POST /services/apexrest/kem/v1/lms/grades
 *      { "classId": "...", "publish": true,
 *        "assessment": { "externalId": "lms-quiz-1", "name": "Quiz 1", "type": "Quiz",
 *                        "maxScore": 20, "weight": 10, "assessmentDate": "2026-10-01" },
 *        "results": [ { "learnerId": "003...", "score": 17 }, { "learnerEmail": "a@b.c", "absent": true } ] }
 * GET  /services/apexrest/kem/v1/lms/events?after=EVT-00000010&limit=200
 * POST /services/apexrest/kem/v1/lms/events/ack   { "events": ["EVT-00000011"], "success": true }
 */
@RestResource(urlMapping='/kem/v1/lms/*')
global with sharing class LmsApi {
  private static final String PREFIX = '/kem/v1/lms';

  @HttpGet
  global static void doGet() {
    try {
      List<String> path = KemApi.segments(PREFIX);
      if (KemApi.handleEvents(IntegrationService.LMS, 'GET', path)) {
        return;
      }
      if (path.size() == 1 && path[0] == 'classes') {
        KemApi.ok(
          200,
          new Map<String, Object>{
            'classes' => LmsService.classes(
              KemApi.param('branch'),
              KemApi.param('status'),
              KemApi.datetimeParam('modifiedSince')
            )
          }
        );
      } else if (path.size() == 2 && path[0] == 'classes') {
        KemApi.ok(200, LmsService.classDetail(idOf(path[1])));
      } else if (
        path.size() == 3 &&
        path[0] == 'classes' &&
        path[2] == 'roster'
      ) {
        KemApi.ok(200, LmsService.roster(idOf(path[1])));
      } else {
        KemApi.notFound();
      }
    } catch (Exception e) {
      KemApi.fail(e, 'LmsApi.doGet');
    }
  }

  @HttpPost
  global static void doPost() {
    try {
      List<String> path = KemApi.segments(PREFIX);
      if (KemApi.handleEvents(IntegrationService.LMS, 'POST', path)) {
        return;
      }
      if (path.size() == 1 && path[0] == 'grades') {
        LmsService.GradeRequest request = (LmsService.GradeRequest) JSON.deserialize(
          KemApi.body(),
          LmsService.GradeRequest.class
        );
        LmsService.GradeResult result = LmsService.saveGrades(request);
        KemApi.ok(result.created ? 201 : 200, result);
      } else {
        KemApi.notFound();
      }
    } catch (Exception e) {
      KemApi.fail(e, 'LmsApi.doPost');
    }
  }

  private static Id idOf(String value) {
    try {
      return Id.valueOf(value);
    } catch (Exception e) {
      throw new LmsService.NotFoundException('Class not found: ' + value);
    }
  }
}
