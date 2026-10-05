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

## Lifecycles (Phase 2)

| Record                                     | Field               | Lifecycle                                                                                                            |
| ------------------------------------------ | ------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Waitlist entry (`Waitlist_Entry__c`)       | `Status__c`         | Waiting → Offered → Enrolled / Declined / Expired; Waiting/Offered → Cancelled; Declined/Expired → Waiting (requeue) |
| Instalment (`Instalment__c`)               | `Status__c`         | Due → Partially Paid → Paid (derived from the invoice's paid amount)                                                 |
| Credit note (`Credit_Note__c`)             | `Status__c`         | Open → Partially Used → Used; Open → Void                                                                            |
| Refund (`Refund__c`)                       | `Status__c`         | Requested → Approved → Paid; Requested/Approved → Rejected                                                           |
| Message (`Message__c`)                     | `Status__c`         | Queued → Sent / Failed; Delivered (portal); Suppressed (no consent or address); Not Sent (delivery off)              |
| Staff absence (`Staff_Absence__c`)         | `Status__c`         | Needs Cover → Partially Covered → Covered; → Withdrawn                                                               |
| Course grade (`CourseOfferingParticipant`) | `Grade_Status__c`   | Provisional → Final (finalised) → Provisional (reopened)                                                             |
| Class grading (`CourseOffering`)           | `Grading_Status__c` | Open → Final → Open (reopened)                                                                                       |

## Policies

Organisation defaults (`Education_Setting__mdt`) with branch overrides (`Branch__c` fields), resolved by `BranchPolicy`:

| Policy                     | Default                      | Branch override                |
| -------------------------- | ---------------------------- | ------------------------------ |
| Invoice due days           | 14                           | `Invoice_Due_Days__c`          |
| Attendance threshold       | 75%                          | `Attendance_Threshold__c`      |
| Tax rate                   | 0%                           | `Tax_Rate__c`                  |
| Invoice number prefix      | INV                          | `Invoice_Prefix__c`            |
| Cancellation notice        | —                            | `Cancellation_Notice_Hours__c` |
| Session generation horizon | 366 days                     | —                              |
| Payment tolerance          | 0.01                         | —                              |
| Log level                  | INFO                         | —                              |
| Waitlist offer hold        | 48 hours                     | —                              |
| Refund auto-approval limit | 1,000                        | —                              |
| Auto-apply credit          | true                         | —                              |
| Email delivery             | Off (go-live switch: `Live`) | —                              |
| Portal URL (in messages)   | `/s/my-learning`             | —                              |
| Due-soon reminder          | 3 days before                | —                              |
| Overdue reminders          | 1, 7, 14 days after          | —                              |
| Absent counts as zero      | true                         | —                              |

Phase 2 settings are `Education_Setting__mdt` records: `Waitlist_Offer_Hours`, `Refund_Auto_Approve_Limit`, `Auto_Apply_Credit`, `Email_Delivery`, `Portal_URL`, `Due_Soon_Days`, `Overdue_Reminder_Days`, `Absent_Counts_As_Zero`. Notification texts are `Message_Template__mdt` records.

Phase 3 settings: `Recurring_Billing_Batch_Size` (enrolments per recurring billing batch, default 5; the job also defers work to a follow-up run when short of limits) and `Dispatch_Rounds` (follow-up email delivery jobs of 100 in a row, default 20).

## Scheduled jobs

| Job (`KemJobs`)       | When (IST)    | Does                                                                 |
| --------------------- | ------------- | -------------------------------------------------------------------- |
| KEM Offer Expiry      | Daily 01:30   | Expires admission offers past their expiry date                      |
| KEM Waitlist Offers   | Hourly at :05 | Expires held waitlist offers and offers the seat to the next learner |
| KEM Recurring Billing | Daily 02:10   | Invoices the monthly periods that have started                       |
| KEM Payment Reminders | Daily 09:05   | Due-soon and overdue reminders, then sends queued email              |
| KEM Message Dispatch  | Hourly at :20 | Sends email queued where a job could not be started                  |

`scripts/deploy.sh` pauses these jobs during a deployment and schedules them again afterwards; the operations console shows their state and can schedule any that are missing.
