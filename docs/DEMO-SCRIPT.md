# Demo & Test Script — Full Learner Journey (Phase 1)

Use this to demonstrate or acceptance-test the complete Kasetti Education Management flow in the org: **enquiry → application → offer → enrolment → timetable → attendance → assessment → invoice → payment → reconciliation → documents → dashboards → portal**.

- **Part A** — what is built (one-page recap).
- **Part B** — automated run (about 3 minutes, 23 checks).
- **Part C** — click-by-click demo in the app (about 30–40 minutes), with the expected result after every step.
- **Part D** — negative tests (the guard rails).
- **Part E** — portal, reporting and clean-up notes.

---

## Part A — What is built

| Area                 | What you can show                                                                                                                                                                      | Where                                                                 |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Enquiries            | Website/API capture, duplicate flag, auto-assignment to a branch counsellor, follow-ups, lost reasons, conversion to learner + guardian + application                                  | **Admissions** tab, Lead page, `POST /kem/v1/enquiries`               |
| Learners & guardians | Person accounts, guardian links (fee payer, emergency contact, portal access), siblings, preferences, **Learner 360**                                                                  | Account page                                                          |
| Applications         | Document checklist, age eligibility (with override), review, decision (Admit/Waitlist/Reject), offer with expiry, acceptance                                                           | **Admissions Review** tab, Application page                           |
| Pricing              | Course fee prices by branch/mode/date, discount codes with approval                                                                                                                    | Course page, Fee Prices, Discounts                                    |
| Enrolment            | Seat control (class goes Full), agreed price snapshot, discount approval, withdrawal                                                                                                   | Class page roster, Learner 360                                        |
| Scheduling           | Weekly patterns, session generation (skips closures), teacher/room clash prevention, drag-and-drop timetable                                                                           | Class page, **Timetable** tab                                         |
| Attendance           | Register with P/L/A/E, late minutes, corrections audit, attendance rate, low-attendance alerts                                                                                         | Session page                                                          |
| Assessments          | Gradebook with live grades, draft/publish, locked results, Learner 360 Results                                                                                                         | Class page → Assessments, Assessment page                             |
| Billing              | Invoice to the fee-paying guardian, branch numbering and due dates, payments (pending/confirmed/failed), oldest-due-first allocation, receipts, reconciliation exceptions, gateway API | Class roster, Invoice page, **Finance Desk**, `POST /kem/v1/payments` |
| Documents            | Offer letter, invoice and receipt PDFs filed on the record automatically                                                                                                               | Documents panel on application/invoice/payment                        |
| Reporting            | Role-aware Home cockpit, 6 reports, **KEM Operations** dashboard                                                                                                                       | Home, Reports → KEM Reports, Dashboards                               |
| Portal               | Learner/guardian home (timetable, results, attendance, fees) with strict access                                                                                                        | Component ready; place on the site (see Part E)                       |
| Security             | 6 personas (permission set groups), branch sharing, system-managed fields, governed status transitions                                                                                 | Setup → Permission Set Groups                                         |

**Quality:** 101 Apex tests (94% coverage), 40 Jest tests, and `FullJourneyTest` covering the whole journey; every feature was also checked live (see [TEST-LOG.md](TEST-LOG.md)).

---

## Part B — Automated run

From the repository (with the org connected — `./scripts/ci/sf-login.sh`):

```bash
scripts/demo/full-journey.sh            # or give a tag: scripts/demo/full-journey.sh R7
```

Each run creates its own learner, guardian and class (all prefixed `[KEM Demo]`), so runs never collide. Expected ending:

```
23 passed, 0 failed — learner "Demo Learner R7 [KEM Demo]", application IA-…, invoice BLR-…, receipt RCT-…
```

