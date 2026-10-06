trigger AdmissionDocumentTrigger on Admission_Document__e(after insert) {
  AdmissionDocumentService.attach(Trigger.new);
}
