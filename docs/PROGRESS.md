# Progress Tracker

> **Status 2026-10-03:** Phase 0 complete. Phase 1 features 1.1–1.7 complete (deployed, tested, end-to-end checked). Next: 1.8 Assessments — see [NEXT-STEPS.md](NEXT-STEPS.md).

Legend: ✅ done · 🟡 in progress · ⬜ not started

Each feature is complete only when it is **built, deployed to the org, unit-tested, and checked end to end**.

## Phase 0 — Foundation

| #   | Feature                                                                            | Built | Deployed      | Tests | E2E check                                | Notes                                                                       |
| --- | ---------------------------------------------------------------------------------- | ----- | ------------- | ----- | ---------------------------------------- | --------------------------------------------------------------------------- |
| 0.1 | Org analysis & data model decision                                                 | ✅    | n/a           | n/a   | n/a                                      | [01-solution-architecture.md](01-solution-architecture.md), ADR-001/002/003 |
| 0.2 | Apex framework (trigger handler, logger, settings, status transitions, exceptions) | ✅    | ✅            | ✅    | ✅ live logger smoke test                |                                                                             |
| 0.3 | Branch & Room model with policies                                                  | ✅    | ✅            | ✅    | ✅                                       | Branch manager managed sharing                                              |
| 0.4 | Security model: 7 permission sets, Lightning app, tabs                             | ✅    | ✅            | ✅    | ✅ `SecurityModelTest` persona scenarios |                                                                             |
| 0.5 | Statuses & policies definition                                                     | ✅    | ✅ (settings) | ✅    | n/a                                      | Transition records added per feature                                        |
| 0.6 | Migration preparation (external IDs, load order, templates)                        | ✅    | n/a           | n/a   | n/a                                      | [05-data-migration.md](05-data-migration.md)                                |

**Phase 0 completion condition — data model and access scenarios validated:** ✅

## Phase 1 — Operational MVP

| #    | Feature                                               | Built | Deployed | Tests | E2E check | Notes |
| ---- | ----------------------------------------------------- | ----- | -------- | ----- | --------- | ----- |
| 1.1  | Enquiries: capture, assignment, follow-up, conversion | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 1.2  | Learner & guardian records, Learner 360               | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 1.3  | Applications: checklist, decision, offer, acceptance  | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 1.4  | Course prices and discounts                           | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 1.5  | Enrolment with seat control and agreed price          | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 1.6  | Scheduling: sessions, conflicts, calendar             | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 1.7  | Attendance                                            | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 1.8  | Basic assessments                                     | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 1.9  | Invoices, payments, reconciliation                    | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 1.10 | Documents                                             | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 1.11 | Basic portal                                          | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 1.12 | Dashboards                                            | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 1.13 | Full learner journey with financial reconciliation    | ⬜    | ⬜       | ⬜    | ⬜        |       |
