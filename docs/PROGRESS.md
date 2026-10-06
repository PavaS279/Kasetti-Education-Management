# Progress Tracker

> **Status 2026-10-06:** Phases 0, 1, 2 and 3 are complete — every feature built, deployed, unit-tested and checked end to end. Phase 1: one learner completes the full journey with financial reconciliation. Phase 2: exceptions and recurring operations work reliably. Phase 3: additional centres and higher volumes are supported (branch templates, limit-aware batches, LMS and ERP APIs, analytics, retention, online payments, library).

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

**Completion condition — exceptions and recurring operations work reliably:** ✅ (`Phase2JourneyTest`, the live checks of F2.1–F2.9, `scripts/demo/phase2-journey.sh` passing 31 of 31 checks live, and the operations console reporting healthy)

| #   | Feature                                                            | Built | Deployed | Tests | E2E check | Notes                                                                                   |
| --- | ------------------------------------------------------------------ | ----- | -------- | ----- | --------- | --------------------------------------------------------------------------------------- |
| 2.1 | Waitlists: queue, held seats, offers with expiry, accept → enrol   | ✅    | ✅       | ✅    | ✅        | [F2.1-waitlists.md](features/F2.1-waitlists.md)                                         |
| 2.2 | Transfers between classes with price difference                    | ✅    | ✅       | ✅    | ✅        | [F2.2-transfers.md](features/F2.2-transfers.md)                                         |
| 2.3 | Recurring billing and instalment plans                             | ✅    | ✅       | ✅    | ✅        | [F2.3-recurring-billing-instalments.md](features/F2.3-recurring-billing-instalments.md) |
| 2.4 | Refund automation and credit notes                                 | ✅    | ✅       | ✅    | ✅        | [F2.4-credit-notes-refunds.md](features/F2.4-credit-notes-refunds.md)                   |
| 2.5 | Messaging (templated notifications with consent)                   | ✅    | ✅       | ✅    | ✅        | [F2.5-messaging.md](features/F2.5-messaging.md)                                         |
| 2.6 | Resource substitution (teacher cover, room swaps)                  | ✅    | ✅       | ✅    | ✅        | [F2.6-resource-substitution.md](features/F2.6-resource-substitution.md)                 |
| 2.7 | Advanced grading (weighted course grades, report cards)            | ✅    | ✅       | ✅    | ✅        | [F2.7-advanced-grading.md](features/F2.7-advanced-grading.md)                           |
| 2.8 | Richer portal (documents, waitlist, instalments, messages, grades) | ✅    | ✅       | ✅    | ✅        | [F2.8-richer-portal.md](features/F2.8-richer-portal.md)                                 |
| 2.9 | Operations console and Phase 2 journey                             | ✅    | ✅       | ✅    | ✅        | [F2.9-operations-console.md](features/F2.9-operations-console.md)                       |

## Phase 3 — Scale and optimisation

**Completion condition — additional centres and higher volumes supported:** ✅ (`Phase3JourneyTest`, `VolumeTest`, the live checks of F3.1–F3.9 and `scripts/demo/phase3-journey.sh` passing 26 of 26 checks live)

Scope chosen by the institution (2026-10-05): a generic LMS API (no LMS yet), a generic ERP export/API, online payments in the portal, and a library/resources module. Administrators have edit access to every class and enrolment through the **KEM Administrators** group (owner sharing rules; the Education Cloud licence does not allow Modify All on these objects) (2026-10-06; the Modify All permission deployed on 2026-10-05 is not stored by the licence).

| #   | Feature                                                                                       | Built | Deployed | Tests | E2E check | Notes                                                                     |
| --- | --------------------------------------------------------------------------------------------- | ----- | -------- | ----- | --------- | ------------------------------------------------------------------------- |
| 3.1 | Multi-branch templates (clone a branch's set-up; branch KPIs)                                 | ✅    | ✅       | ✅    | ✅        | [F3.1-multi-branch-templates.md](features/F3.1-multi-branch-templates.md) |
| 3.2 | Scale and performance (bulk-safe batches, selective queries, volume tests)                    | ✅    | ✅       | ✅    | ✅        | [F3.2-scale-and-performance.md](features/F3.2-scale-and-performance.md)   |
| 3.3 | Generic LMS integration API (outbound events, inbound REST for classes, rosters, grades)      | ✅    | ✅       | ✅    | ✅        | [F3.3-lms-integration.md](features/F3.3-lms-integration.md)               |
| 3.4 | Generic ERP finance export (journal of invoices, payments, credits, refunds; CSV/JSON + REST) | ✅    | ✅       | ✅    | ✅        | [F3.4-erp-export.md](features/F3.4-erp-export.md)                         |
| 3.5 | Advanced analytics (branch comparison, revenue trends, cohorts)                               | ✅    | ✅       | ✅    | ✅        | [F3.5-advanced-analytics.md](features/F3.5-advanced-analytics.md)         |
| 3.6 | Retention workflows (at-risk scoring, follow-up tasks, re-enrolment campaigns)                | ✅    | ✅       | ✅    | ✅        | [F3.6-retention-workflows.md](features/F3.6-retention-workflows.md)       |
| 3.7 | Online payments in the portal (gateway-agnostic payment links, signed webhook)                | ✅    | ✅       | ✅    | ✅        | [F3.7-online-payments.md](features/F3.7-online-payments.md)               |
| 3.8 | Library and resources (catalogue, loans, due dates, fines)                                    | ✅    | ✅       | ✅    | ✅        | [F3.8-library.md](features/F3.8-library.md)                               |
| 3.9 | Phase 3 journey, volume test and demo script                                                  | ✅    | ✅       | ✅    | ✅        | [F3.9-phase3-journey.md](features/F3.9-phase3-journey.md)                 |

## Phase 4 — AI and expansion

**Completion condition — measured benefit with controlled access and review:** ⬜

Choices (2026-10-06): Salesforce Einstein (Models API, Trust Layer) and Agentforce; assistants for enquiry replies, document extraction, learner progress summaries, staff policy Q&A and record summaries; forecasting of enrolments/seats and revenue/collections; transport, exams and hall tickets, alumni and referrals. Analysis: [ai/AI-OPPORTUNITIES.md](ai/AI-OPPORTUNITIES.md).

| #    | Feature                                                                                               | Built | Deployed | Tests | E2E check | Notes |
| ---- | ----------------------------------------------------------------------------------------------------- | ----- | -------- | ----- | --------- | ----- |
| 4.1  | AI foundation: Einstein service, prompt catalogue, access control, review log, evaluation, AI console | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 4.2  | Enquiry reply drafts                                                                                  | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 4.3  | Learner progress summaries and report-card comment drafts                                             | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 4.4  | Record summaries (enquiry, application, class, branch brief, finance brief)                           | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 4.5  | Staff policy Q&A with sources                                                                         | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 4.6  | Agentforce staff assistant topic and actions                                                          | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 4.7  | Document extraction support for applications                                                          | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 4.8  | Forecasting: enrolments and seats, revenue and collections                                            | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 4.9  | Transport: routes, stops, assignments, transport fees                                                 | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 4.10 | Exams and hall tickets                                                                                | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 4.11 | Alumni and referrals                                                                                  | ⬜    | ⬜       | ⬜    | ⬜        |       |
| 4.12 | Phase 4 journey, evaluation report and demo                                                           | ⬜    | ⬜       | ⬜    | ⬜        |       |
