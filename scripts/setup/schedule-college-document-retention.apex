// Run once per org. Deletes college admission files after their configured retention period.
if (
  [
    SELECT COUNT()
    FROM CronTrigger
    WHERE CronJobDetail.Name = 'KEM College Document Retention'
  ] == 0
) {
  System.schedule(
    'KEM College Document Retention',
    '0 0 2 * * ?',
    new CollegeDocumentRetentionJob()
  );
}