| Step | What happens                                                                | Check                                                                                                                                                         |
| ---- | --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0    | New class "[KEM Demo] Journey ‹tag›" (capacity 10, Mondays 16:00)           | —                                                                                                                                                             |
| 1    | Website enquiry with mother's details                                       | Status New                                                                                                                                                    |
| 2    | Conversion                                                                  | Learner, guardian, application created; enquiry converted                                                                                                     |
| 3–5  | Checklist accepted/waived → review → ready → **Admit** → offer **accepted** | Offered, then Accepted                                                                                                                                        |
| 6    | Enrolment from the application                                              | Enrolled at the agreed price; application Enrolled                                                                                                            |
| 7–8  | Timetable generated; a session happening now; attendance marked             | Rate 100%                                                                                                                                                     |
| 9    | Quiz 17/20 published                                                        | Grade **A**                                                                                                                                                   |
| 10   | Invoice to the guardian                                                     | Issued; equals the agreed price                                                                                                                               |
| 11   | Gateway calls over HTTPS: pending → success → retry                         | 201 Pending, 201 Confirmed, 200 duplicate                                                                                                                     |
| 12   | Final state                                                                 | Invoice Paid, 0 due, enrolment Paid, payment Reconciled, offer letter/invoice/receipt PDFs filed, guardian's portal shows the learner, result and nothing due |

Last verified: 2026-10-03 (run D2 — IA-0000000034, BLR-000004, RCT-000004).

---

## Part C — Click-by-click demo in the app

**Before you start**

- Log in as **Kasetti Tech** (administrator) → App Launcher → **Kasetti Education**.
- Optional persona view: Setup → Users → _Login_ next to a staff user (needs _Administrators Can Log in as Any User_ in Login Access Policies). Personas: Adam Admissions (counsellor), Anjali Advisor (academic coordinator), Rahul Registrar (branch manager), Andrea Advancement (finance).
- Demo data: branch **[KEM Demo] Bengaluru Central** (code `DEMO-01`), course **[KEM Demo] Mathematics Foundation** (Admission 2,000 + Term tuition 10,500 + Workbooks 1,500, 18% tax → **16,520**), discount code **SIBLING10**.
- Use the class **[KEM Demo] Journey D2** (capacity 10, Mondays 16:00) — the original Saturday class is intentionally Full (3/3).

### 1. Home cockpit (2 min)

1. Click **Home**.
   - ✅ Greeting with today's date; buttons **Timetable** and **Operations dashboard**.
   - ✅ Gauges: seats filled and attendance (last 30 days); receivables card (outstanding, overdue, collected this month); admissions tiles (open enquiries, applications in review, offers awaiting reply).

### 2. Capture the enquiry (3 min)

1. Open the **Admissions** tab → **New enquiry** (blue button in the toolbar).
   - Do **not** use _Leads → New_: that is Salesforce's standard B2B lead form (it asks for _Company_ and does not show the education fields).
2. Fill the three sections and click **Save enquiry**:
   - **Learner:** First name _Meera_, Last name _Rao [KEM Demo]_, Learner Birthdate = 11 years ago, Mobile, Email.
   - **Parent or guardian:** First/Last name, Relationship = Father, Phone, Email.
   - **Interest:** Branch = [KEM Demo] Bengaluru Central, Interested Course = [KEM Demo] Mathematics Foundation, Enquiry Channel = Walk-in (default), optional Next Follow-up / Trial Session Date / Description.
   - ✅ Toast _Enquiry created_; Meera appears in the **New** column, assigned to a counsellor of the branch. Filters **Branch**, **My enquiries**, search; counters _Due today_ / _Overdue_ / _Possible duplicates_.
   - ✅ Leaving out every email and phone number is refused: “Enter at least one email address or phone number for the learner or guardian.”
3. Open the enquiry → **Log follow-up** (Outcome, Notes, **Next follow-up** tomorrow) → **Save follow-up**.
   - ✅ Stage moves on; the follow-up task is created.

### 3. Convert to learner + guardian + application (2 min)

1. On the enquiry click **Convert**.
   - ✅ The dialog shows _New learner record_ and the guardian, and warns if an existing record matches (_Possible duplicate_ / _Existing record found_).
