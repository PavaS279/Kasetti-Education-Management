/** Lightning controller for class transfers. */
public with sharing class TransferController {
  @AuraEnabled
  public static TransferService.TransferPreview previewTransfer(
    TransferService.TransferRequest request
  ) {
    try {
      return TransferService.preview(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id transfer(TransferService.TransferRequest request) {
    try {
      return TransferService.transfer(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
