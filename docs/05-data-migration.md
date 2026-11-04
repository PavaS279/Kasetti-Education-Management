# 05 — Data Migration Preparation

## Principles

- Every migrated object has a unique, case-insensitive `External_Id__c` (or `Branch_Code__c` for branches); loads are **upserts** so re-runs are safe.
- Education Cloud objects already carry `External_ID__c` (LearningProgram, LearningCourse, CourseOffering, CourseOfferingParticipant, CourseOfferingSchedule, AcademicTerm, AcademicSession).
- Loads run as an integration user with `KEM_Administrator`; triggers stay active so derived data (shares, sessions, balances) is created consistently. Use `Trigger_Control__mdt` only for documented bulk corrections.

## Load order

| Step | Object                                        | Upsert key                                 | Depends on           |
| ---- | --------------------------------------------- | ------------------------------------------ | -------------------- |
| 1    | Branch__c                                     | Branch_Code__c                             | —                    |
| 2    | Room__c                                       | External_Id__c                             | Branch               |
| 3    | AcademicYear / AcademicTerm / AcademicSession | External_ID__c                             | —                    |
| 4    | Learning, LearningProgram, LearningCourse     | External_ID__c                             | —                    |
| 5    | Fee_Price__c, Discount__c                     | External_Id__c                             | Course, Branch       |
| 6    | Person Accounts (learners, guardians)         | Account.External_Id__c                     | —                    |
| 7    | ContactContactRelation (guardians)            | — (dedupe on pair)                         | Person Accounts      |
| 8    | CourseOffering, CourseOfferingSchedule        | External_ID__c                             | Course, Branch, Room |
| 9    | CourseOfferingParticipant                     | External_ID__c                             | Offering, Learner    |
| 10   | Student_Invoice__c, Invoice_Line__c           | External_Id__c                             | Learner, Enrolment   |
| 11   | Student_Payment__c, Payment_Allocation__c     | Gateway_Transaction_Id__c / External_Id__c | Invoice              |

Templates for each step are in `data/templates/` (CSV headers only).

## Validation checklist after each load

1. Record counts match the source extract.
2. `Error_Log__c` has no new ERROR entries.
3. Invoice balances equal source balances (opening balance invoices).
4. Spot-check five learners end to end in Learner 360.