2. Keep **Create admissions application** on → **Convert**.
   - ✅ You land on the learner; the enquiry is read-only and linked to the learner and application.
3. On the learner (**Learner 360**): check **Guardians** (father as _Fee payer_, _Emergency contact_, _Portal access_), tabs **Overview · Applications · Classes · Results · Fees · Preferences**.

### 4. Application → decision → offer (5 min)

1. Open the application (Learner 360 → Applications, or the **Admissions Review** tab).
2. **Checklist**: click ✓ _Accept_ on required items (Birth Certificate, Address Proof, Photo Identity Proof) and _Waive_ the optional ones.
   - ✅ _Eligibility_ shows **Eligible** (age rule).
3. **Submit for review** → **Ready for decision** → **Decide** → Decision **Admit**, _Offer valid for (days)_ 14 → **Record decision**.
   - ✅ Offer status **Offered** with an expiry date; an **Offer Letter** PDF appears in **Documents** within a minute (refresh) — open it.
4. **Record acceptance**.
   - ✅ Offer **Accepted**; **Enrol in class** appears.

### 5. Enrolment with the agreed price (3 min)

1. Click **Enrol in class** → choose **[KEM Demo] Journey D2** → **Next**.
   - ✅ Price breakdown: 14,000 + 2,520 tax = **16,520**. (Optional: type **SIBLING10** to see the discount line.)
2. **Confirm enrolment**.
   - ✅ Application **Enrolled**; Learner 360 → Classes lists the class; the class roster shows Meera with the agreed total and billing **Not Invoiced**.

### 6. Timetable (3 min)

1. Open the class → scheduling menu (calendar icon) → **Open timetable**.
   - ✅ Week view with the Monday sessions; filters for branch, room, teacher, **My sessions**; **Today**.
2. Drag a session to another slot.
   - ✅ Rescheduled (clashes for the same teacher or room are refused with a message).
