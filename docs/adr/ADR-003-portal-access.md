# ADR-003 — Portal data access through explicit relationships

- **Status:** Accepted (2026-10-02)
- **Context:** Guardians may only see records of learners they are explicitly authorised for. Sharing household accounts would leak sibling or ex-partner data.
- **Decision:** Portal Apex resolves the running user's Contact, then the set of learners they may view: themselves, plus learners linked through an active `ContactContactRelation` (Guardian ↔ Child) with `Portal_Access__c = true`. All portal queries are filtered by that set.
- **Consequences:** Access is auditable and revocable per relationship; portal Apex must never accept a learner ID without checking it against the authorised set.
