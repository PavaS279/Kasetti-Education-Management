# Kasetti Education Management — Documentation

> **Start here:** [WALKTHROUGH.md](WALKTHROUGH.md) — the complete walkthrough by role, with set-up, addresses and real-world examples.
>
> **Demo & test:** [DEMO-SCRIPT.md](DEMO-SCRIPT.md) — Phase 1 journey (`scripts/demo/full-journey.sh`), Phase 2 operations (`scripts/demo/phase2-journey.sh`) Phase 3 scale (`scripts/demo/phase3-journey.sh`) and Phase 4 AI and expansion (`scripts/demo/phase4-journey.sh`). AI: [ai/AI-OPPORTUNITIES.md](ai/AI-OPPORTUNITIES.md) (analysis) and [ai/MEASURED-BENEFIT.md](ai/MEASURED-BENEFIT.md) (measured benefit, access and review). Hand-over: [NEXT-STEPS.md](NEXT-STEPS.md).

Delivery documentation for the Salesforce Education Cloud implementation. Read in this order:

| #   | Document                                                   | Purpose                                                                |
| --- | ---------------------------------------------------------- | ---------------------------------------------------------------------- |
| 1   | [PROGRESS.md](PROGRESS.md)                                 | Stage tracker: what is built, deployed, and tested, feature by feature |
| 2   | [01-solution-architecture.md](01-solution-architecture.md) | Foundation decision, native vs custom mapping, layering                |
| 3   | [02-data-model.md](02-data-model.md)                       | Objects, relationships, key fields                                     |
| 4   | [03-security-model.md](03-security-model.md)               | Personas, permission sets, sharing, access scenarios                   |
| 5   | [04-statuses-and-policies.md](04-statuses-and-policies.md) | Status lifecycles, transitions, configurable policies                  |
| 6   | [05-data-migration.md](05-data-migration.md)               | Load order, external IDs, templates, validation                        |
| 7   | [06-development-standards.md](06-development-standards.md) | Coding, testing, and deployment conventions                            |
| 8   | [TEST-LOG.md](TEST-LOG.md)                                 | Deployment and test evidence (deploy IDs, results, end-to-end checks)  |
| 9   | [adr/](adr/)                                               | Architecture decision records                                          |

Target org: Kasetti Technologies Pvt Ltd (Enterprise Edition, Education Cloud), My Domain `kasettitechnologiespvtltd.my.salesforce.com`.

## Feature guides

| Feature                                   | Guide                                                                                            |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------ |
| F1.1 Enquiries                            | [features/F1.1-enquiries.md](features/F1.1-enquiries.md)                                         |
| F1.2 Learners & guardians                 | [features/F1.2-learners-guardians.md](features/F1.2-learners-guardians.md)                       |
| F1.3 Applications                         | [features/F1.3-applications.md](features/F1.3-applications.md)                                   |
| F1.4 Pricing & discounts                  | [features/F1.4-pricing-discounts.md](features/F1.4-pricing-discounts.md)                         |
| F1.5 Enrolment                            | [features/F1.5-enrolment.md](features/F1.5-enrolment.md)                                         |
| F1.6 Scheduling                           | [features/F1.6-scheduling.md](features/F1.6-scheduling.md)                                       |
| F1.7 Attendance                           | [features/F1.7-attendance.md](features/F1.7-attendance.md)                                       |
| F1.8 Assessments                          | [features/F1.8-assessments.md](features/F1.8-assessments.md)                                     |
| F1.9 Billing                              | [features/F1.9-billing.md](features/F1.9-billing.md)                                             |
| F1.10 Documents                           | [features/F1.10-documents.md](features/F1.10-documents.md)                                       |
| F1.11 Portal                              | [features/F1.11-portal.md](features/F1.11-portal.md)                                             |
| F1.12 Dashboards                          | [features/F1.12-dashboards.md](features/F1.12-dashboards.md)                                     |
| F1.13 Full journey                        | [features/F1.13-full-journey.md](features/F1.13-full-journey.md)                                 |
| F2.1 Waitlists                            | [features/F2.1-waitlists.md](features/F2.1-waitlists.md)                                         |
| F2.2 Transfers                            | [features/F2.2-transfers.md](features/F2.2-transfers.md)                                         |
| F2.3 Recurring billing & instalments      | [features/F2.3-recurring-billing-instalments.md](features/F2.3-recurring-billing-instalments.md) |
| F2.4 Credit notes & refunds               | [features/F2.4-credit-notes-refunds.md](features/F2.4-credit-notes-refunds.md)                   |
| F2.5 Messaging                            | [features/F2.5-messaging.md](features/F2.5-messaging.md)                                         |
| F2.6 Teacher cover & room swaps           | [features/F2.6-resource-substitution.md](features/F2.6-resource-substitution.md)                 |
| F2.7 Grading & report cards               | [features/F2.7-advanced-grading.md](features/F2.7-advanced-grading.md)                           |
| F2.8 Richer portal                        | [features/F2.8-richer-portal.md](features/F2.8-richer-portal.md)                                 |
| F2.9 Operations console & Phase 2 journey | [features/F2.9-operations-console.md](features/F2.9-operations-console.md)                       |
| F3.1 Multi-branch templates               | [features/F3.1-multi-branch-templates.md](features/F3.1-multi-branch-templates.md)               |
| F3.2 Scale and performance                | [features/F3.2-scale-and-performance.md](features/F3.2-scale-and-performance.md)                 |
| F3.3 LMS integration API                  | [features/F3.3-lms-integration.md](features/F3.3-lms-integration.md)                             |
| F3.4 ERP finance export                   | [features/F3.4-erp-export.md](features/F3.4-erp-export.md)                                       |
| F3.5 Advanced analytics                   | [features/F3.5-advanced-analytics.md](features/F3.5-advanced-analytics.md)                       |
| F3.6 Retention workflows                  | [features/F3.6-retention-workflows.md](features/F3.6-retention-workflows.md)                     |
| F3.7 Online payments                      | [features/F3.7-online-payments.md](features/F3.7-online-payments.md)                             |
| F3.8 Library and resources                | [features/F3.8-library.md](features/F3.8-library.md)                                             |
| F3.9 Phase 3 journey                      | [features/F3.9-phase3-journey.md](features/F3.9-phase3-journey.md)                               |
| F4.1 AI foundation                        | [features/F4.1-ai-foundation.md](features/F4.1-ai-foundation.md)                                 |
| F4.2–F4.5 AI assistants                   | [features/F4.2-F4.5-ai-assistants.md](features/F4.2-F4.5-ai-assistants.md)                       |
| F4.6 Agentforce staff assistant           | [features/F4.6-agentforce-staff-assistant.md](features/F4.6-agentforce-staff-assistant.md)       |
| F4.7 Document extraction                  | [features/F4.7-document-extraction.md](features/F4.7-document-extraction.md)                     |
| F4.8 Forecasting                          | [features/F4.8-forecasting.md](features/F4.8-forecasting.md)                                     |
| F4.9 Transport                            | [features/F4.9-transport.md](features/F4.9-transport.md)                                         |
| F4.10 Exams and hall tickets              | [features/F4.10-exams-and-hall-tickets.md](features/F4.10-exams-and-hall-tickets.md)             |
| F4.11 Alumni and referrals                | [features/F4.11-alumni-and-referrals.md](features/F4.11-alumni-and-referrals.md)                 |
| F4.12 Phase 4 journey                     | [features/F4.12-phase4-journey.md](features/F4.12-phase4-journey.md)                             |
