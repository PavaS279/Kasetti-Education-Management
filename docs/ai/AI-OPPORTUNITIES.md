# AI opportunities across Kasetti Education Management

_Analysis 2026-10-06 for Phase 4 ("Evaluated assistants, extraction support, forecasting, additional institution-specific capabilities — measured benefit with controlled access and review")._

**Platform:** Salesforce Einstein generative AI through the **Models API** and the **Einstein Trust Layer** (data masking, zero data retention by the model provider, toxicity scoring, audit), plus **Agentforce** for a conversational staff assistant. Verified in this org on 2026-10-06: GPT-4o (default, ~0.6 s), GPT-4o mini, Claude 3.7 Sonnet and Gemini 2.0 Flash all answer; Agentforce (Default) and the Education Cloud agents exist. No document OCR licence is present.

**Principles applied to every AI feature**

1. **Human in the loop:** AI drafts, staff decide. Nothing is sent to a family, saved to a learner record or posted to the ledger without a person accepting it.
2. **Controlled access:** a custom permission (KEM Use AI) and a per-feature switch; a global kill switch (`AI_Enabled`).
3. **Grounded:** prompts are built from the record's own data and the institution's own settings; answers to policy questions cite their sources; no invented fees, dates or names.
4. **Measured:** every call is logged (feature, record, model, latency, outcome); staff mark drafts Accepted / Edited / Rejected; acceptance, edit and rejection rates and estimated minutes saved are shown on the AI console; offline evaluation cases are re-run on every prompt change.
5. **Minimal data:** only the fields a prompt needs; first names rather than full identities where possible; the Trust Layer masks personal data before it reaches the model.

## Feature-by-feature review

| Area (phase)              | AI opportunity                                                                                                                    | Value                                                                      | Risk / control                                                                  | Decision                                    |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------- |
| Enquiries (F1.1)          | **Draft the reply** to a new enquiry from course, branch, prices, next class                                                      | Faster first response; enquiries convert better when answered the same day | Wrong fee or date → grounded on live prices and classes; counsellor edits       | **Build (F4.2)**                            |
| Enquiries (F1.1)          | **Summarise** the enquiry history before a follow-up call                                                                         | Context in seconds                                                         | Low                                                                             | **Build (F4.4)**                            |
| Applications (F1.3)       | **Extract** fields from uploaded documents (birth date, previous school, marks)                                                   | Less typing, fewer errors                                                  | Misread values → proposals only, staff confirm each field                       | **Build (F4.7)**                            |
| Applications (F1.3)       | Summarise the application for the decision                                                                                        | Faster review                                                              | Low                                                                             | **Build (F4.4)**                            |
| Learners (F1.2, F2.7)     | **Progress summary** for parents and **report-card comment** drafts                                                               | Saves teacher time at reporting time                                       | Tone, accuracy → based on grades, attendance, notes; teacher edits              | **Build (F4.3)**                            |
| Classes (F1.6–F1.8)       | Class summary (attendance trend, results, learners needing help)                                                                  | Coordinator overview                                                       | Low                                                                             | **Build (F4.4)**                            |
| Finance (F1.9, F2.3–F2.4) | Finance brief (overdue, exceptions, refunds waiting)                                                                              | Daily focus                                                                | No automated money movement                                                     | **Build (F4.4)**                            |
| Finance (F1.9)            | Payment-to-invoice matching suggestions for bank transfers                                                                        | Fewer reconciliation exceptions                                            | Wrong allocation → would need careful review                                    | Later (deterministic rules first)           |
| Policies (all)            | **Staff Q&A** on fees, refunds, attendance, waitlists, library                                                                    | Consistent answers, less escalation                                        | Hallucination → answers only from the knowledge base and settings, with sources | **Build (F4.5)**                            |
| Operations (F2.9)         | Branch daily brief (cover needs, queues, at-risk learners)                                                                        | Managers start the day informed                                            | Low                                                                             | **Build (F4.4)**                            |
| Retention (F3.6)          | Explain risk and suggest a conversation plan                                                                                      | Better follow-ups                                                          | Sensitive → staff only                                                          | **Build (in F4.3 summary)**                 |
| Analytics (F3.5)          | **Forecast** enrolments, seats, invoicing and collections, with a plain-language narrative                                        | Plan classes and cash                                                      | Over-trust → backtest accuracy shown next to every forecast                     | **Build (F4.8)**                            |
| Messaging (F2.5)          | Rewrite staff messages in a friendlier tone / other languages                                                                     | Family communication                                                       | Language accuracy                                                               | Later                                       |
| Cover (F2.6)              | Explain cover suggestions                                                                                                         | Small                                                                      | —                                                                               | Not now                                     |
| Portal (F2.8)             | Family-facing chatbot                                                                                                             | Self-service                                                               | Public-facing AI needs stronger guardrails and Experience Cloud agent licences  | Later (after staff assistant proves itself) |
| All staff screens         | **Agentforce staff assistant** with actions: policy answers, learner summary, enquiry draft, at-risk list, branch KPIs, forecasts | One conversational entry point                                             | Same permissions as the screens; actions call the same services                 | **Build (F4.6)**                            |

## Institution-specific capabilities (chosen)

| Module                         | Scope                                                                                                                                                 |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Transport (F4.9)               | Routes, stops, learner assignments with pickup/drop, capacity, monthly transport fee billed with tuition                                              |
| Exams and hall tickets (F4.10) | Exams with papers (class, date, time, room, marks), candidates with seat numbers, hall ticket PDFs, marks entered once and published to the gradebook |
| Alumni and referrals (F4.11)   | Learners become alumni on completion; referral codes for families and alumni; referred enquiries tracked to enrolment, optional reward as credit      |

## How benefit is measured

| Measure                       | Source                                                                            |
| ----------------------------- | --------------------------------------------------------------------------------- |
| Usage per feature and user    | `AI_Interaction__c`                                                               |
| Acceptance / edit / rejection | Review outcome recorded when staff use, change or discard a draft                 |
| Edit size                     | Share of the draft changed before use                                             |
| Minutes saved (estimate)      | Accepted or edited drafts × minutes per task (`AI_Minutes_Saved_*` settings)      |
| Quality                       | Offline evaluation cases (`AI_Eval_Case__mdt`) scored on every run; staff ratings |
| Latency and failures          | Logged per call                                                                   |
| Forecast accuracy             | Backtest error (MAPE) on the last six months                                      |
