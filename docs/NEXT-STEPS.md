# Next Steps — Hand-over

_Last updated: 2026-10-03 after F1.13 (Phase 1 complete)._

## Where we are

Phase 0 and Phase 1 are **complete**: features 1.1 – 1.13 are built, deployed to the org, unit-tested (101 Apex tests in 22 test classes, 94% coverage; 40 Jest tests in 16 suites) and checked end to end, including a full learner journey with financial reconciliation (automated in `FullJourneyTest` and run live). See [PROGRESS.md](PROGRESS.md) and [TEST-LOG.md](TEST-LOG.md).

## Org set-up completed on 2026-10-03

| Item           | Done                                                                                                                                                                                                                                                                                                           |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Staff personas | Kasetti Tech → `KEM_Administrator_Persona` + `KEM_Eligibility_Override`; Adam Admissions → `KEM_Admissions_Counsellor_Persona`; Anjali Advisor → `KEM_Academic_Coordinator_Persona`; Rahul Registrar → `KEM_Branch_Manager_Persona`; Andrea Advancement → `KEM_Finance_Persona` (mapped from their job titles) |
| Branch staff   | All four on `[KEM Demo] Bengaluru Central` with matching roles; Rahul Registrar is the branch manager                                                                                                                                                                                                          |
| Portal users   | Rohit Sharma, Priya Sharma, Lakshmi Iyer (`*.kemdemo@kasetti-portal.demo`, profile EDC Community User, `EducationCloudExprcCloudAccessPsl` + `KEM_Portal_User`); no welcome emails sent; 3 of 10 Customer Community Plus licences                                                                              |
| Org setting    | ExperienceBundle Metadata API enabled (Setup → Digital Experiences → Settings) so the site can be managed as metadata                                                                                                                                                                                          |

## Actions for you

| What                                                | Why it is still open                                                                                                                         | How                                                                       |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Portal logins for the demo guardians                | No passwords were set and no emails sent                                                                                                     | Setup → Users → _Reset Password_ (or log in as the user from the contact) |
| UI screenshots from the build environment           | The client-credentials login only ever receives the `api` scope, so no browser session can be created; the web scope does not help this flow | Not needed for operation; check the screens in the app                    |
| Remove **Full access** from the External Client App | You planned to; nothing further needs it                                                                                                     | External Client App → OAuth scopes                                        |

## Suggested next phases (not started)

1. **Payment gateway connector** — signed webhooks (HMAC) in front of `/kem/v1/payments`, hosted payment links on invoices and in the portal.
2. **Communications** — templated email/SMS/WhatsApp for offers, invoices, receipts, attendance alerts (consent fields already exist).
3. **Recurring billing** — monthly/term instalment schedules from `Billing_Frequency__c`, credit notes and refunds.
4. **Portal self-service** — download invoice/receipt PDFs, pay online, update contact preferences.
5. **Progress reports** — weighted course grades from assessment weights, term report cards (PDF).

## How to continue in a new session

1. Environment variables `SF_INSTANCE_URL`, `SF_CLIENT_ID`, `SF_CLIENT_SECRET` are configured in the cloud environment.
2. `npm install --global @salesforce/cli && npm install`
3. `./scripts/ci/sf-login.sh` (access token; re-run if it expires).
4. Change specs in `scripts/tooling/specs.py` → `python3 scripts/tooling/mdgen.py` → `scripts/deploy.sh` (pauses/resumes scheduled jobs, runs all `*Test` classes).
5. Follow the per-feature rhythm: build → deploy → Apex + Jest tests → live end-to-end check → `docs/features/F1.x-*.md` → PROGRESS + TEST-LOG → commit.

## Lessons that save time (see 06-development-standards.md)

- Tests run as `TestDataFactory.admin()`; setup objects as the deployer.
- Education Cloud objects need the licensed `_Edu` permission sets (+ `AccessEducationCloud`, `GroupMembershipPsl`, `DocumentChecklistUserAccess`).
- Read-only (system-managed) fields must not be set in user-mode DML; stamp them in system mode after an access check.
- Teacher-authorised writes (attendance, results) use an inner `without sharing` writer after the teacher check.
- Apex identifiers are case-insensitive — a local `counted` shadows a constant `COUNTED`.
- Anonymous Apex cannot use `AccessLevel.SYSTEM_MODE`, and `AuraHandledException` cannot be thrown there; call services directly in scripts.

## Demo data in the org (prefixed `[KEM Demo]`)

Branch `DEMO-01`, room 101, course `KEM-DEMO-MATH` with prices and discount `SIBLING10`, classes `KEM-DEMO-CLS-1` (13 Saturday sessions + 1 make-up) and `KEM-DEMO-CLS-2`, learners Ananya and Arjun Sharma, guardians Rohit and Priya Sharma, application `IA-0000000032` (Enrolled), closure _Diwali break_. The admin user is assigned as the demo branch's admissions counsellor and the demo class teacher.
