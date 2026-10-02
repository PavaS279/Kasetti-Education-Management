# 02 — Data Model

Generated metadata for custom objects comes from `scripts/tooling/specs.py` (run `python3 scripts/tooling/mdgen.py`). This document describes intent; the spec file is the source of truth for field lists.

## Entity relationship overview

```mermaid
erDiagram
    Branch__c ||--o{ Room__c : has
    Branch__c ||--o{ Lead : "enquiries"
    Branch__c ||--o{ CourseOffering : "runs classes"
    Lead }o--|| LearningCourse : "interested in"
    Account_Learner ||--o{ ContactContactRelation : "guardians"
    Account_Guardian ||--o{ ContactContactRelation : "children"
    Account_Learner ||--o{ IndividualApplication : applies
    IndividualApplication ||--o{ DocumentChecklistItem : checklist
    LearningProgram ||--o{ LearningCourse : "via plans"
    LearningCourse ||--o{ CourseOffering : "delivered as"
    LearningCourse ||--o{ Fee_Price__c : priced
    CourseOffering ||--o{ CourseOfferingSchedule : "timetable pattern"
    CourseOffering ||--o{ Class_Session__c : sessions
    CourseOffering ||--o{ CourseOfferingParticipant : enrolments
    Class_Session__c ||--o{ Session_Attendance__c : attendance
    CourseOffering ||--o{ Course_Assessment__c : assessments
    Course_Assessment__c ||--o{ Assessment_Result__c : results
    CourseOfferingParticipant ||--o{ Invoice_Line__c : billed
    Student_Invoice__c ||--o{ Invoice_Line__c : lines
    Student_Invoice__c ||--o{ Payment_Allocation__c : settled_by
    Student_Payment__c ||--o{ Payment_Allocation__c : allocated_to
```

## Phase 0 objects (deployed)

| Object                   | Sharing                                                     | Purpose                            | Key fields                                                                                                                                                                                                          |
| ------------------------ | ----------------------------------------------------------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Branch__c`              | Public Read Only + Apex share to `Branch_Manager__c` (Edit) | Centre/campus and policy overrides | `Branch_Code__c` (unique, external ID), `Active__c`, `Branch_Manager__c`, `Invoice_Due_Days__c`, `Attendance_Threshold__c`, `Tax_Rate__c`, `Invoice_Prefix__c`, `Cancellation_Notice_Hours__c`, `Delivery_Modes__c` |
| `Room__c`                | Controlled by parent (Branch)                               | Bookable space                     | `Branch__c` (MD), `Capacity__c`, `Room_Type__c`, `Equipment__c`, `Meeting_Url__c`                                                                                                                                   |
| `Error_Log__c`           | Private (admins view all)                                   | Persistent application log         | `Severity__c`, `Source__c`, `Message__c`, `Stack_Trace__c`, `Record_Id__c`, `Transaction_Id__c`                                                                                                                     |
| `Log_Event__e`           | Platform event (publish immediately)                        | Transport for log entries          | mirrors `Error_Log__c`                                                                                                                                                                                              |
| `Education_Setting__mdt` | Custom metadata                                             | Organisation defaults              | `Value__c`, `Description__c`                                                                                                                                                                                        |
| `Status_Transition__mdt` | Custom metadata                                             | Allowed status transitions         | `Object_Name__c`, `Field_Name__c`, `From_Status__c`, `To_Status__c`, `Active__c`                                                                                                                                    |
| `Trigger_Control__mdt`   | Custom metadata                                             | Per-handler kill switch            | `Disabled__c` (DeveloperName = handler class)                                                                                                                                                                       |

| `Branch_Staff__c` | Controlled by parent (Branch) | User ↔ branch ↔ role | `Branch__c` (MD), `User__c`, `Role__c`, `Active__c`, `Unique_Key__c` (unique) |

## Phase 1 objects

Added feature by feature; see [PROGRESS.md](PROGRESS.md) for what is deployed.

### F1.1 Enquiries (deployed)

| Object                   | New fields                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Lead`                   | `Branch__c`, `Interested_Course__c`, `Interested_Program__c`, `Enquiry_Channel__c`, `Preferred_Delivery_Mode__c`, `Learner_Birthdate__c`, `Guardian_First_Name__c`, `Guardian_Last_Name__c`, `Guardian_Email__c`, `Guardian_Phone__c`, `Guardian_Relationship__c`, `Next_Follow_Up__c`, `Last_Contacted__c`, `Trial_Session_Date__c`, `Lost_Reason__c`, `Possible_Duplicate__c`_, `Duplicate_Details__c`_, `Converted_Learner__c`_, `Converted_Application__c`_, `Submission_Id__c` (unique), `Follow_Up_Status__c` (formula) |
| `Account`                | `Branch__c` (home branch), `KEM_Role__c` (Learner / Guardian / Learner and Guardian)                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `IndividualApplication`  | `Branch__c`, `Learning_Course__c`, `Learning_Program__c`, `Source_Enquiry__c`*                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `ContactContactRelation` | `Is_Fee_Payer__c`, `Is_Emergency_Contact__c`, `Portal_Access__c`, `Guardian_Relationship__c`                                                                                                                                                                                                                                                                                                                                                                                                                                  |

\* system-managed (read-only to users, set by Apex).

Guardian link convention: `ContactId` = guardian's person contact, `RelatedContactId` = learner's person contact, `PartyRoleRelation` = Guardian/Child.

### Design rules applied

1. Application status, enrolment status, payment status, and academic completion are separate fields on separate records.
2. The agreed price is copied to the enrolment and invoice line; later catalogue price changes never alter historical charges.
3. Invoice issuance, payment confirmation, and settlement/reconciliation are separate states.
4. Payment processing is idempotent on `Gateway_Transaction_Id__c` (unique external ID).
5. Published assessment results keep the grade that was calculated at publication time.
6. Every object that may be migrated has a unique `External_Id__c`.
