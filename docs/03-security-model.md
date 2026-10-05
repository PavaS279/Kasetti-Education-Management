# 03 — Security Model

## Principles

- Access is granted **only** through permission sets (`KEM_*`); profiles are not modified.
- Custom objects default to the most restrictive sharing that supports the process.
- Apex runs `with sharing` (services, controllers) and queries `WITH USER_MODE`; DML uses `AccessLevel.USER_MODE` unless a documented system operation needs elevated rights (logging, managed sharing).
- Portal access is decided by explicit relationships ([ADR-003](adr/ADR-003-portal-access.md)).

## Permission set architecture

Education Cloud objects can only be granted by permission sets bound to the Education Cloud permission set licence, and those licensed sets cannot grant custom objects. Each staff persona therefore has:

| Layer           | Name pattern            | Licence                       | Contains                                                                                                                                               |
| --------------- | ----------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Base            | `KEM_<Persona>`         | none                          | Custom objects, CRM objects (Lead, Account, Contact), standard field access, tabs, app, Apex classes, user permissions (Convert Leads, Edit Tasks)     |
| Education Cloud | `KEM_<Persona>_Edu`     | Education Cloud – Full Access | Education Cloud objects and fields, plus `AccessEducationCloud` and `GroupMembershipPsl` (required for `ContactContactRelation` / `PartyRoleRelation`) |
| Group           | `KEM_<Persona>_Persona` | —                             | Permission set group bundling both; assign this to users                                                                                               |

Users must hold the **Education Cloud – Full Access** permission set licence before the `_Edu` set (or the group) can be assigned.

## Personas and permission sets

| Persona                   | Permission set              | Summary                                                             |
| ------------------------- | --------------------------- | ------------------------------------------------------------------- |
| Institution administrator | `KEM_Administrator`         | Full access including View/Modify All on KEM objects and error logs |
| Branch manager            | `KEM_Branch_Manager`        | Edits own branch (Apex managed share), manages rooms in own branch  |
| Admissions counsellor     | `KEM_Admissions_Counsellor` | Enquiries, applications, offers                                     |
| Academic coordinator      | `KEM_Academic_Coordinator`  | Classes, timetable, enrolments, rooms                               |
| Teacher                   | `KEM_Teacher`               | Assigned sessions, attendance, results entry                        |
| Finance user              | `KEM_Finance`               | Prices, invoices, payments, reconciliation                          |
| Learner / guardian        | `KEM_Portal_User`           | Portal components only; data filtered by relationship               |

Education Cloud objects additionally require the **Education Cloud – Full Access** permission set licence (staff) or **Education Cloud for Experience Cloud User** (portal).

## Object access matrix (Phase 0)

| Object       | Admin             | Branch Mgr                       | Admissions | Academic    | Teacher | Finance |
| ------------ | ----------------- | -------------------------------- | ---------- | ----------- | ------- | ------- |
| Branch__c    | CRUD + Modify All | Read/Edit (own branch via share) | Read       | Read        | Read    | Read    |
| Room__c      | CRUD + Modify All | CRUD (own branch)                | Read       | Create/Edit | Read    | Read    |
| Error_Log__c | CRUD + Modify All | —                                | —          | —           | —       | —       |

The matrix is extended per feature in `scripts/tooling/specs.py` (`PERMISSION_SETS`).

## Sharing

| Object       | OWD                  | Extra sharing                                                                             |
| ------------ | -------------------- | ----------------------------------------------------------------------------------------- |
| Branch__c    | Public Read Only     | `Branch__Share` row cause `Branch_Manager__c` (Edit) maintained by `BranchTriggerHandler` |
| Room__c      | Controlled by parent | —                                                                                         |
| Error_Log__c | Private              | Admins via View All                                                                       |

## Validated access scenarios (`SecurityModelTest`)

| Scenario                                                                                             | Result                                                               |
| ---------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| Branch manager creates and edits a room in their own branch                                          | Allowed                                                              |
| Branch manager creates a room in another branch                                                      | Denied                                                               |
| Teacher reads branches                                                                               | Allowed                                                              |
| Teacher creates a room or a branch                                                                   | Denied                                                               |
| Teacher reads error logs                                                                             | Denied                                                               |
| Administrator reads all error logs                                                                   | Allowed                                                              |
| Branch manager edits own branch; share moves when manager changes                                    | Allowed / share re-pointed                                           |
| Duplicate branch staff assignment (same user, branch, role)                                          | Denied                                                               |
| Admissions counsellor captures, follows up, and converts an enquiry with only the counsellor persona | Allowed (`EnquiryServicesTest.counsellorCanWorkAndConvertEnquiries`) |

## System-mode operations (documented exceptions)

