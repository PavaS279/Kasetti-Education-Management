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

| Permission / access                              | Administrator            | Branch Manager | Admissions  | Academic       | Teacher | Finance      | Integration                                  |
| ------------------------------------------------ | ------------------------ | -------------- | ----------- | -------------- | ------- | ------------ | -------------------------------------------- |
| Branch comparison (`BranchController`)           | ✅                       | ✅             | —           | —              | —       | —            | —                                            |
| Open a branch from a template (create on Branch) | ✅                       | —              | —           | —              | —       | —            | —                                            |
| Classes (`CourseOffering`)                       | Edit all (group sharing) | Create/Edit    | Read        | Create/Edit    | Read    | Read         | Read                                         |
| Enrolments (`CourseOfferingParticipant`)         | Edit all (group sharing) | Create/Edit    | Create/Edit | Create/Edit    | Read    | Read         | Read                                         |
| Analytics (`AnalyticsController`)                | ✅                       | ✅             | —           | ✅             | —       | ✅           | —                                            |
| Retention desk (`RetentionController`)           | ✅ (+ recalculate)       | ✅             | —           | ✅             | —       | —            | —                                            |
| Library desk (`LibraryController`)               | ✅ lend, items           | ✅ lend, items | read        | ✅ lend, items | read    | fines (read) | —                                            |
| ERP export (`FinanceExportController`, exports)  | ✅                       | —              | —           | —              | —       | ✅           | ✅ (API)                                     |
| Payment links (`PaymentLinkController`)          | ✅                       | ✅ (view)      | ✅ (view)   | —              | —       | ✅           | —                                            |
| Integration events                               | Modify All               | —              | —           | —              | —       | View All     | View All                                     |
| LMS / ERP / payment webhook APIs                 | —                        | —              | —           | —              | —       | —            | ✅ (`KEM Integration`, `KEM Manage Billing`) |

**Administrator edit access to classes and enrolments:** the Education Cloud licence silently drops View All and Modify All on `CourseOffering` and `CourseOfferingParticipant` (the permission set says Modify All; the org stores neither). Edit access is therefore granted by **sharing**: owner-based sharing rules give the public group **KEM Administrators** Edit on every class and enrolment owned by internal users. The group's members are the users holding the KEM Administrator permission set; `AdminGroupService` keeps it in step — run after every deployment (`scripts/deploy.sh`) and from the operations console (**Sync administrators**, shown when an administrator is missing; needs user-management rights).

**KEM Integration persona** (permission set group `KEM_Integration_Persona`): an API-only user for the LMS, the ERP and the payment middleware. Reads classes, enrolments and learners (View All on accounts and contacts), finance documents (View All), creates assessments and results and finance exports, reads integration events (acknowledged through the API), and holds the KEM Integration and KEM Manage Billing custom permissions (the webhook records gateway payments).

**Secrets:** the payment webhook secret is stored in the custom setting `KEM_Gateway__c` (Public: production orgs cannot create Protected custom settings). No permission set grants access to custom settings; only administrators with View All Custom Settings can read it. It is entered in Setup only.

`BranchTemplateService` runs entirely as the user (user-mode queries and inserts), so cloning needs create access on every copied object; comparison figures only include records the user can see.

**Administrator edit access (Phase 3):** see _Administrator edit access to classes and enrolments_ under Phase 3 permissions — granted through the KEM Administrators group, not Modify All.

## Phase 4 permissions (AI)

| Permission / access                                      | Administrator                      | Other staff with **KEM AI User**          | Staff without it |
| -------------------------------------------------------- | ---------------------------------- | ----------------------------------------- | ---------------- |
| AI panels and Agentforce actions                         | ✅ (needs KEM AI User too)         | ✅                                        | Hidden / refused |
| Facts sent to the model                                  | What the user can see              | What the user can see (user-mode queries) | —                |
| AI interactions (`AI_Interaction__c`)                    | All (Modify All)                   | Own (read)                                | —                |
| AI console                                               | Everyone's figures, run evaluation | Own figures                               | —                |
| Evaluation results (`AI_Evaluation__c`)                  | ✅                                 | —                                         | —                |
| Saving AI output (reply task, comment, message, details) | Normal object permissions apply    | Normal object permissions apply           | —                |

