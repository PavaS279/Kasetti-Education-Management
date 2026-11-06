# UI Test Cases — Enquiry → Admission → Fee Payment

_Manual UI test cases for the end-to-end admission journey (updated 2026-11-03 with enquiry conversion, admission letters and section allotment in section A8; simple walkthrough in [COLLEGE-SIMPLE-DEMO-FLOW.md](COLLEGE-SIMPLE-DEMO-FLOW.md)), built from [COLLEGE-DEMO-SCRIPT.md](COLLEGE-DEMO-SCRIPT.md) (Stages 0–5), [COLLEGE-SETUP-GUIDE.md](COLLEGE-SETUP-GUIDE.md) and [WALKTHROUGH.md](WALKTHROUGH.md) (Acts B, C, D, F, H). Version 2026-11-03._

- **Track A — KT College** (PUC / Diploma / BE): public enquiry → walk-in eligibility → documents → Dean's decision → fee by DD → roll number → student portal.
- **Track B — After-school centres** (KTEdutech): enquiry → convert → application → offer → enrolment → invoice → payment → family portal.

Mark each case **Pass / Fail / Blocked** and write the record number or a screenshot name in _Evidence_.

---

## 1. Environment and links

| Code | What                       | Link                                                                                      |
| ---- | -------------------------- | ----------------------------------------------------------------------------------------- |
| `S`  | Staff login                | https://kasettitechnologiespvtltd.my.salesforce.com                                       |
| `L`  | Lightning base             | https://kasettitechnologiespvtltd.lightning.force.com                                     |
| `P`  | Portal (TrialOrgPortal)    | https://kasettitechnologiespvtltd.my.site.com                                             |
| ENQ  | Public enquiry page        | https://kasettitechnologiespvtltd.my.site.com/s/enquire                                   |
| PORT | My Learning (portal)       | https://kasettitechnologiespvtltd.my.site.com/s/my-learning                               |
| APP1 | KT College app             | https://kasettitechnologiespvtltd.lightning.force.com/lightning/app/c__KT_College         |
| APP2 | KTEdutech app              | https://kasettitechnologiespvtltd.lightning.force.com/lightning/app/c__Kasetti_Education  |
| ADM  | Admissions (enquiry board) | https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Admissions          |
| REV  | Admissions Review          | https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Applications        |
| FIN  | Finance Desk               | https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Finance_Desk        |
| INV  | Student Invoices list      | https://kasettitechnologiespvtltd.lightning.force.com/lightning/o/Student_Invoice__c/list |
| PAY  | Student Payments list      | https://kasettitechnologiespvtltd.lightning.force.com/lightning/o/Student_Payment__c/list |
| LEAD | Leads (enquiries) list     | https://kasettitechnologiespvtltd.lightning.force.com/lightning/o/Lead/list               |
| ACC  | Accounts (learners)        | https://kasettitechnologiespvtltd.lightning.force.com/lightning/o/Account/list            |
| CO   | Course Offerings (classes) | https://kasettitechnologiespvtltd.lightning.force.com/lightning/o/CourseOffering/list     |

Track B demo records:

| Record                                    | Link                                                                                                            |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Application IA-0000000032                 | https://kasettitechnologiespvtltd.lightning.force.com/lightning/r/IndividualApplication/0iTdN000000Ina9UAC/view |
| Invoice BLR-000007                        | https://kasettitechnologiespvtltd.lightning.force.com/lightning/r/Student_Invoice__c/a0adN00000ElWkLQAV/view    |
| Learner Ananya (Learner 360)              | https://kasettitechnologiespvtltd.lightning.force.com/lightning/r/Account/001dN000013Fo77QAC/view               |
| Enquiry Meera Nair (converted, read-only) | https://kasettitechnologiespvtltd.lightning.force.com/lightning/r/Lead/00QdN00000H5ukXUAR/view                  |

**Switching user:** log in at `S` as Kasetti Tech → Setup → **Users** → **Login** next to the user. **Log out** to return. For portal users: contact record → ▾ → **Log in to Experience as User**.

## 2. Personas

