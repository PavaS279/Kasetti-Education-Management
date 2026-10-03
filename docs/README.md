# Kasetti Education Management — Documentation

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

| Feature                   | Guide                                                                      |
| ------------------------- | -------------------------------------------------------------------------- |
| F1.1 Enquiries            | [features/F1.1-enquiries.md](features/F1.1-enquiries.md)                   |
| F1.2 Learners & guardians | [features/F1.2-learners-guardians.md](features/F1.2-learners-guardians.md) |
| F1.3 Applications         | [features/F1.3-applications.md](features/F1.3-applications.md)             |
| F1.4 Pricing & discounts  | [features/F1.4-pricing-discounts.md](features/F1.4-pricing-discounts.md)   |
| F1.5 Enrolment            | [features/F1.5-enrolment.md](features/F1.5-enrolment.md)                   |
| F1.6 Scheduling           | [features/F1.6-scheduling.md](features/F1.6-scheduling.md)                 |
| F1.7 Attendance           | [features/F1.7-attendance.md](features/F1.7-attendance.md)                 |
| F1.8 Assessments          | [features/F1.8-assessments.md](features/F1.8-assessments.md)               |
| F1.9 Billing              | [features/F1.9-billing.md](features/F1.9-billing.md)                       |
| F1.10 Documents           | [features/F1.10-documents.md](features/F1.10-documents.md)                 |
| F1.11 Portal              | [features/F1.11-portal.md](features/F1.11-portal.md)                       |
