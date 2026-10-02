# Test & Deployment Log

All deployments target production org `00DdN000013eLgHUAU` with `RunSpecifiedTests` (all project `*Test` classes).

| Date       | Scope                                                 | Deploy ID          | Tests | Coverage | Result | Notes                                                                       |
| ---------- | ----------------------------------------------------- | ------------------ | ----- | -------- | ------ | --------------------------------------------------------------------------- |
| 2026-10-02 | Phase 0 metadata (objects, permission sets, settings) | —                  | n/a   | n/a      | ✅     | Deployed before Apex so the admin user receives FLS via `KEM_Administrator` |
| 2026-10-02 | Phase 0 Apex framework                                | 0AfdN00000JV0btSAD | 15/16 | —        | ❌     | Admin lacked FLS on new fields → assigned `KEM_Administrator`               |
| 2026-10-02 | Phase 0 framework, app, sharing, security tests       | 0AfdN00000JV11hSAD | 21/21 | 95%      | ✅     |                                                                             |

## End-to-end checks

| Date       | Feature | Check                                                                                                                                 | Result |
| ---------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| 2026-10-02 | Logger  | Anonymous Apex `Logger.error` → `Error_Log__c` created by platform event trigger as Automated Process user; record removed afterwards | ✅     |
