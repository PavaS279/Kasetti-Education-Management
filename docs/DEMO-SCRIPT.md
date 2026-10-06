# Demo & Test Script — Phase 1 Learner Journey and Phase 2 Operations

Use this to demonstrate or acceptance-test the complete Kasetti Education Management flow in the org: **enquiry → application → offer → enrolment → timetable → attendance → assessment → invoice → payment → reconciliation → documents → dashboards → portal**.

- **Part A** — what is built (one-page recap).
- **Part B** — automated run (about 3 minutes, 23 checks).
- **Part C** — click-by-click demo in the app (about 30–40 minutes), with the expected result after every step.
- **Part D** — negative tests (the guard rails).
- **Part E** — portal, reporting and clean-up notes.
- **Part F** — Phase 2 (operational depth): automated run and click-by-click demo of waitlists, transfers, recurring billing, instalments, credit and refunds, messaging, teacher cover, grading and report cards, the richer portal and the operations console.

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
| Portal               | Learner/guardian home (timetable, results, attendance, fees) with strict access                                                                                                        | Live on `TrialOrgPortal` → **My Learning** (see Part E)               |
| Security             | 6 personas (permission set groups), branch sharing, system-managed fields, governed status transitions                                                                                 | Setup → Permission Set Groups                                         |

**Quality (2026-10-05):** 139 Apex tests (94% coverage), 87 Jest tests, `FullJourneyTest` (Phase 1) and `Phase2JourneyTest` (Phase 2); every feature was also checked live (see [TEST-LOG.md](TEST-LOG.md)). Phase 2 features are listed in Part F.

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

**Portal.** The portal page is live: `TrialOrgPortal` → **My Learning** (`/my-learning`). Portal users exist for guardians Rohit Sharma, Priya Sharma and Lakshmi Iyer (`*.kemdemo@kasetti-portal.demo`); reset a password (Setup → Users → Reset Password) to log in. Expected: **Rohit** sees Ananya and Arjun; **Priya** sees only Ananya; **Lakshmi** sees Kavya — each with timetable, attendance, results and fees (nothing due).

**Gateway API** (Postman or curl with an OAuth token):

```http
POST /services/apexrest/kem/v1/payments
{ "transactionId": "txn-123", "invoiceNumber": "BLR-000005", "amount": 16520, "status": "success", "method": "Online Gateway" }
```

`201` created/confirmed · `200` duplicate · `400` invalid (unknown invoice, missing fields).

**Clean-up.** All demo records carry `[KEM Demo]` in their name. Paid invoices and confirmed payments cannot be deleted by design; to retire a demo, leave the records or deactivate the demo portal users.

---

## Part F — Phase 2: operational depth

### What is built

| Area                     | What you can show                                                                                                                                         | Where                                                                                     |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Waitlists (F2.1)         | Priority queue, a freed seat held 48 h for the next learner, accept → enrolled, expiry passes the seat on                                                 | Class page → **Waitlist** panel                                                           |
| Transfers (F2.2)         | Move an enrolment to another class with a price/billing preview; difference billed or issued as credit                                                    | Class page → roster ▾ → **Transfer to another class**                                     |
| Recurring billing (F2.3) | Monthly fees billed period by period; nightly **KEM Recurring Billing** job; instalment plans settled in order                                            | Invoice page → **Pay in instalments**                                                     |
| Credit & refunds (F2.4)  | Overpayment **held as credit**, credit applied to the next invoice automatically, withdrawal credit, refunds with auto-approval or second-person approval | Finance Desk (exceptions, **Refunds**), Invoice → **Issue credit note**, Credit Note page |
| Messaging (F2.5)         | 8 templated notices (invoice, payment, due soon, overdue, waitlist offer, refund, session cancelled, report card), email consent, staff messages          | Learner page → **Messages** panel; Setup → Custom Metadata → Message Template             |
| Teacher cover (F2.6)     | Report an absence, ranked cover suggestions, assign or cancel (families told), room swaps                                                                 | Home → **Cover Desk**; Session page → **Teacher and room**                                |
| Grading (F2.7)           | Weighted course grades, comments, finalise → report card PDFs and family notices, reopen                                                                  | Class page → **Course grades**                                                            |
| Portal (F2.8)            | Inbox, course grades with report card download, documents, instalments, credit, waitlist position                                                         | Portal → My Learning                                                                      |
| Operations (F2.9)        | Health, exception queues, scheduled jobs with **Run now**, background runs, errors                                                                        | Home → **Operations** (administrators)                                                    |

