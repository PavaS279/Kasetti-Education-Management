# Next Steps — Hand-over for the next working session

_Last updated: 2026-10-03 after F1.7._

## Where we are

Phase 0 is complete. Phase 1 features **1.1 – 1.7** are built, deployed to the org, unit-tested (75 Apex tests, 95% coverage; 20 Jest tests), and end-to-end checked. See [PROGRESS.md](PROGRESS.md).

## Remaining Phase 1 work (in this order)

| #    | Feature                            | Design already decided                                                                                                                                                                                                                                                                                                        |
| ---- | ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1.8  | Basic assessments                  | ✅ Done — see [features/F1.8-assessments.md](features/F1.8-assessments.md)                                                                                                                                                                                                                                                    |
| 1.9  | Invoices, payments, reconciliation | ✅ Done — see [features/F1.9-billing.md](features/F1.9-billing.md)                                                                                                                                                                                                                                                            |
| 1.10 | Documents                          | ✅ Done — see [features/F1.10-documents.md](features/F1.10-documents.md)                                                                                                                                                                                                                                                      |
| 1.11 | Basic portal                       | LWC for Experience Cloud site `TrialOrgPortal`: learner/guardian home (timetable, attendance, results, invoices), access through `GuardianRelationshipService.learnersOf(contact, portalOnly=true)` ([ADR-003](adr/ADR-003-portal-access.md)); `KEM_Portal_User` permission set (licence `EducationCloudExprcCloudAccessPsl`) |
| 1.12 | Dashboards                         | Reports + dashboard: admissions funnel, class occupancy, attendance, finance (invoiced, collected, outstanding); `Kasetti Education` home page                                                                                                                                                                                |
| 1.13 | Full journey                       | One Apex test and one live run: enquiry → application → offer → enrolment → sessions → attendance → assessment → invoice → payment → reconciled                                                                                                                                                                               |

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
