# 06 — Development Standards

## Apex

- One trigger per object, one line: `new XyzTriggerHandler().run();`. Logic lives in `TriggerHandler` subclasses.
- Layering: Controller → Service → Selector/Domain (see architecture doc). Controllers are thin and `with sharing`.
- Queries use `WITH USER_MODE`; DML uses `AccessLevel.USER_MODE` unless the operation is a documented system action.
- **Updates send only the fields being changed.** User-mode DML rejects records that carry non-editable fields (for example a non-reparentable master-detail).
- No SOQL/DML in loops; all code is bulk-safe for 200+ records.
- Business errors throw `AppException` with user-safe messages; unexpected errors are logged with `Logger.error` and masked through `AppException.toAura`.
- No hard-coded IDs, record type IDs, or user names; use custom metadata, `Schema` describes, and developer names.

## Tests

- Every class ≥ 85% coverage (deployment minimum is 75%). Tests assert behaviour with messages.
- Test data comes from `TestDataFactory`; no `SeeAllData=true`.
- Security scenarios run as persona users with only their permission set (`System.runAs`).

## LWC

- SLDS-based, responsive (mobile first), accessible (labels, `aria-*`, keyboard reachable).
- Apex calls through `@AuraEnabled(cacheable=true)` for reads; imperative calls for writes followed by `refreshApex`/`notifyRecordUpdateAvailable`.
- Errors surfaced through toast with the server message from `AppException.toAura`.

## Metadata

- Object, field, and permission set XML is generated from `scripts/tooling/specs.py` with `python3 scripts/tooling/mdgen.py`. Edit the spec, regenerate, and commit both.

## Deployment

- `scripts/deploy.sh` deploys `force-app` and runs every `*Test` class (`RunSpecifiedTests`), printing a compact summary.
- `CHECK_ONLY=1 scripts/deploy.sh` validates without saving.
- Authentication: `scripts/ci/sf-login.sh` (client credentials flow).
- Every deployment is recorded in [TEST-LOG.md](TEST-LOG.md).