Email delivery is switched off in this org (Education Setting `Email_Delivery` = Off): emails are logged as **Not Sent**; portal messages are delivered.

### Automated run (about 3 minutes, 31 checks)

```bash
scripts/demo/phase2-journey.sh            # or give a tag: scripts/demo/phase2-journey.sh P7
```

Each run creates its own guardian ("Guardian ‹tag› [KEM Demo] Phase2") with two children and two classes of the monthly Coding Club course, then:

| Step | What happens                                                                 | Checked                                                                                                     |
| ---- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| 0    | Elder child enrolled in one-seat class A                                     | Class A **Full**                                                                                            |
| 1–2  | Younger child joins the waitlist; class A gets a second seat; offer accepted | **Offered**, guardian notified, **Enrolled**, Full again                                                    |
| 3    | Younger child transferred to class B before invoicing                        | "Not invoiced yet", old enrolment **Withdrew**, seat released                                               |
| 4    | Elder's first invoice (4,130) paid with 500 extra → held as credit           | **Exception** → credit **500**                                                                              |
| 5    | Younger's first invoice                                                      | Credit **applied 500**, credit **Used**                                                                     |
| 6    | Next month billed and split into two instalments                             | **2,950**, **2** instalments                                                                                |
| 7    | Withdrawal credit 1,000 on the paid invoice; 600 refunded                    | **Auto-approved**, **Paid**, **400** credit left                                                            |
| 8    | Class teacher absent tomorrow; first free suggestion assigned                | Absence **Covered**, session **Substituted**                                                                |
| 9    | Quiz 18/20 published; grades finalised                                       | **A+**, **Final**                                                                                           |
| 10   | Guardian's portal                                                            | 2 children, notices, A+ Final with report card, invoice/receipt/report card PDFs, 2 instalments, 400 credit |
| 11   | Operations console                                                           | Every job scheduled, health reported                                                                        |

Latest live run: tag `P2A` on 2026-10-05 — **all checks passed** (guardian "Guardian P2A [KEM Demo] Phase2", invoice BLR-000009).

### Click-by-click demo (about 30 minutes)

1. **Waitlist.** Open class _[KEM Demo] Waitlist Demo – Sunday_ → Waitlist panel: queue with positions, held seat and countdown. **Join waitlist** for a learner (priority, sibling discount code). Expected: added at the right position; the class shows Waiting count.
2. **Accept or decline an offer** on an Offered entry. Expected: Accept enrols the learner with the code; Decline passes the seat to the next learner (new offer, new countdown).
3. **Transfer.** Class roster ▾ → **Transfer to another class**. Pick a class: preview shows current vs new price, the difference and what happens to billing. Expected: old enrolment Withdrew "Transferred to …", new enrolment linked; a cheaper class after invoicing creates a credit note.
4. **Recurring billing.** Open invoice BLR-000005 (Coding Club, Ishaan): line "Tuition (Sep 2026)" with period dates, **Instalments** panel (3 instalments, first paid, second part-paid). On a new issued invoice, **Pay in instalments** → choose 3, monthly → preview → **Create plan**. Expected: due date moves to the first unpaid instalment.
5. **Credit and refunds.** Finance Desk → **Reconciliation exceptions** → **Hold as credit** on an overpaid payment. Then open a paid invoice → **Issue credit note** (Withdrawal) → the credit note page: **Request refund** of 800 (auto-approved, under 1,000) → **Mark paid** with a reference. Request 1,200 → "Waiting for an approver other than the requester". Expected: as a second user (branch manager), Finance Desk → **Refunds** → **Approve**. CN-000001 already has RFD-000001 (1,200) waiting.
6. **Messaging.** Learner page (Ananya Sharma) → **Messages**: recipients with consent, the report card and staff notices, statuses (Delivered / Not Sent / Suppressed with reason). **New message** to Rohit by email and portal. Toggle **Opt out** for a guardian and send again: the email is Suppressed.
7. **Teacher cover.** Home → **Cover Desk** → **Report absence** (a teacher, tomorrow, Training). Expected: their sessions appear under Needs cover with ranked teachers (free, has taught the course, load). **Assign** → session shows "covering for …", teacher attendance Substituted, a task for the cover teacher. On a session page, **Change room** lists free rooms large enough first.
8. **Grading.** Class _[KEM Demo] Maths Foundation – Saturday AM_ → **Course grades**: weights 10/20 (33.3% / 66.7%), Ananya 92.67 A+, Arjun 69.00 C, Kavya 85.00 A, status **Final** with report card links. **Reopen** (reason) → Provisional, old report cards superseded; change a weight → **Save weights** → scores recalculate; **Finalise & issue report cards** → new PDFs and family notices.
9. **Portal.** Log in as Rohit Sharma → My Learning: **Messages (n new)**; Ananya → Results starts with the course grade and **Report card** download; **Documents** tab; Fees shows instalments and credit; Timetable shows waitlist position when queued.
10. **Operations.** Home → **Operations** (administrators): health banner, queues (e.g. 1 refund awaiting approval), the five scheduled jobs with next runs and **Run now**, background runs and recent errors.

