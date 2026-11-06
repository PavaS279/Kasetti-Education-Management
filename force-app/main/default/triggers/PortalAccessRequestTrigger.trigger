trigger PortalAccessRequestTrigger on Portal_Access_Request__e(after insert) {
  CollegePortalAccessService.handleRequests(Trigger.new);
}
