# 01 — Solution Architecture

## 1. Foundation decision

**Route chosen: Education Cloud with custom extensions** (see [ADR-001](adr/ADR-001-education-cloud-foundation.md)).

The org already holds Education Cloud licences (Education Cloud – Full Access, Experience Cloud user licences, Customer Community Plus) and the Education Cloud data model is installed and populated (36 Learning, 30 Learning Course, 3 Learning Program, 13 Course Offering, 6 Academic Term records at the time of analysis). Building a parallel custom curriculum and enrolment model would duplicate licensed capability and fight future Salesforce releases.

Where a native object is not creatable, not licensed for the use case, or semantically different, a custom object is built instead.

## 2. Org analysis (2026-10-02)

| Area                  | Finding                                                                                          | Impact                                                   |
| --------------------- | ------------------------------------------------------------------------------------------------ | -------------------------------------------------------- |
| Edition               | Enterprise Edition, production, API 67.0                                                         | All deployments run Apex tests; no destructive changes   |
| Person Accounts       | Enabled (`PersonAccount`, `Household` record types)                                              | Learners and guardians are Person Accounts               |
| Guardian model        | `PartyRoleRelation` "Guardian ↔ Child" exists for `ContactContactRelation`                       | Guardian links use native `ContactContactRelation`       |
| Lead                  | Status values New/Contacted/Nurturing/Qualified/Unqualified; `Qualified` is the converted status | Enquiries are Leads                                      |
| Applications          | `IndividualApplication` with `Admissions` record type                                            | Applications are native                                  |
| Curriculum            | `Learning`, `LearningProgram`, `LearningCourse`, `LearningProgramPlan`                           | Catalogue is native                                      |
| Classes               | `CourseOffering`, `CourseOfferingSchedule`, `CourseOfferingParticipant`                          | Classes, timetable patterns, class enrolments are native |
| Calendar              | `AcademicYear`, `AcademicTerm`, `AcademicSession`                                                | Academic calendar is native                              |
| Invoice / InvoiceLine | **Not creatable** (Revenue Cloud Billing engine only)                                            | Custom billing ledger                                    |
| Payment               | Commerce Payments object, gateway-bound, requires `ProcessingMode`/`Type`                        | Custom payment ledger                                    |
| Attendance            | No attendance objects in this org                                                                | Custom `Session_Attendance__c`                           |
| `Assessment`          | Industries questionnaire object, not grading                                                     | Custom assessment objects                                |
| Documents             | `DocumentChecklistItem`, `ReceivedDocument` available                                            | Native application checklist                             |
| Experience Cloud      | Live site `TrialOrgPortal`; 10 Customer Community Plus licences                                  | Portal components target this site                       |
| Existing custom code  | Experience Cloud boilerplate only; OmniStudio managed package                                    | No collisions                                            |

## 3. Native vs custom mapping (Phase 0–1)

| Business entity       | Implementation                                                    | Type               |
| --------------------- | ----------------------------------------------------------------- | ------------------ |
| Institution           | Org + `Education_Setting__mdt`                                    | Native + config    |
| Branch / centre       | `Branch__c`                                                       | Custom             |
| Room                  | `Room__c` (master-detail to Branch)                               | Custom             |
| Enquiry               | `Lead` + custom fields                                            | Native + extension |
| Learner, guardian     | Person Account + `LearnerProfile`                                 | Native             |
| Guardian relationship | `ContactContactRelation` (Guardian ↔ Child) + custom flags        | Native + extension |
| Application           | `IndividualApplication` + custom fields                           | Native + extension |
| Application checklist | `DocumentChecklistItem`                                           | Native             |
| Programme / course    | `LearningProgram`, `LearningCourse`                               | Native             |
| Class (offering)      | `CourseOffering` + custom fields                                  | Native + extension |
| Timetable pattern     | `CourseOfferingSchedule`                                          | Native             |
| Session               | `Class_Session__c`                                                | Custom             |
| Class enrolment       | `CourseOfferingParticipant` + agreed price fields                 | Native + extension |
| Price                 | `Fee_Price__c`                                                    | Custom             |
| Discount              | `Discount__c`                                                     | Custom             |
| Attendance            | `Session_Attendance__c`                                           | Custom             |
| Assessment, result    | `Course_Assessment__c`, `Assessment_Result__c`, `Grade_Band__mdt` | Custom             |
| Invoice, line         | `Student_Invoice__c`, `Invoice_Line__c`                           | Custom             |
| Payment, allocation   | `Student_Payment__c`, `Payment_Allocation__c` (junction)          | Custom             |
| Generated documents   | Salesforce Files (`ContentVersion`) linked to the source record   | Native             |
| Logs                  | `Log_Event__e` → `Error_Log__c`                                   | Custom             |

## 4. Application layering

```
LWC (UI)  ──►  Controller (@AuraEnabled, thin, with sharing)
                    │
                    ▼
               Service (business rules, transactions, with sharing / inherited sharing)
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
   Selector (SOQL,       Domain trigger handler
   WITH USER_MODE)       (TriggerHandler subclass, one trigger per object)
```

- **Controllers** validate input, call one service method, and convert exceptions with `AppException.toAura`.
- **Services** own transactions (savepoints), enforce business rules, and perform DML in user mode unless a documented system operation requires otherwise.
- **Trigger handlers** contain record-level rules; triggers contain one line.
- **Logger** publishes `Log_Event__e` (publish-immediately) so errors are persisted even when the transaction rolls back.
- **Configuration** lives in custom metadata (`Education_Setting__mdt`, `Status_Transition__mdt`, `Trigger_Control__mdt`, `Grade_Band__mdt`) and branch-level policy fields.

## 5. Out of scope for Phases 0–1

Waitlist automation, transfers, recurring billing, instalment plans, refund automation, gateway integration, messaging channels, LMS/ERP integration, multi-branch templates, AI. These are Phase 2+ per the roadmap.
