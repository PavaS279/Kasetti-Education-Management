# 04 — Statuses and Policies

Status transitions are enforced by `StatusTransitionService` from `Status_Transition__mdt` records. A governed field rejects any change that is not declared.

## Lifecycles (Phase 1)

| Record                                        | Field                      | Lifecycle                                                                                                               |
| --------------------------------------------- | -------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Enquiry (`Lead`)                              | `Status`                   | New → Contacted → Nurturing → Qualified (converted) / Unqualified                                                       |
| Application (`IndividualApplication`)         | `Status`                   | Processing → In Review → Ready For Decision → Application Decision → Enrolled; Canceled / Withdrawn from any open stage |
| Offer (`IndividualApplication`)               | `Offer_Status__c`          | Not Offered → Offered → Accepted / Declined / Expired                                                                   |
| Class (`CourseOffering`)                      | `Class_Status__c`          | Planned → Open → Full ↔ Open → In Progress → Completed; Cancelled                                                       |
| Class enrolment (`CourseOfferingParticipant`) | `ParticipationStatus`      | Enrolled → Completed / Withdrew / On Hold                                                                               |
| Session (`Class_Session__c`)                  | `Status__c`                | Scheduled → Completed / Cancelled                                                                                       |
| Attendance (`Session_Attendance__c`)          | `Status__c`                | Present, Late, Absent, Excused                                                                                          |
| Result (`Assessment_Result__c`)               | `Status__c`                | Draft → Published                                                                                                       |
| Invoice (`Student_Invoice__c`)                | `Status__c`                | Draft → Issued → Partially Paid → Paid; Cancelled from Draft/Issued                                                     |
| Payment (`Student_Payment__c`)                | `Status__c`                | Pending → Confirmed / Failed                                                                                            |
| Payment reconciliation                        | `Reconciliation_Status__c` | Unreconciled → Reconciled / Exception                                                                                   |

The exact transition records live in `force-app/main/default/customMetadata/Status_Transition.*`.

## Policies

Organisation defaults (`Education_Setting__mdt`) with branch overrides (`Branch__c` fields), resolved by `BranchPolicy`:

| Policy                     | Default  | Branch override                |
| -------------------------- | -------- | ------------------------------ |
| Invoice due days           | 14       | `Invoice_Due_Days__c`          |
| Attendance threshold       | 75%      | `Attendance_Threshold__c`      |
| Tax rate                   | 0%       | `Tax_Rate__c`                  |
| Invoice number prefix      | INV      | `Invoice_Prefix__c`            |
| Cancellation notice        | —        | `Cancellation_Notice_Hours__c` |
| Session generation horizon | 366 days | —                              |
| Payment tolerance          | 0.01     | —                              |
| Log level                  | INFO     | —                              |