### Phase 2 negative tests

| #   | Try                                                      | Expected                                                                      |
| --- | -------------------------------------------------------- | ----------------------------------------------------------------------------- |
| 1   | Accept a waitlist offer after it expired                 | "The seat offer expired on …"                                                 |
| 2   | Invoice a monthly enrolment again before the next period | "Nothing is due yet. The next monthly period is billed on …"                  |
| 3   | Credit more than was paid on an invoice                  | "At most … can be credited on …"                                              |
| 4   | Approve a refund you requested                           | "A refund must be decided by someone other than the person who requested it." |
| 5   | Assign a cover teacher who is teaching at that time      | "The teacher is already teaching …"                                           |
| 6   | Move a session to a room smaller than the class          | "The room holds … but … learners are enrolled."                               |
| 7   | Finalise grades while an assessment is still draft       | "Publish or delete the draft assessment …"                                    |
| 8   | Change weights or comments after grades are final        | "Grades are final. Reopen them before making changes."                        |
| 9   | Download another family's report card through the portal | "Document not found or not available to you."                                 |
| 10  | Open the Operations console as a non-administrator       | The card does not appear                                                      |

## Part G — Phase 3: scale and optimisation

### G1. Open a new branch from a template (5 minutes)

1. Open branch **[KEM Demo] Bengaluru Central** → the **Branch comparison** panel shows every branch with seats filled, classes, learners, 30-day attendance, waiting, enquiries, rooms and (administrators, finance) outstanding, overdue and collected fees. The current branch is highlighted; sort by fill rate or attendance.
2. **New branch from this one** → the modal lists what will be copied (rooms, branch prices, branch discounts, upcoming closures, classes and weekly patterns, with counts). Enter a name, code (for example DEMO-03) and invoice prefix; untick parts if needed; choose when classes start.
3. **Open branch** → counts and next steps (assign teachers, generate sessions, open classes). **Open new branch** → the new branch page; its classes are Planned with the copied rooms, each on the same weekday as in the template.
4. Open a copied class → **Generate sessions** → sessions start on or after the chosen date.
5. Negative: repeat with the same code or invoice prefix → "Branch code … is already used by …"; as a branch manager the template buttons do not appear.

### G2. Scale and background jobs (3 minutes)

1. Home → **Operations** → **Run now** on _KEM Payment Reminders_: a `ReminderJob` batch appears under background runs (Completed) with a log entry "Payment reminders for …: n messages", followed by a delivery job.
2. **Run now** on _KEM Recurring Billing_: the batch runs in small batches of 5 enrolments; the log line reports invoices raised, failures and any enrolments left for an automatic follow-up run.
3. Setup → Custom Metadata Types → Education Setting: `Recurring_Billing_Batch_Size` (5) and `Dispatch_Rounds` (20) tune throughput without code changes.

