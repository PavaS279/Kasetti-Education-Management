for (CronTrigger job : [
  SELECT Id
  FROM CronTrigger
  WHERE CronJobDetail.Name = 'KEM College Document Retention'
]) {
  System.abortJob(job.Id);
}
