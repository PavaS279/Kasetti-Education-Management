/**
 * Business exception for expected, user-facing failures. Messages must be
 * safe to show to end users; never include stack traces or internal IDs.
 */
public inherited sharing class AppException extends Exception {
  /** Converts any exception into an AuraHandledException safe for Lightning components. */
  public static AuraHandledException toAura(Exception e) {
    String message = e instanceof AppException || e instanceof DmlException
      ? (e instanceof DmlException
          ? ((DmlException) e).getDmlMessage(0)
          : e.getMessage())
      : System.Label.KEM_Unexpected_Error;
    AuraHandledException aura = new AuraHandledException(message);
    aura.setMessage(message);
    return aura;
  }
}
