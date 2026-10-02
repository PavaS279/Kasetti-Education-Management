// Aborts all scheduled Kasetti Education Management jobs (run before deploying Apex).
for (CronTrigger job : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'KEM %']) {
    System.abortJob(job.Id);
}
