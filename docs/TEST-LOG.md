# Test & Deployment Log

All deployments target production org `00DdN000013eLgHUAU` with `RunSpecifiedTests` (all project `*Test` classes).

| Date       | Scope                                                 | Deploy ID          | Tests | Coverage | Result | Notes                                                                       |
| ---------- | ----------------------------------------------------- | ------------------ | ----- | -------- | ------ | --------------------------------------------------------------------------- |
| 2026-10-02 | Phase 0 metadata (objects, permission sets, settings) | —                  | n/a   | n/a      | ✅     | Deployed before Apex so the admin user receives FLS via `KEM_Administrator` |
| 2026-10-02 | Phase 0 Apex framework                                | 0AfdN00000JV0btSAD | 15/16 | —        | ❌     | Admin lacked FLS on new fields → assigned `KEM_Administrator`               |
| 2026-10-02 | Phase 0 framework, app, sharing, security tests       | 0AfdN00000JV11hSAD | 21/21 | 95%      | ✅     |                                                                             |
| 2026-10-03 | F1.1–F1.7 (one deploy per feature)                    | see feature guides | all   | ≥ 95%    | ✅     | Per-feature tests and E2E results are recorded in `docs/features/`          |
| 2026-10-03 | F1.8 assessments backend                              | 0AfdN00000JVA4zSAH | 77/77 | 95%      | ✅     | After fixing CMDT bind (`tmpVar1`) and Decimal map-key scale in the test    |
| 2026-10-03 | F1.8 gradebook UI, class assessments, Learner 360 tab | 0AfdN00000JV9DpSAL | 77/77 | 95%      | ✅     | Jest 28/28                                                                  |

## End-to-end checks

| Date       | Feature | Check                                                                                                                                                                                                                    | Result |
| ---------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------ |
| 2026-10-02 | Logger  | Anonymous Apex `Logger.error` → `Error_Log__c` created by platform event trigger as Automated Process user; record removed afterwards                                                                                    | ✅     |
| 2026-10-03 | F1.8    | Demo class: assessment out of 50 → Ananya 47 (94%, **A+**), Arjun 33 (66%, **C**); score 60 rejected; published (average 80%); re-save refused ("Published results are locked."); Learner 360 lists the published result | ✅     |
