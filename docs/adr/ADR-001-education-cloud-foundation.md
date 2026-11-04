# ADR-001 — Use Education Cloud as the data foundation

- **Status:** Accepted (2026-10-02)
- **Context:** The roadmap offers two routes: a custom application or Education Cloud with extensions. The target org already has Education Cloud licences and a populated Education Cloud data model.
- **Decision:** Reuse Education Cloud objects for people, applications, curriculum, classes, timetable patterns, and class enrolment. Build custom objects only where the native object is missing, not creatable, or semantically different (sessions, attendance, assessments, billing ledger, branches, rooms).
- **Consequences:** Lower duplication and alignment with Salesforce releases; custom fields on Education Cloud objects must be deployed with field-level security in permission sets; Education Cloud permission set licences must be assigned to staff users who work with these objects.
