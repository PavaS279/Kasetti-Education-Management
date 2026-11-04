// Schedules all Kasetti Education Management jobs (idempotent; run after deploying Apex).
System.debug(LoggingLevel.ERROR, 'KEM jobs scheduled: ' + KemJobs.scheduleAll());
