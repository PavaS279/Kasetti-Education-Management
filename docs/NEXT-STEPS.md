# Next Steps — Hand-over

_Last updated: 2026-10-05 after F2.9 (Phase 2 complete)._

## Where we are

Phases 0, 1 and 2 are **complete**: features 1.1 – 1.13 and 2.1 – 2.9 are built, deployed to the org, unit-tested (139 Apex tests, 94% coverage; 87 Jest tests) and checked end to end. Phase 1: a full learner journey with financial reconciliation (`FullJourneyTest`, `scripts/demo/full-journey.sh`). Phase 2: exceptions and recurring operations — waitlists, transfers, recurring billing, instalments, credit and refunds, messaging, teacher cover, grading and report cards, the richer portal and the operations console (`Phase2JourneyTest`, `scripts/demo/phase2-journey.sh`, all 31 checks passing live). See [PROGRESS.md](PROGRESS.md), [TEST-LOG.md](TEST-LOG.md) and [DEMO-SCRIPT.md](DEMO-SCRIPT.md).

## Org set-up completed on 2026-10-03

| Item           | Done                                                                                                                                                                                                                                                                                                           |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Staff personas | Kasetti Tech → `KEM_Administrator_Persona` + `KEM_Eligibility_Override`; Adam Admissions → `KEM_Admissions_Counsellor_Persona`; Anjali Advisor → `KEM_Academic_Coordinator_Persona`; Rahul Registrar → `KEM_Branch_Manager_Persona`; Andrea Advancement → `KEM_Finance_Persona` (mapped from their job titles) |
| Branch staff   | All four on `[KEM Demo] Bengaluru Central` with matching roles; Rahul Registrar is the branch manager                                                                                                                                                                                                          |
| Portal users   | Rohit Sharma, Priya Sharma, Lakshmi Iyer (`*.kemdemo@kasetti-portal.demo`, profile EDC Community User, `EducationCloudExprcCloudAccessPsl` + `KEM_Portal_User`); no welcome emails sent; 3 of 10 Customer Community Plus licences                                                                              |
| Org setting    | ExperienceBundle Metadata API enabled (Setup → Digital Experiences → Settings) so the site can be managed as metadata                                                                                                                                                                                          |

## Actions for you

| What                                                | Why it is still open                                                                                                                         | How                                                                                                                     |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Portal logins for the demo guardians                | No passwords were set and no emails sent                                                                                                     | Setup → Users → _Reset Password_ (or log in as the user from the contact)                                               |
| UI screenshots from the build environment           | The client-credentials login only ever receives the `api` scope, so no browser session can be created; the web scope does not help this flow | Not needed for operation; check the screens in the app                                                                  |
| Remove **Full access** from the External Client App | You planned to; nothing further needs it                                                                                                     | External Client App → OAuth scopes                                                                                      |
| Switch email on                                     | `Email_Delivery` is **Off**: notifications are logged as Not Sent; portal messages are delivered                                             | Check Setup → Deliverability ("All email") and the sender address, then set Education Setting `Email_Delivery` = `Live` |
| Approve the waiting demo refund                     | RFD-000001 (1,200 on CN-000001) needs an approver other than the requester                                                                   | Finance Desk → Refunds → Approve (as an administrator or branch manager)                                                |
| Check the new screens in the browser                | The build environment has API access only; screens are covered by Jest tests                                                                 | Home (Cover Desk, Operations), class page (Waitlist, Course grades), invoice, credit note, learner Messages, portal     |

## Not in Phase 2 (possible next steps)

1. **Payment gateway connector** — signed webhooks (HMAC) in front of `/kem/v1/payments`, hosted payment links on invoices and in the portal, automatic gateway refunds (refunds are paid out manually today).
2. **SMS / WhatsApp** — messaging covers email and the portal inbox; add a provider through the same templates and consent.
3. **Billing refinements** — proration of part months, billing On Hold enrolments, pro-rata withdrawal refunds (entered by finance today), credit note PDFs.
4. **More notices** — enrolment confirmation and transfer templates (8 events today).
5. **Tabs** — the org is at its custom tab limit; credit notes, refunds and absences are reached through the Finance Desk, Cover Desk and search.
6. **Portal home page** — the site's `/s/` home page still shows the template components that fail (AssignedResource, action plans); My Learning is unaffected.

## How to continue in a new session

1. Environment variables `SF_INSTANCE_URL`, `SF_CLIENT_ID`, `SF_CLIENT_SECRET` are configured in the cloud environment.
2. `npm install --global @salesforce/cli && npm install`
3. `./scripts/ci/sf-login.sh` (access token; re-run if it expires).
4. Change specs in `scripts/tooling/specs.py` → `python3 scripts/tooling/mdgen.py` → `scripts/deploy.sh` (pauses/resumes scheduled jobs, runs all `*Test` classes).
5. Follow the per-feature rhythm: build → deploy → Apex + Jest tests → live end-to-end check → `docs/features/F*.md` → PROGRESS + TEST-LOG (+ DEMO-SCRIPT and data/security/status docs when they change) → commit.
6. Demo runners: `scripts/demo/full-journey.sh` (Phase 1) and `scripts/demo/phase2-journey.sh` (Phase 2) — each run creates its own tagged `[KEM Demo]` data.

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

## Demo data in the org (prefixed `[KEM Demo]`)

Phase 2 additions: monthly course `KEM-DEMO-CODING` (Coding Club, admission 1,000 + tuition 2,500 monthly) with learner Ishaan Rao and invoices BLR-000005/6/7/8 (instalment plan, credit notes CN-000000/1, refunds RFD-000000 paid and RFD-000001 waiting); class _Waitlist Demo – Sunday_; room 102; Kasetti Tech and Anjali Advisor as Teachers at the demo branch; absence ABS-00000 (Saturday 10 Oct covered by Anjali, moved to room 102); the Saturday Maths class with grades finalised and report cards; Phase 2 demo runs ("Guardian ‹tag› [KEM Demo] Phase2").

Phase 1:

Branch `DEMO-01`, room 101, course `KEM-DEMO-MATH` with prices and discount `SIBLING10`, classes `KEM-DEMO-CLS-1` (13 Saturday sessions + 1 make-up) and `KEM-DEMO-CLS-2`, learners Ananya and Arjun Sharma, guardians Rohit and Priya Sharma, application `IA-0000000032` (Enrolled), closure _Diwali break_. The admin user is assigned as the demo branch's admissions counsellor and the demo class teacher.
