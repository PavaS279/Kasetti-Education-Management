# KT College — Simple Demo Flow: Enquiry to Class

_One student, start to finish, in the order a real admission happens: online enquiry → lead → documents → admit (Dean only for exceptions) → fee → admission letter → roll number → section → student portal. About 25 minutes. Version 2026-11-03. The full story with refusals and academics is in [COLLEGE-DEMO-SCRIPT.md](COLLEGE-DEMO-SCRIPT.md)._

## Before you start

| Check                                                                                                                                     | Done |
| ----------------------------------------------------------------------------------------------------------------------------------------- | ---- |
| Logged in as **Kasetti Tech**; Setup → Login Access Policies allows logging in as users                                                   | ☐    |
| The Admission Counsellor has **KEM College Admissions**; Anjali has **KEM College Dean** + **KEM Eligibility Override** (done 2026-11-03) | ☐    |
| The Admission Counsellor and Anjali are in **KEM College Admissions Team** (done 2026-11-03)                                              | ☐    |
| A private/incognito browser window for the visitor                                                                                        | ☐    |
| Use a **new student name** every run (for example _Kavya Rao_ + today's date) and an example email address                                | ☐    |

Switch user: Setup → **Users** → **Login** next to the name; **Log out** returns to Kasetti Tech.

| Link              | Address                                                                                   |
| ----------------- | ----------------------------------------------------------------------------------------- |
| Public enquiry    | https://kasettitechnologiespvtltd.my.site.com/s/enquire                                   |
| Enquiry board     | https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Admissions          |
| Admissions Review | https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Applications        |
| Student Invoices  | https://kasettitechnologiespvtltd.lightning.force.com/lightning/o/Student_Invoice__c/list |
| Finance Desk      | https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Finance_Desk        |
| Student portal    | https://kasettitechnologiespvtltd.my.site.com/s/my-learning                               |

---

## Step 1 — The student enquires online

👤 **Visitor** (no login) · 📍 Public enquiry, in a private window

1. **College admission** → **Yelahanka Campus** → **Bachelor of Engineering (BE)** → **BE Computer Science and Engineering** → **Year 1** → **Continue**.
2. Marks: SSLC **91**, PUC **92** (Science), **KCET** rank **12400** → ✅ _Your marks meet the published cut-off._
3. Your details: student name (new each run), mobile, email; parent optional → **Review** → tick consent → **Send enquiry**.

✅ _Thank you_ with a reference number and the documents to bring.

🗣 _"The family checks the cut-off at home. What they typed reaches the desk as data, not as a note."_

## Step 2 — The enquiry is a lead; the desk converts it

👤 **Admission Counsellor** · 📍 App Launcher → **KT College** → **Admissions** tab (the enquiry board; also in the KTEdutech app) → the new **Website** enquiry in **New** → **Convert to learner** (or open the enquiry → **Convert**)

0. Website enquiries for the college campuses are assigned to the Admission Counsellor, so the card is there with **Mine only** ticked too. Keep the branch filter on **All branches**; if the board was already open, press refresh.
1. The convert window shows **College admission · Yelahanka Campus · BE Computer Science and Engineering · 2026-27 · Year 1 (regular)** and the marks **as typed by the visitor** (SSLC 91, PUC Science 92, KCET 12400).
2. Check them against the marks card; correct any value if needed.
3. **Convert** stays disabled until you tick **I have checked these marks against the marks card** → tick → **Convert**.

✅ _Enquiry converted — the college admission is ready for document verification._ The new **admission** opens at **Processing**, **Eligible**, with privacy consent already recorded (given online) and the document checklist ready — Step 3 starts right here. If the student was already on file (same email, or same mobile and surname), that record is reused — no duplicate.

🗣 _"No retyping. The desk only confirms the marks against the original — and the system records who confirmed them."_

> Guard rails: a school counsellor without college access sees _"Only the college admission desk can convert a college enquiry."_ A second open admission for the same programme is refused.

## Step 3 — Document verification

👤 **Admission Counsellor** · 📍 Admissions Review → the student's admission → **College admission** panel

1. **Aadhaar card**: type the last 4 digits (e.g. `4321`) → **Verify** → _Accepted · ends 4321 · file removed_.
2. SSLC marks card, PUC marks card, fitness certificate, entrance rank card → **Verify** each.
3. **Mark documents verified** → stage **Documents Verified**.

🗣 _"Only the admission desk can verify documents, and only before the Dean's interview. We keep the last four Aadhaar digits, never the number or the image."_

## Step 4 — Admit (the counsellor; the Dean only for exceptions)

👤 **Admission Counsellor** · 📍 the same admission → **College admission** panel → **2 · Decision**

The student meets the cut-off, so there is no Dean step:

1. **Admit** → stage **Fee Pending** · enrolment **Provisional** · roll number _issued when the fee is received_.

✅ A seat is reserved and the first-year invoice (₹1,50,000 tuition + ₹5,000 admission) is issued with a 7-day deadline.

> **Only if the student does NOT meet the criteria** (eligibility _Not Eligible_): **Admit** is not offered. The counsellor types a **Reason for the Dean** (e.g. _PUC 58%, cut-off 60%; state-level sports certificate_) → **Request Dean approval** → stage **Awaiting Dean Approval**.
> 👤 **Anjali Advisor (Dean)** · 📍 KT College → **Admissions Review** (the Dean sees only these requests) → the admission → **Dean · exception request** → optional interview → **Approve exception** (back to the counsellor, who clicks **Admit**) or **Decline** with a reason (admission closed).
> The counsellor can also close it with **Not admitted** and a reason.

🗣 _"Eligible students are admitted by the desk the same day. The Dean only sees the exceptions — with the reason, and the decision is recorded with who and when."_

## Step 5 — The admission letter

👤 **Anjali Advisor** (or the Admission Counsellor) · 📍 the admission record → **Files** (refresh after a few seconds)

✅ **Admission Letter IA-… – {student}** (PDF): programme, branch, year, the invoice, the **pay-by date**, how to pay (DD, cheque, online — no cash), and that the seat is released if the fee is not received.

🗣 _"The letter is generated the moment the Dean admits, so the family has the fee and the deadline in writing the same day."_

## Step 6 — Fee payment

👤 **Admission Counsellor** · 📍 App Launcher → **KT College** → **Finance Desk** → **College invoices** (only the counsellor's campuses) → click the student's invoice (e.g. YLK-000389, ₹1,55,000) → **Record payment**.

1. **Record payment** → Method **Cash** → refused: _Payment method Cash is not allowed at this college campus._
2. **Record payment** → **Demand Draft**, reference `DD-4512`, DD number `004512`, bank `Canara Bank`, date today → payment **Pending**.
3. 📍 Back to **Finance Desk** → **Awaiting confirmation** → the payment → **Confirm** → invoice **Paid**.

🗣 _"The counsellor who admitted the student also takes the fee — but only for their own campuses. Refunds, credit notes and cancelling an invoice stay with Finance (Andrea) or the Dean."_

## Step 7 — Admission confirmed: roll number and confirmation letter

👤 **Anjali Advisor** · 📍 the admission (refresh). An enrolled admission leaves Admissions Review, so open it from **Home** → **College Students** → the student → **Admission**.

✅ Programme enrolment **Enrolled** · roll number **KT26YBCS0nn** (next number in the sequence). In **Files**: **Admission Confirmation KT26YBCS0nn – {student}** (PDF) with the roll number; the student also gets an _Admission confirmed_ message.

## Step 8 — Class allotment

👤 **Anjali Advisor** · 📍 the admission panel

1. The panel shows **Next: allot a section** → **Allot section** (opens the programme enrolment).
2. **Section** _YLK · BE-CSE · 2026-27 · Y1 · A_, **Joining date** today → **Join section**.

✅ The section is shown on the enrolment with the term's subjects; the prompt disappears from the admission panel.

## Step 9 — The student's portal (given at Admit)

👤 **Student** · the login is created **automatically at Admit (Step 4)** when the student has an email address and a portal licence is free; the welcome email carries the link to set a password. So the student can already see the admission letter and the invoice **before paying**.

- On the admission panel the counsellor sees **Student portal: Active / Not given / Needs an email / No free portal licence**.
- **Not given** → **Give portal access** (refresh after a few seconds). **Active** → **Send password link** re-sends the email.
- **Needs an email** → Home → **College Students** → **Student 360** → **Edit**, add the email, then **Give portal access**.
- To look as the student: as Kasetti Tech, the contact → ▾ → **Log in to Experience as User** → **My Learning**.

✅ Before payment: admission letter, invoice with the pay-by date. After payment: college card with the roll number and section, **Fees due ₹0**, and under **Documents** the confirmation letter and the receipt.

> Email needs Setup → **Deliverability** = _All email_ and a real sender address on the portal site (Setup → All Sites → Workspaces → Administration → Emails).

---

## Clean-up after the demo

The student, admission, invoice and payment are part of the audit trail and stay. Deactivate the portal user afterwards to free the licence (Setup → Users → untick **Active**). Use a new student name for the next run.

## If something goes wrong

| Symptom                                                         | Fix                                                                                 |
| --------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Convert window shows no college section                         | The enquiry did not come from the college page (no campus branch on it)             |
| _Only the college admission desk can convert…_                  | Log in as the Admission Counsellor (KEM College Admissions)                         |
| _This student already has an open admission for this programme_ | The student was used before — use a new name                                        |
| _Documents can be verified only before the Dean's interview_    | The admission is already past documents; continue from the Dean's step              |
| No letter in Files                                              | Wait a few seconds and refresh; generation runs right after the action              |
| _Confirm the payment from the Finance Desk…_                    | The status was edited directly — use Finance Desk → Awaiting confirmation → Confirm |
| No **Allot section** prompt                                     | The fee is not yet confirmed (enrolment still Provisional), or you are not the Dean |