| Operation                                                                                                 | Why                                                                                                                                                                                                                                                     |
| --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `LogEventTriggerHandler` inserts `Error_Log__c`                                                           | Runs as Automated Process user                                                                                                                                                                                                                          |
| `BranchTriggerHandler` writes `Branch__Share`                                                             | Managed sharing                                                                                                                                                                                                                                         |
| `EnquiryAssignmentService` workload queries                                                               | Counsellors cannot see each other's enquiries                                                                                                                                                                                                           |
| `EnquiryDuplicateService` queries                                                                         | Integrity check must see all records                                                                                                                                                                                                                    |
| `EnquiryConversionService` stamps `Source_Enquiry__c`, `Converted_Learner__c`, `Converted_Application__c` | Read-only traceability fields, written only after user-mode create/edit succeeded                                                                                                                                                                       |
| `SeatService` seat counts and Open/Full status                                                            | Seat availability must count every enrolment regardless of the user's visibility                                                                                                                                                                        |
| `EnrolmentService` stamps agreed amounts and fee lines after a user-mode insert                           | Financial snapshot fields are read-only for users                                                                                                                                                                                                       |
| `EnrolmentService.decideDiscount` writes via an elevated helper                                           | Authorised by the **KEM Approve Discounts** custom permission, not by record ownership                                                                                                                                                                  |
| `AssessmentService` result writes (`Writer`)                                                              | Teachers only read classes; authorised by "class teacher or can edit the assessment"                                                                                                                                                                    |
| `BillingService` ledger writes (`Writer`)                                                                 | All ledger fields are system-managed; authorised by the **KEM Manage Billing** custom permission (Administrator, Finance, Branch Manager). Invoices and payments are Private: finance and administrators have View/Modify All, branch managers View All |
| `GuardianRelationshipService` reads `PartyRoleRelation` and `ContactContactRelation`                      | Reference data; `WITH USER_MODE` + bind variables fails on these Industries objects (object access is checked explicitly)                                                                                                                               |
| `WaitlistService` / `SeatService` offers and seat holds (`Writer`)                                        | Waitlist fields are system-managed; authorised by create access on waitlist entries (schedulers, counsellors)                                                                                                                                           |
| `TransferService` (`Writer`)                                                                              | Authorised by edit access to the original enrolment                                                                                                                                                                                                     |
| `CreditService` credit, application and refund writes (`Writer`)                                          | Authorised by **KEM Manage Billing**; refund decisions by **KEM Approve Refunds** (Administrator, Branch Manager) and never by the requester                                                                                                            |
| `MessageService` outbox writes                                                                            | Notifications are created by the business event; staff messages need read access to the learner and go only to the learner or their guardians; consent changes run in user mode                                                                         |
| `CoverService` absence and cover fields (`Writer`)                                                        | Teachers report their own absence; arranging cover needs edit access to the session's teacher and room fields; the teacher/room change itself runs in user mode through the double-booking trigger                                                      |
| `GradingService` grade fields (`Writer`)                                                                  | Class teacher, edit access to the class, or Modify All on assessments (administrators, academic coordinators); reopening excludes teachers                                                                                                              |
| `PortalService` reads and downloads                                                                       | Portal users see only themselves and wards with portal access; documents are returned as base64 after checking they belong to those learners                                                                                                            |
| `OpsService`                                                                                              | Administrators only (read and edit access to the error log)                                                                                                                                                                                             |

## Phase 2 permissions

| Permission / access                     | Administrator | Branch Manager       | Admissions  | Academic             | Teacher      | Finance    |
| --------------------------------------- | ------------- | -------------------- | ----------- | -------------------- | ------------ | ---------- |
| KEM Approve Refunds (custom permission) | ✅            | ✅                   | —           | —                    | —            | —          |
| Waitlist entries                        | Modify All    | Create/Edit/View All | Create/Edit | Create/Edit/View All | Read         | Read       |
| Credit notes, refunds                   | Modify All    | View All             | —           | —                    | —            | Modify All |
| Messages                                | Modify All    | View All             | Read        | Read                 | —            | View All   |
| Staff absences                          | Modify All    | Create/Edit/View All | Read        | Create/Edit/View All | Create (own) | —          |
| Report card and document pages          | ✅            | ✅                   | ✅          | ✅                   | ✅           | ✅         |
| Operations console (`OpsController`)    | ✅            | —                    | —           | —                    | —            | —          |

## Phase 3 permissions

| Permission / access                              | Administrator | Branch Manager | Admissions  | Academic    | Teacher | Finance |
| ------------------------------------------------ | ------------- | -------------- | ----------- | ----------- | ------- | ------- |
| Branch comparison (`BranchController`)           | ✅            | ✅             | —           | —           | —       | —       |
| Open a branch from a template (create on Branch) | ✅            | —              | —           | —           | —       | —       |
| Classes (`CourseOffering`)                       | Modify All    | Create/Edit    | Read        | Create/Edit | Read    | Read    |
| Enrolments (`CourseOfferingParticipant`)         | Modify All    | Create/Edit    | Create/Edit | Create/Edit | Read    | Read    |

`BranchTemplateService` runs entirely as the user (user-mode queries and inserts), so cloning needs create access on every copied object; comparison figures only include records the user can see.

**Administrator edit access (Phase 3, 2026-10-05):** administrators have Modify All on classes (`CourseOffering`) and enrolments (`CourseOfferingParticipant`), so they can edit, re-schedule and close records other users own. Teachers, branch managers and coordinators keep their existing access.
