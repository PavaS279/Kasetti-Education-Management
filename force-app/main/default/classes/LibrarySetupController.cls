/** Lightning controller for the library catalogue import and Add copies. */
public with sharing class LibrarySetupController {
  @AuraEnabled
  public static LibraryImportService.Preview previewImport(
    Id branchId,
    String csv
  ) {
    try {
      return LibraryImportService.preview(branchId, csv);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static LibraryImportService.ImportResult importItems(
    Id branchId,
    String csv
  ) {
    try {
      return LibraryImportService.importCsv(branchId, csv);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Integer addCopies(Id itemId, Integer copies) {
    try {
      return LibraryImportService.addCopies(itemId, copies);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