### G3. Automated run (about 4 minutes, 26 checks)

```bash
scripts/demo/phase3-journey.sh P3C     # any new tag
```

Opens "[KEM Demo] Centre ‹tag›" from the demo branch and checks: classes and rooms copied; LMS outbox, API classes, roster, grades (created, then updated), events acknowledged; invoice with the centre's prefix in a balanced journal (Apex and ERP API) and the ERP event; payments refused and webhook 503 while Off; retention scoring and desk; library issue and return; analytics; branch comparison; nine scheduled jobs and administrators in their group. Last run: P3B, 26 of 26.

### G4. Integrations (5 minutes, with any REST client as the integration user)

1. `GET /services/apexrest/kem/v1/lms/classes?branch=DEMO-01` → the demo classes with course code, branch code and teacher email.
2. `GET …/lms/classes/{id}/roster` → learners with emails.
3. `POST …/lms/grades` with an `externalId` → 201 Draft; send again with `"publish": true` → 200 Published; once more → 400 "published; its results are locked".
4. `GET …/lms/events?limit=10` → paged events; `POST …/lms/events/ack` → acknowledged.
5. `GET …/erp/journal?from=2026-10-01&to=2026-10-31&format=csv` → balanced CSV; Finance Desk → **ERP export** → Preview / Export CSV / Download.
6. As a teacher (no KEM Integration permission) any call → 403.

### G5. Analytics and retention (5 minutes)

1. Home → **Analytics**: tiles, invoiced vs collected, enrolment flow, attendance line (hover a month), retention by enrolment month, receivables ageing, courses; switch branch and period; **Show as table**.
2. Home → **Retention**: risk counts; **At risk** with reasons → **Log follow-up** (Contacted needs a note; Retained does not); **Re-enrolment** → select learners whose class ends soon → **Send invitations** (portal message to the fee payer). Administrators: **Recalculate**.

### G6. Online payments (3 minutes; needs Test mode)

1. Set Education Setting `Payment_Gateway_Mode` = `Test` (Setup → Custom Metadata Types).
2. Portal (Rohit) → Fees → **Pay online** on an open invoice → "Test mode: payment request PL-… was created. No money is taken."
3. Staff: invoice page → **Online payment** → the link (Portal, Active) → **Simulate payment** → payment recorded, invoice Paid, receipt and notice as usual.
4. Set the mode back to `Off`.

### G7. Library (3 minutes)

Branch **[KEM Demo] Bengaluru Central** → **Library**: counts; **Catalogue** → search "kalam" → **Issue** the robotics kit to a learner found by name (the last copy cannot be lent twice); **On loan** → **Renew** / **Return** / **Return damaged** / **Lost** (replacement cost); **Fines** → **Paid** / **Waive**. Portal → **Library** tab shows the learner's loans and late fees.

### Phase 3 negative tests

| #   | Try                                                            | Expected                                                                        |
| --- | -------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 1   | Open a branch with an existing code or invoice prefix          | "Branch code … is already used by …"                                            |
| 2   | Post grades for a learner not in the class                     | 400 "Not enrolled in this class: …" and nothing saved                           |
| 3   | Call the LMS or ERP API without the KEM Integration permission | 403                                                                             |
| 4   | Export more than 92 days                                       | "Export at most 92 days at a time."                                             |
| 5   | Pay online while `Payment_Gateway_Mode` is Off                 | "Online payments are not available yet. Please pay at the branch."              |
| 6   | Webhook with a wrong signature                                 | 401 "Invalid signature." (logged)                                               |
| 7   | Issue a library item to a learner with an overdue loan         | "… has an overdue loan. Return it before borrowing again."                      |
| 8   | Renew an overdue loan, or a third time                         | "Overdue items must be returned, not renewed." / "already been renewed 2 times" |
| 9   | Log a "Contacted" follow-up without a note                     | "Add a note about the conversation."                                            |
