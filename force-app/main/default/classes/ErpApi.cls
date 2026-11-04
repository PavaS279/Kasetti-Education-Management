/**
 * Generic ERP API (integration user with the KEM Integration persona).
 *
 * GET  /services/apexrest/kem/v1/erp/journal?from=2026-10-01&to=2026-10-31&branch=BLR-01&format=csv|json
 * POST /services/apexrest/kem/v1/erp/exports   { "fromDate": "2026-10-01", "toDate": "2026-10-31", "branch": "BLR-01" }
 * GET  /services/apexrest/kem/v1/erp/exports   (latest 20 exports with their CSV file IDs)
 * GET  /services/apexrest/kem/v1/erp/events?after=EVT-00000010&limit=200
 * POST /services/apexrest/kem/v1/erp/events/ack   { "events": ["EVT-00000011"], "success": true }
 */
@RestResource(urlMapping='/kem/v1/erp/*')
global with sharing class ErpApi {
  private static final String PREFIX = '/kem/v1/erp';

  @HttpGet
  global static void doGet() {
    try {
      List<String> path = KemApi.segments(PREFIX);
      if (KemApi.handleEvents(IntegrationService.ERP, 'GET', path)) {
        return;
      }
      if (path.size() == 1 && path[0] == 'journal') {
        IntegrationService.assertIntegration();
        FinanceExportService.Journal journal = FinanceExportService.journal(
          KemApi.dateParam('from'),
          KemApi.dateParam('to'),
          branchId(KemApi.param('branch'))
        );
        if (KemApi.param('format') == 'csv') {
          KemApi.text('text/csv', FinanceExportService.toCsv(journal));
        } else {
          KemApi.ok(200, journal);
        }
      } else if (path.size() == 1 && path[0] == 'exports') {
        IntegrationService.assertIntegration();
        KemApi.ok(
          200,
          new Map<String, Object>{
            'exports' => FinanceExportService.recent(20)
          }
        );
      } else {
        KemApi.notFound();
      }
    } catch (Exception e) {
      KemApi.fail(e, 'ErpApi.doGet');
    }
  }

  @HttpPost
  global static void doPost() {
    try {
      List<String> path = KemApi.segments(PREFIX);
      if (KemApi.handleEvents(IntegrationService.ERP, 'POST', path)) {
        return;
      }
      if (path.size() == 1 && path[0] == 'exports') {
        IntegrationService.assertIntegration();
        ExportRequest request = (ExportRequest) JSON.deserialize(
          KemApi.body(),
          ExportRequest.class
        );
        KemApi.ok(
          201,
          FinanceExportService.export(
            request.fromDate,
            request.toDate,
            branchId(request.branch),
            'API'
          )
        );
      } else {
        KemApi.notFound();
      }
    } catch (Exception e) {
      KemApi.fail(e, 'ErpApi.doPost');
    }
  }

  global class ExportRequest {
    public Date fromDate;
    public Date toDate;
    public String branch;
  }

  private static Id branchId(String code) {
    if (String.isBlank(code)) {
      return null;
    }
    String value = code.trim().toUpperCase();
    List<Branch__c> rows = [
      SELECT Id
      FROM Branch__c
      WHERE Branch_Code__c = :value
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Unknown branch: ' + value);
    }
    return rows[0].Id;
  }
}