| Persona        | User                 | Username                                                                          | Used in             |
| -------------- | -------------------- | --------------------------------------------------------------------------------- | ------------------- |
| Visitor        | (no login)           | private / incognito window                                                        | A0                  |
| Admission desk | Admission Counsellor | `adamadmissionsuser1708459704071618019.w9ggkb3izggz.dk2pxr8w62ss@techkasetti.com` | A0–A2, B1–B4, B6–B7 |
| Dean           | Anjali Advisor       | `anjaliadvisoruser17084614018583395001.rkapknwbxzh6.asfwptgocb5j@techkasetti.com` | A3, A5, B8          |
| Accounts       | Andrea Advancement   | `andreaadvancementuser1708461643214542.k09qcubq0ix1.szcjc385fj75@techkasetti.com` | A4, B9–B10          |
| Student        | Ravi Kumar           | portal (setup guide §6.1)                                                         | A6                  |
| Guardian       | Rohit Sharma         | `rsharma.kemdemo@kasetti-portal.demo`                                             | B11                 |

## 3. Preconditions (check before you start)

| #   | Check                                                                                                                      | ☐   |
| --- | -------------------------------------------------------------------------------------------------------------------------- | --- |
| P1  | College set-up done ([COLLEGE-SETUP-GUIDE.md](COLLEGE-SETUP-GUIDE.md)): 2 campuses, 3 programmes, 22 branches, 22 sections | ☐   |
| P2  | The Admission Counsellor and Anjali are in **KEM College Admissions Team**; Anjali has **KEM College Dean**                | ☐   |
| P3  | REV shows the five `[KEM College]` admissions (Ravi, Meghana, Sneha, Kiran, Arjun) at _Processing_                         | ☐   |
| P4  | Ravi Kumar has **not** been used in an earlier run (otherwise use a new walk-in from A1)                                   | ☐   |
| P5  | One **Customer Community Plus** licence free (Setup → Company Information) for Ravi's portal login                         | ☐   |
| P6  | Track B: Online payments mode is `Test` only if you run TC-B10.3; set back to `Off` afterwards                             | ☐   |
| P7  | Use example email addresses only — portal access sends real emails                                                         | ☐   |

## 4. Test data

| Data                            | Value                                                                                          |
| ------------------------------- | ---------------------------------------------------------------------------------------------- |
| Campus / programme              | Yelahanka Campus · Bachelor of Engineering (BE) · BE Computer Science and Engineering · Year 1 |
| BE CSE cut-off                  | PUC Science ≥ 90 % and KCET rank ≤ 20,000 or COMEDK rank ≤ 15,000                              |
| Enquiry (below cut-off)         | SSLC 88, PUC 86, KCET 18200                                                                    |
| Walk-in (ineligible)            | Pooja Nayak, DOB 12-05-2008, SSLC 90, PUC 84, KCET 25000; parent Ramesh Nayak                  |
| Main student                    | Ravi Kumar [KEM College] — PUC Science 92 %, KCET 12,400                                       |
| First-year fee (walk-in screen) | ₹1,10,000 + ₹5,000 = ₹1,15,000 (BE Mechanical)                                                 |
| Ravi's invoice                  | ₹1,50,000 tuition + ₹5,000 admission = **₹1,55,000**, due in 7 days                            |
| DD                              | Reference `DD-4512`, number `004512`, bank `Canara Bank`, date today                           |
| Aadhaar                         | last 4 digits `4321`                                                                           |
| Expected roll number            | `KT26YBCS001` (lateral entry Kiran: `KT26RBCS401`)                                             |

---

## Track A — KT College

### A0. Public online enquiry

