# ADR-002 — Custom billing ledger instead of native Invoice/Payment

- **Status:** Accepted (2026-10-02)
- **Context:** `Invoice` and `InvoiceLine` are not creatable through the API in this org (Revenue Cloud Billing engine only). `Payment` is the Commerce Payments object, coupled to payment gateways and processing modes. Student Financials requires Revenue Cloud Advanced and Billing configuration that is not in place.
- **Decision:** Implement a focused ledger: `Student_Invoice__c`, `Invoice_Line__c`, `Student_Payment__c`, and the junction `Payment_Allocation__c`. Prices agreed at enrolment are copied to the enrolment and invoice lines. Payments are idempotent on `Gateway_Transaction_Id__c`.
- **Consequences:** Full control of the MVP financial journey and reconciliation; a later migration to Student Financials or an ERP integration maps one-to-one from these objects.
