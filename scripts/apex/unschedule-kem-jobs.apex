// Aborts only the core jobs owned by KemJobs (run before deploying dependent Apex).
// College and future independently managed schedules may also use the KEM prefix.
Set<String> managedNames = new Set<String>(KemJobs.jobNames());
for (CronTrigger job : [
  SELECT Id, CronJobDetail.Name
  FROM CronTrigger
  WHERE CronJobDetail.Name LIKE 'KEM %'
]) {
  if (managedNames.contains(job.CronJobDetail.Name)) {
    System.abortJob(job.Id);
  }
}