**Persona:** Visitor · **Link:** [ENQ](https://kasettitechnologiespvtltd.my.site.com/s/enquire) (private window)

| ID       | Steps                                                                                                                                                                                        | Expected result                                                                                                                                            | Result | Evidence |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ | -------- |
| TC-A0.1  | Open ENQ without logging in                                                                                                                                                                  | Page loads without a login prompt; first question _What are you interested in?_                                                                            |        |          |
| TC-A0.2  | Choose **College admission**                                                                                                                                                                 | Programme step appears                                                                                                                                     |        |          |
| TC-A0.3  | Yelahanka Campus → BE → look at the branch cards                                                                                                                                             | Each branch shows its published cut-off; **no seat counts** are shown                                                                                      |        |          |
| TC-A0.4  | Choose **BE Computer Science and Engineering** → Year 1 → **Continue**                                                                                                                       | Eligibility step asks only for SSLC %, PUC % (stream fixed to _Science_), entrance exam and rank                                                           |        |          |
| TC-A0.5  | Enter SSLC 88, PUC 86, KCET 18200                                                                                                                                                            | _Below the cut-off for this branch_: ✗ PUC (Science) at least 90% — 86%; _You are eligible for_ BE ECE, BE Mechanical, BE Civil, each with **Choose this** |        |          |
| TC-A0.6  | Click **Choose this** on one suggestion, then go back and re-select CSE                                                                                                                      | Branch switches and the check turns eligible; returning to CSE shows the shortfall again                                                                   |        |          |
| TC-A0.7  | Continue with CSE (below cut-off)                                                                                                                                                            | The visitor is **allowed** to continue (desk will call)                                                                                                    |        |          |
| TC-A0.8  | Your details: leave name and mobile empty → continue                                                                                                                                         | Validation stops you; name and mobile are required                                                                                                         |        |          |
| TC-A0.9  | Enter student name and mobile; leave parent empty                                                                                                                                            | Allowed; parent is optional (recommended under 18)                                                                                                         |        |          |
| TC-A0.10 | Review: try **Send enquiry** without ticking consent                                                                                                                                         | Not possible until consent is ticked                                                                                                                       |        |          |
| TC-A0.11 | Review shows first-year fees and document list → tick consent → **Send enquiry**                                                                                                             | _Thank you_ with a **reference number** and the document list                                                                                              |        |          |
| TC-A0.12 | As **the Admission Counsellor** open [ADM](https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Admissions)                                                                 | New **Website** enquiry in _New_: campus Yelahanka Campus, interest BE CSE, the marks and the self-check result in the description                         |        |          |
| TC-A0.13 | Check records in [LEAD](https://kasettitechnologiespvtltd.lightning.force.com/lightning/o/Lead/list) / [ACC](https://kasettitechnologiespvtltd.lightning.force.com/lightning/o/Account/list) | Only the enquiry is created — no account, application or invoice                                                                                           |        |          |

### A1. Walk-in eligibility at the admission desk

**Persona:** Admission Counsellor · **Link:** [APP1](https://kasettitechnologiespvtltd.lightning.force.com/lightning/app/c__KT_College) → **Home** → **Walk-in admission** card

| ID       | Steps                                                                                                                     | Expected result                                                                                                                                                                                                                            | Result | Evidence |
| -------- | ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------ | -------- |
| TC-A1.1  | Click **New college admission**                                                                                           | Guided screen opens; nothing is saved until the last step                                                                                                                                                                                  |        |          |
| TC-A1.2  | Yelahanka → BE → BE CSE                                                                                                   | Branch card shows cut-off (_PUC Science 90% + entrance rank_) and **seats left**; Year 1 (regular) and Year 2 (lateral entry) offered                                                                                                      |        |          |
| TC-A1.3  | Keep Year 1 → **Next**                                                                                                    | Marks step asks only SSLC %, PUC stream (_Science_, only option), PUC %, entrance exam (KCET / COMEDK) and rank                                                                                                                            |        |          |
| TC-A1.4  | Enter SSLC 90, PUC 84, KCET 25000                                                                                         | Live panel: ✗ PUC (Science) at least 90% — 84%; ✗ Entrance … — KCET 25,000; **Not eligible for this branch**                                                                                                                               |        |          |
| TC-A1.5  | Look at suggestions and the **Next** button                                                                               | _Eligible instead for:_ BE ECE (80 %), BE Mechanical (65 %), BE Civil (60 %) with **Switch**; **Next disabled**                                                                                                                            |        |          |
| TC-A1.6  | **Switch** → BE Mechanical Engineering                                                                                    | Panel turns ✅ **Eligible** with the same marks; **Next** enabled                                                                                                                                                                          |        |          |
| TC-A1.7  | Student: Pooja Nayak, DOB 12-05-2008, mobile                                                                              | Parent section shows _recommended: the student is under 18_                                                                                                                                                                                |        |          |
| TC-A1.8  | Add parent Ramesh Nayak + mobile → **Next**                                                                               | Documents and fees step                                                                                                                                                                                                                    |        |          |
| TC-A1.9  | Check documents and fees                                                                                                  | Required: Aadhaar, SSLC, PUC marks card, fitness certificate, rank card; optional: study certificate, PAN; note _only the last 4 Aadhaar digits are kept_; fee ₹1,10,000 + ₹5,000 = ₹1,15,000, DD/cheque/online within 7 days, **no cash** |        |          |
| TC-A1.10 | Try **Create admission** without consent                                                                                  | Blocked until **privacy consent** is ticked                                                                                                                                                                                                |        |          |
| TC-A1.11 | Tick consent → **Create admission**                                                                                       | Admission opens at _Processing_, **Eligible**, consent recorded, checklist ready                                                                                                                                                           |        |          |
| TC-A1.12 | [REV](https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Applications) → **Sneha Gowda [KEM College]** | **Not Eligible — "The qualifying stream is not accepted for this branch."** (PUC Commerce)                                                                                                                                                 |        |          |
| TC-A1.13 | REV → **Meghana Rao [KEM College]**                                                                                       | Not eligible: "needs 90 %; the student has 86 %", with suggestions                                                                                                                                                                         |        |          |
| TC-A1.14 | REV → **Ravi Kumar [KEM College]**                                                                                        | **Eligible — "The verified qualification and entrance score meet the active rule."** Stage _Processing_                                                                                                                                    |        |          |

### A2. Documents and verification

**Persona:** Admission Counsellor · **Link:** [REV](https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Applications) → Ravi Kumar [KEM College] → **College admission** panel

| ID      | Steps                                                                 | Expected result                                                                                                      | Result | Evidence |
| ------- | --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ------ | -------- |
| TC-A2.1 | Click **Mark documents verified** before verifying anything           | Refused — required documents are not yet Accepted                                                                    |        |          |
| TC-A2.2 | **Record privacy consent**                                            | Toast "Privacy consent recorded"                                                                                     |        |          |
| TC-A2.3 | Review the checklist                                                  | Aadhaar, SSLC, PUC marks card, fitness certificate, entrance rank card (required); study certificate, PAN (optional) |        |          |
| TC-A2.4 | Click **SSLC marks card** → Files → **Upload Files** → any PDF → back | File attached to the document                                                                                        |        |          |
| TC-A2.5 | Aadhaar: enter `4321` → **Verify**                                    | _Accepted · ends 4321 · file removed_; the full number and image are not stored                                      |        |          |
| TC-A2.6 | Aadhaar: try fewer/more than 4 digits or letters                      | Rejected — only 4 digits accepted                                                                                    |        |          |
| TC-A2.7 | **Verify** SSLC, PUC, fitness certificate, entrance rank card         | Each shows _Accepted_                                                                                                |        |          |
| TC-A2.8 | **Mark documents verified**                                           | Stage **Documents Verified**                                                                                         |        |          |

### A3. Dean's interview and decision

**Persona:** Anjali Advisor · **Link:** [APP1](https://kasettitechnologiespvtltd.lightning.force.com/lightning/app/c__KT_College) → **Admissions Review** → Ravi Kumar [KEM College] → **Dean** block

| ID      | Steps                                                                                  | Expected result                                                                                                                       | Result | Evidence |
| ------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ------ | -------- |
| TC-A3.1 | As **the Admission Counsellor**, open Ravi's admission                                 | **No Dean block** (interview / admit / reject only for KEM College Dean)                                                              |        |          |
| TC-A3.2 | As Anjali, on an admission still at _Processing_ (e.g. Pooja) → **Schedule interview** | "Verify the required documents before scheduling"                                                                                     |        |          |
| TC-A3.3 | Ravi: schedule with a **future** time, then try **Record outcome**                     | "An outcome can be recorded only after the scheduled interview"                                                                       |        |          |
| TC-A3.4 | Ravi: date/time now → **Schedule interview**                                           | Stage **Interview Scheduled**                                                                                                         |        |          |
| TC-A3.5 | Outcome **Pass**, remarks _"Strong maths, good communication"_ → **Record outcome**    | Stage **Ready For Decision**                                                                                                          |        |          |
| TC-A3.6 | **Admit**                                                                              | Stage **Fee Pending** · Programme enrolment **Provisional** · roll number _"issued when the fee is received"_                         |        |          |
| TC-A3.7 | Check the seat and invoice                                                             | One of 60 BE-CSE Yelahanka seats **reserved** (seats left −1 on the branch card); annual invoice ₹1,55,000 issued, due today + 7 days |        |          |
| TC-A3.8 | Meghana Rao → **Reject** without a reason                                              | Refused — reason required                                                                                                             |        |          |
| TC-A3.9 | Reason _"Below the BE CSE cut-off; offered BE ECE"_ → **Reject**                       | Stage **Application Decision**, decision _Reject_; no seat, no invoice                                                                |        |          |

### A4. Fee payment (no cash, DD clears through the bank)

**Persona:** Andrea Advancement · **Link:** [APP2](https://kasettitechnologiespvtltd.lightning.force.com/lightning/app/c__Kasetti_Education) → [INV](https://kasettitechnologiespvtltd.lightning.force.com/lightning/o/Student_Invoice__c/list)

| ID       | Steps                                                                                                        | Expected result                                                                                      | Result | Evidence |
| -------- | ------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- | ------ | -------- |
| TC-A4.1  | Open Ravi's invoice (Learner _Ravi Kumar [KEM College]_)                                                     | Status Issued, total **₹1,55,000** (₹1,50,000 tuition + ₹5,000 admission), due date = admit date + 7 |        |          |
| TC-A4.2  | Check discounts                                                                                              | No discount option (discounts are switched off for the college)                                      |        |          |
| TC-A4.3  | **Record payment** → Method **Cash**, ₹1,55,000                                                              | Refused: _"Payment method Cash is not allowed at this college campus."_                              |        |          |
| TC-A4.4  | **Record payment** → Demand Draft with empty DD number / bank / date                                         | Refused — DD number, bank and date are required                                                      |        |          |
| TC-A4.5  | Demand Draft, Ref `DD-4512`, number `004512`, bank `Canara Bank`, date today → **Record payment**            | Payment **Pending**; invoice **not** Paid yet                                                        |        |          |
| TC-A4.6  | Back on Ravi's admission (any staff)                                                                         | Still **Provisional**; no roll number while the DD is Pending                                        |        |          |
| TC-A4.7  | [FIN](https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Finance_Desk) → **College dues** | Yelahanka · BE CSE · 2026-27 → Billed ₹1,55,000, **Awaiting clearance ₹1,55,000**                    |        |          |
| TC-A4.8  | FIN → **Awaiting confirmation** → Ravi's payment → **Confirm**                                               | Invoice **Paid**; College dues Due **₹0**; receipt **RCT-…** with PDF                                |        |          |
| TC-A4.9  | Try to confirm the same payment again                                                                        | Payment no longer in _Awaiting confirmation_                                                         |        |          |
| TC-A4.10 | As **Anjali**, open Home                                                                                     | No receivables, no Finance Desk (role separation)                                                    |        |          |

### A5. Admission confirmed — roll number

**Persona:** Anjali Advisor · **Link:** [REV](https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Applications) → Ravi Kumar [KEM College]

| ID      | Steps                                                             | Expected result                                                    | Result | Evidence |
| ------- | ----------------------------------------------------------------- | ------------------------------------------------------------------ | ------ | -------- |
| TC-A5.1 | Open the College admission panel                                  | Programme enrolment **Enrolled** · roll number **KT26YBCS001**     |        |          |
| TC-A5.2 | Check the seat                                                    | Seat is **final** (no longer provisional)                          |        |          |
| TC-A5.3 | Check Ravi's messages                                             | _"Admission confirmed — roll number …"_ message created            |        |          |
| TC-A5.4 | Try to edit the roll number                                       | Not editable — roll numbers never change and are never reused      |        |          |
| TC-A5.5 | (Optional) Repeat A2–A4 for **Kiran Patil** (Rajajinagar, Year 2) | Roll number **KT26RBCS401** (R = Rajajinagar, 401 = lateral entry) |        |          |

### A6. Student portal

**Persona:** Ravi Kumar · Set-up guide §6.1 (Accounts → Ravi → **Portal access** → **Give access**), then contact → ▾ → **Log in to Experience as User** → [PORT](https://kasettitechnologiespvtltd.my.site.com/s/my-learning)

| ID      | Steps                                       | Expected result                                                                          | Result | Evidence |
| ------- | ------------------------------------------- | ---------------------------------------------------------------------------------------- | ------ | -------- |
| TC-A6.1 | Open My Learning                            | College card: Yelahanka Campus · BE CSE · **Roll number KT26YBCS001** · 2026-27 · year 1 |        |          |
| TC-A6.2 | Fees section                                | **Fees due ₹0**; invoice and receipt downloadable                                        |        |          |
| TC-A6.3 | Messages                                    | Fee received and admission confirmed messages                                            |        |          |
| TC-A6.4 | Try another student's record (e.g. Meghana) | "You do not have access to this learner." — only own record visible                      |        |          |
| TC-A6.5 | (Variant) Give access **before** A4         | Card shows the "pay by" state with the amount due instead of a roll number               |        |          |

### A7. Seat expiry (scheduled job — verify next day, or explain)

| ID      | Scenario                                       | Expected result                                                                   | Result | Evidence |
| ------- | ---------------------------------------------- | --------------------------------------------------------------------------------- | ------ | -------- |
| TC-A7.1 | Admitted, nothing paid for 7 days              | Nightly run expires the provisional admission; seat released                      |        |          |
| TC-A7.2 | Admitted, DD Pending or part-paid after 7 days | Not expired — appears on the Dean's **overdue list** with **Extend** / **Cancel** |        |          |

### A8. Simple flow additions (deployed 2026-11-03)

**Links:** [ADM](https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Admissions), [REV](https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Applications), [FIN](https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Finance_Desk)

| ID       | Persona                   | Steps                                                                                     | Expected result                                                                                                                               | Result | Evidence |
| -------- | ------------------------- | ----------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ------ | -------- |
| TC-A8.1  | Visitor                   | Submit a college enquiry on ENQ (new student name)                                        | On the Lead: **Campus Branch**, **Entry Route** and **Declared Marks** are filled                                                             |        |          |
| TC-A8.2  | the Admission Counsellor  | ADM → the enquiry → **Convert**                                                           | Window shows _College admission_, the intake, the route and the declared marks; no "Create admissions application" toggle                     |        |          |
| TC-A8.3  | the Admission Counsellor  | Leave the marks-card box unticked                                                         | **Convert** disabled                                                                                                                          |        |          |
| TC-A8.4  | the Admission Counsellor  | Correct one mark → tick _I have checked these marks against the marks card_ → **Convert** | Student record opens; REV shows the admission at **Processing**, **Eligible**, consent recorded, checklist ready; the corrected mark is saved |        |          |
| TC-A8.5  | Rahul (no college access) | Open a college enquiry → **Convert**                                                      | _Only the college admission desk can convert a college enquiry._                                                                              |        |          |
| TC-A8.6  | the Admission Counsellor  | Walk-in (**New college admission**) with the same email as an existing student            | The existing student is reused (no second account); a second open admission for the same programme → _already has an open admission_          |        |          |
| TC-A8.7  | Andrea                    | Open a college admission and try to verify a document                                     | No verify buttons; the server refuses with _You do not have permission_                                                                       |        |          |
| TC-A8.8  | the Admission Counsellor  | Verify a document on an admission at Interview Scheduled or later                         | _Documents can be verified only before the Dean's interview_                                                                                  |        |          |
| TC-A8.9  | Anjali                    | **Admit** → wait a few seconds → admission **Files**                                      | **Admission Letter IA-… – {student}** PDF: programme, branch, year, invoice, pay-by date, payment methods, no cash                            |        |          |
| TC-A8.10 | Andrea                    | Payments list → edit a **Pending** DD → Status **Confirmed** → Save                       | Refused: _Confirm the payment from the Finance Desk so it is allocated and the receipt is issued._                                            |        |          |
| TC-A8.11 | Andrea                    | FIN → Awaiting confirmation → **Confirm**                                                 | Invoice Paid; roll number issued                                                                                                              |        |          |
| TC-A8.12 | Anjali                    | Admission **Files** (refresh)                                                             | **Admission Confirmation KT26… – {student}** PDF showing the roll number                                                                      |        |          |
| TC-A8.13 | Anjali                    | Admission panel after the fee                                                             | **Next: allot a section** with **Allot section** → opens the enrolment; after **Join section** the prompt is gone                             |        |          |
| TC-A8.14 | Student                   | Portal → My Learning → Documents                                                          | Admission letter and confirmation letter listed with the invoice and receipt                                                                  |        |          |
| TC-A8.15 | Dean (nightly)            | Let a provisional admission expire, or **Cancel** it from the overdue list                | The admission letter is marked _(superseded)_ and stays on file                                                                               |        |          |

---

## Track B — After-school centres (KTEdutech)

### B1–B4. Enquiry

**Persona:** Admission Counsellor · **Link:** [ADM](https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Admissions)

| ID      | Steps                                                                                                        | Expected result                                                                                                | Result | Evidence |
| ------- | ------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------- | ------ | -------- |
| TC-B1.1 | **New enquiry** with no phone and no email → **Save enquiry**                                                | "Enter at least one email address or phone number…"                                                            |        |          |
| TC-B1.2 | Learner (name, DOB), guardian (name, relationship, phone), branch, course, channel, follow-up date → Save    | Card in **New**, assigned to a branch counsellor                                                               |        |          |
| TC-B1.3 | Repeat with the same guardian phone                                                                          | Flagged as a **duplicate**                                                                                     |        |          |
| TC-B1.4 | New enquiry with referral code `SHA-S8EZ`                                                                    | Channel becomes _Referral_, linked to Rohit                                                                    |        |          |
| TC-B2.1 | Open the new enquiry → **Reply with Einstein** → note → **Draft reply** → edit → **Copy and record as sent** | Plain-text reply with real class times, no invented prices; completed task recorded (needs KEM AI User)        |        |          |
| TC-B3.1 | **Log follow-up** (outcome, notes, next date)                                                                | Stage moves on; follow-up task created                                                                         |        |          |
| TC-B4.1 | **Convert** with _Create admissions application_ on                                                          | Learner + guardian person accounts (or matched), guardian = fee payer / emergency contact, application created |        |          |
| TC-B4.2 | Open the learner → **Learner 360**                                                                           | Guardians, Applications, Classes, Results, Fees tabs populated                                                 |        |          |
| TC-B4.3 | (Walk-in) ADM → **New family (walk-in)** per WALKTHROUGH B0                                                  | Existing parent offered as **Use existing**; one child enrolled, other's application at Processing             |        |          |

### B6–B8. Application, documents, offer

**Persona:** the Admission Counsellor (B6–B7), Anjali or manager (B8) · **Link:** the application from B4, or [IA-0000000032](https://kasettitechnologiespvtltd.lightning.force.com/lightning/r/IndividualApplication/0iTdN000000Ina9UAC/view)

| ID      | Steps                                                                                                   | Expected result                                                                          | Result | Evidence |
| ------- | ------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ------ | -------- |
| TC-B6.1 | **Ready for decision** with checklist incomplete                                                        | "All required checklist items must be accepted or waived first."                         |        |          |
| TC-B6.2 | **Accept** birth certificate, address proof, photo ID; **Waive** optional ones                          | Items Accepted / Waived; Eligibility (age rule) shown                                    |        |          |
| TC-B6.3 | Guardian uploads from portal → **Admission documents**                                                  | Portal shows _Sent – awaiting review_; staff see the file with **View** on the checklist |        |          |
| TC-B7.1 | **AI document reader** → paste certificate text → **Read text** → correct one → **Apply**               | Fields filled; health, religion, caste, income, ID numbers never extracted               |        |          |
| TC-B8.1 | **Submit for review** → **Ready for decision** → **Decide**: Admit, valid 14 days → **Record decision** | Offer **Offered** with expiry; **Offer Letter PDF** in Documents within a minute         |        |          |
| TC-B8.2 | **Record acceptance**                                                                                   | **Enrol in class** appears                                                               |        |          |
| TC-B8.3 | Record acceptance after the offer expiry                                                                | Refused                                                                                  |        |          |
| TC-B8.4 | **Enrol in class** → _[KEM Demo] Journey D2_ → code `SIBLING10` → **Confirm enrolment**                 | Application **Enrolled**; roster shows learner with agreed total, billing _Not Invoiced_ |        |          |
| TC-B8.5 | Enrol into the full _Maths Saturday_ class                                                              | Refused: class is Full                                                                   |        |          |

### B9–B10. Invoice and payment

**Persona:** Andrea Advancement · **Links:** [CO](https://kasettitechnologiespvtltd.lightning.force.com/lightning/o/CourseOffering/list), [BLR-000007](https://kasettitechnologiespvtltd.lightning.force.com/lightning/r/Student_Invoice__c/a0adN00000ElWkLQAV/view), [FIN](https://kasettitechnologiespvtltd.lightning.force.com/lightning/n/KEM_Finance_Desk)

| ID       | Steps                                                                           | Expected result                                                                                                                  | Result | Evidence |
| -------- | ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ------ | -------- |
| TC-B9.1  | Class roster → learner from B8.4 → ▾ **Create invoice**                         | Invoice **BLR-…** to the fee-paying guardian, due date from branch policy, lines with tax, **Invoice PDF**; billing **Invoiced** |        |          |
| TC-B9.2  | **Record payment** on a **Draft** invoice                                       | "Payments can only be taken against issued invoices."                                                                            |        |          |
| TC-B10.1 | Issued invoice → **Record payment** UPI 6,000                                   | Receipt **RCT-…** with PDF; invoice **Partially Paid**                                                                           |        |          |
| TC-B10.2 | Record a **cheque** for the balance with cheque number, bank and date           | Payment **Pending**; FIN → Awaiting confirmation → **Confirm** → invoice **Paid**                                                |        |          |
| TC-B10.3 | (Test mode) Portal → Fees → **Pay online** as Rohit; staff **Simulate payment** | "Test mode: payment request PL-… was created. No money is taken." → payment recorded, invoice Paid                               |        |          |
| TC-B10.4 | Pay online while mode is `Off`                                                  | "Online payments are not available yet. Please pay at the branch."                                                               |        |          |
| TC-B10.5 | Overpay an invoice → FIN → **Reconciliation exceptions** → **Hold as credit**   | Exception queued, then resolved as credit                                                                                        |        |          |

### B11. Family portal

**Persona:** Rohit Sharma · **Link:** [PORT](https://kasettitechnologiespvtltd.my.site.com/s/my-learning)

| ID       | Steps                                     | Expected result                                                                           | Result | Evidence |
| -------- | ----------------------------------------- | ----------------------------------------------------------------------------------------- | ------ | -------- |
| TC-B11.1 | Switch between Ananya and Arjun           | Both children visible to Rohit (Priya sees only Ananya)                                   |        |          |
| TC-B11.2 | **Fees**                                  | Invoices, balance, receipts, instalments                                                  |        |          |
| TC-B11.3 | **Documents**                             | Offer letter, invoices, receipts downloadable                                             |        |          |
| TC-B11.4 | **Messages**                              | Invoice and payment notices                                                               |        |          |
| TC-B11.5 | Request another family's learner/document | "You do not have access to this learner." / "Document not found or not available to you." |        |          |

---

## 5. Traceability

| Stage                 | Track A cases | Track B cases | Source                                                     |
| --------------------- | ------------- | ------------- | ---------------------------------------------------------- |
| Enquiry               | A0            | B1–B4         | College script Stage 0 · Walkthrough Act B                 |
| Eligibility           | A1            | B6.2          | Stage 1 · Act C1                                           |
| Documents             | A2            | B6, B7        | Stage 2 · Act C1–C2, H11                                   |
| Decision / offer      | A3            | B8.1–B8.3     | Stage 3 · Act C3                                           |
| Enrolment / seat      | A3.7, A5      | B8.4–B8.5     | Stages 3, 5 · Act D1                                       |
| Invoice and payment   | A4            | B9–B10        | Stage 4 · Act F1–F2, F5                                    |
| Confirmation / portal | A5, A6        | B11           | Stages 5, 10 · Act H                                       |
| Scheduled jobs        | A7            | —             | Script "Close" table                                       |
| Simple flow additions | A8            | —             | [COLLEGE-SIMPLE-DEMO-FLOW.md](COLLEGE-SIMPLE-DEMO-FLOW.md) |

## 6. Troubleshooting

| Symptom                                                                | Fix                                                                    |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| **Next** disabled on _Marks and cut-off_                               | Student not eligible — **Switch** to a suggested branch or check marks |
| The Admission Counsellor / Anjali can't see `[KEM College]` admissions | Add them to **KEM College Admissions Team** (set-up step 5)            |
| No Dean block                                                          | Assign **KEM College Dean** to Anjali (set-up step 4)                  |
| Roll number missing after the DD                                       | DD still **Pending** — confirm it in Finance Desk                      |
| No college card in the portal                                          | Not admitted yet, or portal user not created (set-up 6.1)              |
| Ravi already used in an earlier run                                    | Run the full journey with a new walk-in from A1                        |