3. Click a session → drawer → **Attendance** (use a session that starts within the next hour; otherwise create one: Class page → menu → **Add weekly pattern**/**Generate sessions**, or add a make-up session on Class Sessions → New with Start = now).

### 7. Attendance (2 min)

1. In the register: **Mark all present**, set one learner to **Late** with minutes, add a note → **Save register**.
   - ✅ Counters update live; session becomes **Completed**; each learner's attendance rate updates. Re-save after a change → audited as a correction.

### 8. Assessment and results (3 min)

1. Class page → **Assessments** → **New**: Name _Unit Quiz_, Type Quiz, Maximum Score 20 → Save.
2. On the assessment (gradebook): enter Meera **17**.
   - ✅ Live percentage bar and provisional grade **A** (bands: A+ ≥ 90, A ≥ 80, B ≥ 70, C ≥ 60, D ≥ 50, F).
3. **Save draft**, then **Publish results** → confirm.
   - ✅ Status **Published**, class average shown; inputs locked. Learner 360 → **Results** shows _Unit Quiz 17 / 20 (85%) A_.

### 9. Invoice (2 min)

1. Class page → roster row for Meera → ▾ → **Create invoice**.
   - ✅ Opens invoice **BLR-…**: Bill to the **father**, learner Meera, issue date today, due in 15 days (branch policy), charges table, total **16,520**, balance 16,520. Enrolment billing → **Invoiced**. An **Invoice PDF** is filed under Documents.

### 10. Payment and reconciliation (5 min)

1. **Record payment**: Amount 6,000, Method **UPI**, Reference _UTR-DEMO-1_, **Funds received** on → **Record payment**.
   - ✅ Toast with receipt **RCT-…**; invoice **Partially Paid**, progress bar 36%; payment listed with its receipt; receipt PDF filed on the payment.
2. **Record payment** again: 10,520, Method **Cheque**, Reference _CHQ-001_ — note **Funds received** switches off → save.
   - ✅ Listed under **Awaiting confirmation**; balance still 10,520.
3. Open **Finance Desk** → **Awaiting confirmation** → **Confirm** the cheque.
   - ✅ Invoice **Paid**, balance 0; enrolment billing **Paid**; payment **Reconciled**.
4. Overpayment exception: create an invoice for another learner (or use any open one) and record a payment larger than its balance.
   - ✅ Toast warns that the extra could not be allocated; **Finance Desk → Reconciliation exceptions** lists it → **Close** with a note (e.g. _Refunded by bank transfer_) → reconciled.

### 11. Documents (1 min)

1. On the application, invoice and payment: **Documents** panel → **Open …**.
   - ✅ Branded PDFs: Offer of Admission, Invoice, Payment Receipt. Samples: [docs/features/samples](features/samples/).

### 12. Reports and dashboard (3 min)

1. **Dashboards → KEM Dashboards → KEM Operations**.
   - ✅ Outstanding, Collected, Seats taken; funnel, applications, seats by status, attendance marks, balance by invoice status, collections by method — runs as the viewer.
2. **Reports → KEM Reports**: Admissions Funnel, Applications by Status, Class Occupancy, Attendance by Status, Receivables, Collections by Method.

---

## Part D — Negative tests (guard rails)

| #   | Try                                                                    | Expected                                                                                           |
| --- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| 1   | Create an enquiry with the same email/phone as an existing person      | Flagged **Possible duplicate** on the Admissions board                                             |
| 2   | Enrol a new learner into **[KEM Demo] Maths Foundation – Saturday AM** | Refused: class is **Full**                                                                         |
| 3   | Enrol with a discount that needs approval, then try **Create invoice** | Not offered / refused until finance decides (roster ▾ **Approve discount** or **Reject discount**) |
| 4   | Click **Ready for decision** before the checklist is complete          | “All required checklist items must be accepted or waived first.”                                   |
| 5   | Record acceptance after the offer expiry date                          | Refused: the offer expired                                                                         |
| 6   | Open the register for a session starting tomorrow                      | “Attendance can be taken from one hour before the session starts.”                                 |
| 7   | Enter 25 on a quiz out of 20                                           | “Score cannot exceed the maximum”                                                                  |
| 8   | Edit results after publishing                                          | Read-only — “Results are published and locked.”                                                    |
| 9   | Record a payment on a **Draft** invoice                                | “Payments can only be taken against issued invoices.”                                              |
| 10  | Cancel an invoice that has a payment                                   | “Payments are allocated to this invoice; it cannot be cancelled.”                                  |
| 11  | Delete an issued invoice or a confirmed payment                        | Blocked — cancel instead / confirmed payments are kept                                             |
| 12  | Send the same gateway `transactionId` twice                            | Second call returns HTTP 200 `duplicate: true`; one payment only                                   |
| 13  | Log in as Anjali Advisor (academic coordinator)                        | No Finance Desk; Home has no receivables card                                                      |
| 14  | Guardian requests another family's learner in the portal               | “You do not have access to this learner.”                                                          |

---

## Part E — Portal, reporting data and clean-up

**Portal.** Portal users exist for guardians Rohit Sharma, Priya Sharma and Lakshmi Iyer (`*.kemdemo@kasetti-portal.demo`; reset their passwords to log in). To show the portal, place **KEM Learner & Guardian Home** on a `TrialOrgPortal` page in Experience Builder and publish ([NEXT-STEPS.md](NEXT-STEPS.md)). Expected for **Rohit**: two children (Ananya, Arjun) with timetable, attendance, results (A+ and C) and fees; **Priya** sees only Ananya.

**Gateway API** (Postman or curl with an OAuth token):

```http
POST /services/apexrest/kem/v1/payments
{ "transactionId": "txn-123", "invoiceNumber": "BLR-000005", "amount": 16520, "status": "success", "method": "Online Gateway" }
```

`201` created/confirmed · `200` duplicate · `400` invalid (unknown invoice, missing fields).

**Clean-up.** All demo records carry `[KEM Demo]` in their name. Paid invoices and confirmed payments cannot be deleted by design; to retire a demo, leave the records or deactivate the demo portal users.
