# Next Steps — Hand-over

_Last updated: 2026-10-06 after F3.9 (Phase 3 complete)._

## Where we are

Phases 0–3 are **complete**: features 1.1 – 1.13, 2.1 – 2.9 and 3.1 – 3.9 are built, deployed to the org, unit-tested (194 Apex tests, 94% coverage; 128 Jest tests) and checked end to end.

- Phase 1: a full learner journey with financial reconciliation (`FullJourneyTest`, `scripts/demo/full-journey.sh`).
- Phase 2: exceptions and recurring operations work reliably (`Phase2JourneyTest`, `scripts/demo/phase2-journey.sh`, 31 checks).
- Phase 3: additional centres and higher volumes — branch templates and comparison, limit-aware recurring billing and reminder batches, generic LMS and ERP APIs with an outbox, analytics, retention workflows, online payments in the portal (switched Off), a library module (`Phase3JourneyTest`, `VolumeTest`, `scripts/demo/phase3-journey.sh`, 26 checks).

See [PROGRESS.md](PROGRESS.md), [TEST-LOG.md](TEST-LOG.md) and [DEMO-SCRIPT.md](DEMO-SCRIPT.md).

## Org set-up completed on 2026-10-03

| Item           | Done                                                                                                                                                                                                                                                                                                           |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Staff personas | Kasetti Tech → `KEM_Administrator_Persona` + `KEM_Eligibility_Override`; Adam Admissions → `KEM_Admissions_Counsellor_Persona`; Anjali Advisor → `KEM_Academic_Coordinator_Persona`; Rahul Registrar → `KEM_Branch_Manager_Persona`; Andrea Advancement → `KEM_Finance_Persona` (mapped from their job titles) |
| Branch staff   | All four on `[KEM Demo] Bengaluru Central` with matching roles; Rahul Registrar is the branch manager                                                                                                                                                                                                          |
| Portal users   | Rohit Sharma, Priya Sharma, Lakshmi Iyer (`*.kemdemo@kasetti-portal.demo`, profile EDC Community User, `EducationCloudExprcCloudAccessPsl` + `KEM_Portal_User`); no welcome emails sent; 3 of 10 Customer Community Plus licences                                                                              |
| Org setting    | ExperienceBundle Metadata API enabled (Setup → Digital Experiences → Settings) so the site can be managed as metadata                                                                                                                                                                                          |

## Actions for you

| What                                                | Why it is still open                                                                                                                         | How                                                                                                                                                                                                       |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Portal logins for the demo guardians                | No passwords were set and no emails sent                                                                                                     | Setup → Users → _Reset Password_ (or log in as the user from the contact)                                                                                                                                 |
| UI screenshots from the build environment           | The client-credentials login only ever receives the `api` scope, so no browser session can be created; the web scope does not help this flow | Not needed for operation; check the screens in the app                                                                                                                                                    |
| Remove **Full access** from the External Client App | You planned to; nothing further needs it                                                                                                     | External Client App → OAuth scopes                                                                                                                                                                        |
| Switch email on                                     | `Email_Delivery` is **Off**: notifications are logged as Not Sent; portal messages are delivered                                             | Check Setup → Deliverability ("All email") and the sender address, then set Education Setting `Email_Delivery` = `Live`                                                                                   |
| Approve the waiting demo refund                     | RFD-000001 (1,200 on CN-000001) needs an approver other than the requester                                                                   | Finance Desk → Refunds → Approve (as an administrator or branch manager)                                                                                                                                  |
| Check the new screens in the browser                | The build environment has API access only; screens are covered by Jest tests                                                                 | Home (Analytics, Branches, Retention, Cover Desk, Operations), branch page (comparison, analytics, retention, library), Finance Desk (ERP export), invoice (Online payment), portal (Pay online, Library) |
| Create the integration user                         | The LMS, ERP and payment middleware need an API-only user                                                                                    | New user (API only) → permission set group **KEM Integration Persona** → Connected App with client credentials; keep its secret out of chat and tickets                                                   |
| Decide on the ERP outbox                            | `ERP_Outbox` is On: every invoice, payment, credit note and refund adds an event that waits until an ERP reads it (deleted after 90 days)    | Keep it On when the ERP will poll `/erp/events`; otherwise set Education Setting `ERP_Outbox` = Off (the journal export does not need it)                                                                 |
| Online payments                                     | `Payment_Gateway_Mode` is **Off**; the webhook has no secret                                                                                 | Choose the gateway, set `Payment_Checkout_URL`, enter the secret in Setup → Custom Settings → KEM Gateway, try `Test`, then `Live`                                                                        |
| Map ERP account codes                               | Defaults 1100/1010/1000/4000/2200/2300/4900                                                                                                  | Education Settings `ERP_Account_*` to your chart of accounts                                                                                                                                              |
| Add administrators                                  | Administrators edit others' classes through the KEM Administrators group                                                                     | After assigning KEM Administrator, use **Sync administrators** in the operations console (or the next deployment syncs it)                                                                                |

## Possible next steps (after Phase 3)