**KEM AI User** (permission set `KEM_AI_User`): custom permission `KEM_Use_AI`, read on `AI_Interaction__c`, access to `AiController` and the `Agent*` action classes. It is assigned person by person, on top of the persona; it is not in any persona group. Opening the Agentforce agent also needs the user's Agentforce licence or permission set licence.

**Data protection:** model calls go through the Einstein Trust Layer (masking of personal data, zero retention by the model provider, audit). Prompts contain only the facts the feature needs; the document reader excludes health, religion, caste, income and identity numbers, and documents chosen from the computer are read in the browser and not stored. Switches: `AI_Enabled` (all AI) and `AI_Disabled_Features`. Interaction logs are private to their owner and administrators.

**System-mode operations (Phase 4):** AI interaction and evaluation logs are written by the system (`AiService.Writer`, `AiEvaluationService.Writer`) after the access check; the document reader writes `Document_Details__c` in system mode (system-managed field) after reading the application as the user; the prompt catalogue and evaluation cases are read in system mode (configuration).

**Forecasts (F4.8):** `ForecastController` for administrators, branch managers, academic coordinators and finance; every figure is read in user mode (enrolment figures need enrolment access, finance figures need invoice and payment access). The Einstein explanation and the Agentforce forecast action need KEM AI User.

## Phase 4 permissions (transport, exams, referrals)

| Permission / access                    | Administrator                                  | Branch Manager | Admissions               | Academic | Teacher | Finance               |
| -------------------------------------- | ---------------------------------------------- | -------------- | ------------------------ | -------- | ------- | --------------------- |
| Transport routes and stops             | Manage                                         | Manage         | Read                     | Read     | Read    | Read                  |
| Assign / end riders, message a route   | ✅                                             | ✅             | ✅                       | —        | —       | — (reads assignments) |
| Exams, papers, candidates (desk steps) | ✅                                             | ✅             | —                        | ✅       | Read    | —                     |
| Allow a withheld candidate             | with KEM Eligibility Override (permission set) |                |                          |          |         |                       |
| Enter exam marks                       | ✅                                             | ✅             | —                        | ✅       | ✅      | —                     |
| Referrals desk                         | ✅                                             | ✅             | ✅ (read, invite alumni) | —        | —       | ✅ (read)             |
| Grant a referral reward / not eligible | KEM Manage Billing (finance, administrators)   |                |                          |          |         |                       |

**System-mode operations (transport, exams, referrals):** seats taken, assignment and fee-line fields, candidate status and seats, marks, and referral fields are system-managed and written by the services after the user-mode checks (create access on the object, the custom permissions above). Referral codes on enquiries are matched in system mode (any channel may give a code; only the referrer's Id is used). Portal: transport details and hall tickets are read in system mode after the portal's own check that the learner belongs to the signed-in family.

## Phase 5 permissions (creation screens)

| Screen                                                        | Administrator                                     | Branch Manager                                              | Academic                                                     | Others |
| ------------------------------------------------------------- | ------------------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------ | ------ |
| Set-up Centre (`SetupCentreController`)                       | ✅ all tiles, New on every record they may create | ✅ (New room, class, staff role…; not branches)             | ✅ (New room, class)                                         | Hidden |
| New course, New class, New faculty (`CatalogSetupController`) | ✅ with prices                                    | — (standard class form; no course or weekly-pattern access) | ✅ course without prices (finance adds them), class, faculty | —      |

The Set-up Centre reads in user mode; "New" follows the user's create permission on each object and opens a guided screen only when the person can complete it (otherwise the standard form). The course, class and faculty screens save in user mode; duplicate checks (course code and name, faculty email) and creating the faculty account run in system mode and return no data.
