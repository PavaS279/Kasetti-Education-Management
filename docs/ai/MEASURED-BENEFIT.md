# AI — measured benefit, access and review (Phase 4)

Phase 4 asked for "measured benefit with controlled access and review". This report records how that is measured and the figures from production on **2026-10-06** (the go-live checks, on `[KEM Demo]` data, by one administrator). Re-run it monthly from the **AI console** (Home page → _AI console_, 30 days); NEXT-STEPS has the monthly review.

## How benefit is measured

Every AI request writes an **AI Interaction** (`AI_Interaction__c`): feature, channel (_In-app_, _Agentforce_, _Evaluation_), model, prompt version, record, latency, success or failure, and after staff review the outcome (_Accepted_, _Edited_, _Rejected_), the **edit ratio** (how much of the draft staff changed), an optional 1–5 rating and **minutes saved** = the prompt's minutes per use × (1 − edit ratio). Evaluation runs are kept apart and never count as use.

| Measure              | Where it comes from                                                                                  |
| -------------------- | ---------------------------------------------------------------------------------------------------- |
| Use                  | Requests per feature and channel; staff using AI; Agentforce actions                                 |
| Usefulness           | Share of reviewed drafts used (as is or edited); average edit; rating                                |
| Time saved           | Sum of minutes saved (only for drafts staff used)                                                    |
| Quality before trust | The evaluation set (`AI_Eval_Case__mdt`): expected facts, forbidden content, format, word limits     |
| Reliability          | Failed requests, average response time                                                               |
| Extraction accuracy  | For document extraction, the share of proposed values staff corrected before saving (the edit ratio) |

## Controlled access

| Control           | How                                                                                                                                              |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Who can use AI    | Permission set **KEM AI User** (plus the record access the person already has; summaries only read what the user can see)                        |
| Switches          | `AI_Enabled` and `AI_Disabled_Features` in settings; per-prompt active flag                                                                      |
| Data protection   | Einstein Trust Layer: masking, zero retention at the model provider, audit                                                                       |
| Human in the loop | Nothing is sent, saved or published by AI: replies are drafts, extraction proposes values staff tick, forecasts and summaries are read-only text |
| Agentforce        | The **KEM Staff Assistant** agent uses six Apex actions that run as the user (with sharing) and only read; it cannot send or change records      |
| Review            | The console shows every feature's outcomes; administrators see everyone's use, other AI users their own                                          |

## Evaluation (before use)

| Run                  | Cases | Passed | Average score | Average time | Notes                                                                               |
| -------------------- | ----- | ------ | ------------- | ------------ | ----------------------------------------------------------------------------------- |
| First run            | 10    | 8      | —             | —            | Two cases failed; drafts also showed Markdown formatting                            |
| Run 2026-10-06 11:28 | 10    | 10     | 100           | 2.7 s        | After prompt version 2 for enquiry replies and document extraction                  |
| Run 2026-10-06 13:13 | 11    | 11     | 100           | 4.3 s        | Forecast narrative case added (grounded figures, currency); run by the Phase 4 demo |

## Production figures (30 days to 2026-10-06)

After the go-live checks and the Phase 4 demo run `P4A`: **20 requests**, **3 Agentforce actions**, **0 failed**, average response **4.5 s**, **1 staff user**, model `sfdc_ai__DefaultGPT4Omni`. Of the 5 drafts reviewed, **5 were used** (2 as is, 3 edited, 0 rejected); average edit 19.1%; rating 5/5; **18.6 minutes saved**.

| Feature             | Requests | Reviewed | Used | Average edit | Minutes saved | Average time |
| ------------------- | -------- | -------- | ---- | ------------ | ------------- | ------------ |
| Document extraction | 3        | 2        | 2    | 26.6%        | 8.8           | 2.3 s        |
| Enquiry reply       | 4        | 2        | 2    | 4.1%         | 7.8           | 8.0 s        |
| Record summary      | 2        | 1        | 1    | 0%           | 2.0           | 3.6 s        |
| Policy Q&A          | 4        | —        | —    | —            | —             | 1.4 s        |
| Branch brief        | 2        | —        | —    | —            | —             | 3.3 s        |
| Forecast narrative  | 2        | —        | —    | —            | —             | 8.3 s        |
| Progress summary    | 2        | —        | —    | —            | —             | 6.6 s        |
| Report comment      | 1        | —        | —    | —            | —             | 2.4 s        |

"—" means the output is read-only (no review step) or the draft was left pending. Requests include the Agentforce channel.

## Reading the figures

- These are go-live checks, not a baseline: one user, a handful of requests. The first meaningful review is after a month of staff use (NEXT-STEPS: assign **KEM AI User** to counsellors, coordinators and finance).
- Extraction is where most time is saved and where staff change most (a quarter of proposed values corrected). Two live corrections led to fixes: unticked conflicting values no longer count as edits, and another parent's phone is no longer offered for the linked guardian.
- Enquiry replies and forecast narratives are the slowest features (about 8 s); acceptable for a draft, worth watching.
- **Decision rules for the monthly review:** keep a feature if at least 60% of reviewed drafts are used and the average edit stays under 40%; revise its prompt (new version, re-run the evaluation to 10/10) if not; switch it off in `AI_Disabled_Features` if a revised prompt still falls short or a rejected draft shows a safety issue.
