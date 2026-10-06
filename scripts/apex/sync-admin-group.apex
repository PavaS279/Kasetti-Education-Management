// Adds KEM Administrator users to the KEM Administrators group (edit access to every class and enrolment).
AdminGroupService.SyncResult r = AdminGroupService.sync();
System.debug(LoggingLevel.ERROR, 'KEM Administrators group: ' + r.added + ' added, ' + r.removed + ' removed');
