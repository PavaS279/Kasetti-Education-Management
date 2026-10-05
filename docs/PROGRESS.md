# Progress Tracker

> **Status 2026-10-03:** Phase 0 and Phase 1 are complete — every feature built, deployed, unit-tested and checked end to end, and one learner has completed the full journey with financial reconciliation (automated and live). Phase 2 (operational depth) is in progress — table below.

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

| #    | Feature                                               | Built | Deployed | Tests | E2E check | Notes                                                                                 |
| ---- | ----------------------------------------------------- | ----- | -------- | ----- | --------- | ------------------------------------------------------------------------------------- |
| 1.1  | Enquiries: capture, assignment, follow-up, conversion | ✅    | ✅       | ✅    | ✅        | [F1.1-enquiries.md](features/F1.1-enquiries.md)                                       |
| 1.2  | Learner & guardian records, Learner 360               | ✅    | ✅       | ✅    | ✅        | [F1.2-learners-guardians.md](features/F1.2-learners-guardians.md)                     |
| 1.3  | Applications: checklist, decision, offer, acceptance  | ✅    | ✅       | ✅    | ✅        | [F1.3-applications.md](features/F1.3-applications.md)                                 |
| 1.4  | Course prices and discounts                           | ✅    | ✅       | ✅    | ✅        | [F1.4-pricing-discounts.md](features/F1.4-pricing-discounts.md)                       |
| 1.5  | Enrolment with seat control and agreed price          | ✅    | ✅       | ✅    | ✅        | [F1.5-enrolment.md](features/F1.5-enrolment.md)                                       |
| 1.6  | Scheduling: sessions, conflicts, calendar             | ✅    | ✅       | ✅    | ✅        | [F1.6-scheduling.md](features/F1.6-scheduling.md)                                     |
| 1.7  | Attendance                                            | ✅    | ✅       | ✅    | ✅        | [F1.7-attendance.md](features/F1.7-attendance.md)                                     |
| 1.8  | Basic assessments                                     | ✅    | ✅       | ✅    | ✅        | [F1.8-assessments.md](features/F1.8-assessments.md)                                   |
| 1.9  | Invoices, payments, reconciliation                    | ✅    | ✅       | ✅    | ✅        | [F1.9-billing.md](features/F1.9-billing.md)                                           |
| 1.10 | Documents                                             | ✅    | ✅       | ✅    | ✅        | [F1.10-documents.md](features/F1.10-documents.md)                                     |
| 1.11 | Basic portal                                          | ✅    | ✅       | ✅    | ✅        | [F1.11-portal.md](features/F1.11-portal.md) — site placement is a manual Builder step |
| 1.12 | Dashboards                                            | ✅    | ✅       | ✅    | ✅        | [F1.12-dashboards.md](features/F1.12-dashboards.md)                                   |
| 1.13 | Full learner journey with financial reconciliation    | ✅    | ✅       | ✅    | ✅        | [F1.13-full-journey.md](features/F1.13-full-journey.md)                               |

**Phase 1 completion condition — one learner can complete the full journey with financial reconciliation:** ✅ (`FullJourneyTest` and the live run in [F1.13](features/F1.13-full-journey.md))

## Phase 2 — Operational depth

**Completion condition — exceptions and recurring operations work reliably.**

| #   | Feature                                                          | Built | Deployed | Tests | E2E check | Notes                                                                                   |
| --- | ---------------------------------------------------------------- | ----- | -------- | ----- | --------- | --------------------------------------------------------------------------------------- |
| 2.1 | Waitlists: queue, held seats, offers with expiry, accept → enrol | ✅    | ✅       | ✅    | ✅        | [F2.1-waitlists.md](features/F2.1-waitlists.md)                                         |
| 2.2 | Transfers between classes with price difference                  | ✅    | ✅       | ✅    | ✅        | [F2.2-transfers.md](features/F2.2-transfers.md)                                         |
| 2.3 | Recurring billing and instalment plans                           | ✅    | ✅       | ✅    | ✅        | [F2.3-recurring-billing-instalments.md](features/F2.3-recurring-billing-instalments.md) |
| 2.4 | Refund automation and credit notes                               | ✅    | ✅       | ✅    | ✅        | [F2.4-credit-notes-refunds.md](features/F2.4-credit-notes-refunds.md)                   |
| 2.5 | Messaging (templated notifications with consent)                 | ✅    | ✅       | ✅    | ✅        | [F2.5-messaging.md](features/F2.5-messaging.md)                                         |
| 2.6 | Resource substitution (teacher cover, room swaps)                | ✅    | ✅       | ✅    | ✅        | [F2.6-resource-substitution.md](features/F2.6-resource-substitution.md)                 |
| 2.7 | Advanced grading (weighted course grades, report cards)          | ⬜    | ⬜       | ⬜    | ⬜        |                                                                                         |
| 2.8 | Richer portal (documents, waitlist, instalments, messages)       | ⬜    | ⬜       | ⬜    | ⬜        |                                                                                         |
| 2.9 | Operations console and Phase 2 journey                           | ⬜    | ⬜       | ⬜    | ⬜        |                                                                                         |