1. **Connect the chosen LMS and ERP** — the generic APIs and outbox are ready; add the named credentials `KEM_LMS` / `KEM_ERP` and switch push on if they prefer push to polling.
2. **Payment gateway** — connect middleware to the signed webhook; automatic gateway refunds (refunds are paid out manually today).
3. **SMS / WhatsApp** — messaging covers email and the portal inbox; add a provider through the same templates and consent.
4. **Billing refinements** — proration of part months, billing On Hold enrolments, pro-rata withdrawal refunds, credit note PDFs; library fines on invoices (settled at the desk today).
5. **Custom indexes** — request indexes on `Student_Invoice__c.Due_Date__c`, `Message__c.Status__c`, `Enrolment_Fee_Line__c.Next_Bill_Date__c` and `Class_Session__c.Start__c` from Salesforce Support when a table passes ~100,000 rows.
6. **Tabs** — the org is at its custom tab limit; library, payment links, exports and integration events are reached through the branch page, invoice page, Finance Desk and search.
7. **Portal home page** — the site's `/s/` home page still shows the template components that fail (AssignedResource, action plans); My Learning is unaffected.

## How to continue in a new session

1. Environment variables `SF_INSTANCE_URL`, `SF_CLIENT_ID`, `SF_CLIENT_SECRET` are configured in the cloud environment.
2. `npm install --global @salesforce/cli && npm install`
3. `./scripts/ci/sf-login.sh` (access token; re-run if it expires).
4. Change specs in `scripts/tooling/specs.py` → `python3 scripts/tooling/mdgen.py` → `scripts/deploy.sh` (pauses/resumes scheduled jobs, runs all `*Test` classes).
5. Follow the per-feature rhythm: build → deploy → Apex + Jest tests → live end-to-end check → `docs/features/F*.md` → PROGRESS + TEST-LOG (+ DEMO-SCRIPT and data/security/status docs when they change) → commit.
6. Demo runners: `scripts/demo/full-journey.sh` (Phase 1), `scripts/demo/phase2-journey.sh` (Phase 2) and `scripts/demo/phase3-journey.sh` (Phase 3) — each run creates its own tagged `[KEM Demo]` data.

## Lessons that save time (see 06-development-standards.md)

- Tests run as `TestDataFactory.admin()`; setup objects as the deployer.
- Education Cloud objects need the licensed `_Edu` permission sets (+ `AccessEducationCloud`, `GroupMembershipPsl`, `DocumentChecklistUserAccess`).
- Read-only (system-managed) fields must not be set in user-mode DML; stamp them in system mode after an access check.
- Teacher-authorised writes (attendance, results) use an inner `without sharing` writer after the teacher check.
- Apex identifiers are case-insensitive — a local `counted` shadows a constant `COUNTED`.
- Anonymous Apex cannot use `AccessLevel.SYSTEM_MODE`, and `AuraHandledException` cannot be thrown there; call services directly in scripts.
- `Message_Template__mdt.getAll()` cuts long text to 255 characters: query custom metadata (`WITH SYSTEM_MODE`, the org restricts custom metadata access).
- `hint`, `join`, `from` and `override` are reserved words in Apex; prettier reformats files on commit, so script edits must match the formatted text.
- Long tests hit 100 SOQL queries: give heavy sections their own `Test.startTest()` context or split the test.
- A queueable cannot start another queueable in tests ("maximum stack depth").
- The org is at its custom tab limit; new objects cannot get tabs.
- The Education Cloud licence silently drops View All / Modify All on `CourseOffering` and `CourseOfferingParticipant` (the deploy succeeds; check `ObjectPermissions`). Use sharing rules to a group instead.
- Production orgs reject Protected custom settings; one class cannot be both Queueable and Schedulable; `Database.queryWithBinds` returns `List<SObject>` (cast to `List<AggregateResult>` for aggregates).
- In tests, `Request.getCurrent().getRequestId()` is the same for setup and test methods — do not use it for uniqueness.
- Recurring billing costs ~18 queries per enrolment: keep batches small (Education Setting `Recurring_Billing_Batch_Size`).

## Demo data in the org (prefixed `[KEM Demo]`)

Phase 3 additions: branch **[KEM Demo] Whitefield** (DEMO-02, prefix WFD) opened from Bengaluru Central with 2 rooms, 1 price, 1 closure and 7 Planned classes (Maths Foundation has 14 generated sessions); demo centres **[KEM Demo] Centre P3A / P3B** (D3-P3A, D3-P3B) from the Phase 3 runner with a learner, invoice, LMS quiz and a returned library loan each; library items **[KEM Demo] Wings of Fire** (DEMO-B-001) and **Robotics Starter Kit** (DEMO-K-001) with loans LN-000000 and the kit to Ananya Sharma; export EXP-000000 (1–6 Oct journal); integration events acknowledged.

Phase 2 additions: monthly course `KEM-DEMO-CODING` (Coding Club, admission 1,000 + tuition 2,500 monthly) with learner Ishaan Rao and invoices BLR-000005/6/7/8 (instalment plan, credit notes CN-000000/1, refunds RFD-000000 paid and RFD-000001 waiting); class _Waitlist Demo – Sunday_; room 102; Kasetti Tech and Anjali Advisor as Teachers at the demo branch; absence ABS-00000 (Saturday 10 Oct covered by Anjali, moved to room 102); the Saturday Maths class with grades finalised and report cards; Phase 2 demo runs ("Guardian ‹tag› [KEM Demo] Phase2").

Phase 1:

Branch `DEMO-01`, room 101, course `KEM-DEMO-MATH` with prices and discount `SIBLING10`, classes `KEM-DEMO-CLS-1` (13 Saturday sessions + 1 make-up) and `KEM-DEMO-CLS-2`, learners Ananya and Arjun Sharma, guardians Rohit and Priya Sharma, application `IA-0000000032` (Enrolled), closure _Diwali break_. The admin user is assigned as the demo branch's admissions counsellor and the demo class teacher.
