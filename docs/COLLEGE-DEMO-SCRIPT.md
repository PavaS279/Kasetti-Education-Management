# KT College — Final Demo Script

_Admission season at KT College, told in the order it happens in a real institute: walk-in → eligibility → documents → Dean's interview → fees → roll number → joining → classes → marks → results → student portal. About 45 minutes. Version 2026-10-14._

**Before you start:** complete [COLLEGE-SETUP-GUIDE.md](COLLEGE-SETUP-GUIDE.md) (users, permission sets, admissions team, Ravi's portal login). You present as five people; switch with Setup → **Users** → **Login** next to the name, and **Log out** to return to Kasetti Tech.

| Who            | User               | Role in the story                                                  | App to use                                          |
| -------------- | ------------------ | ------------------------------------------------------------------ | --------------------------------------------------- |
| Admission desk | Adam Admissions    | Meets the student, checks cut-offs, verifies documents             | KT College (Home) and KTEdutech (Admissions Review) |
| Dean           | Anjali Advisor     | Interviews, admits or rejects, assigns sections, finalises results | KT College                                          |
| Accounts       | Andrea Advancement | Takes the fee by DD/cheque/online, clears it                       | KTEdutech                                           |
| Faculty        | Tara Teacher       | Takes classes, attendance and marks                                | KTEdutech                                           |
| Student        | Ravi Kumar         | Sees his roll number, timetable, attendance, results               | Portal → My Learning                                |

The administrator (Kasetti Tech) is not shown. Say once at the start: _"Everything the administrator configures — campuses, programmes, cut-offs, fees, documents — is already set and stays in the background."_

**The story:** Ravi Kumar has passed PUC Science with 92 % and KCET rank 12,400. He walks into **Yelahanka Campus** to join **BE Computer Science (CSE)**, where the cut-off is 90 % with KCET up to 20,000. On the same day other students are refused, for different reasons.

---

## Stage 0 — Online enquiry from the college website

👤 **A visitor** (no login) · open `https://kasettitechnologiespvtltd.my.site.com/s/enquire` in a private browser window

1. **What are you interested in?** → **College admission**.
2. **Programme** — **Yelahanka Campus** → **Bachelor of Engineering (BE)** → **BE Computer Science and Engineering** (each branch shows its published cut-off) → **Year 1** → **Continue**.
3. **Eligibility** — only the fields this branch needs appear. Enter SSLC **88**, PUC **86** (stream fixed to _Science_), **KCET** rank **18200**.
   ✅ _Below the cut-off for this branch_: ✗ PUC (Science) at least 90% — 86%; and _You are eligible for_ BE ECE, BE Mechanical, BE Civil with **Choose this**. The visitor may still continue — the desk will call.
4. **Your details** — student name and mobile; parent optional (recommended under 18).
5. **Review** — fees for the first year and the documents to bring → tick consent → **Send enquiry**.
   ✅ _Thank you_ with a reference number and the document list.

👤 **Adam Admissions** · KTEdutech → **Admissions** (enquiry board) → the new **Website** enquiry: campus _Yelahanka Campus_, interest _BE Computer Science and Engineering_, and the marks with the self-check result in the description.

🗣 _"Families check the cut-off themselves at home, any time. The enquiry reaches the desk already qualified, with the marks and the branches the student can join."_

> The public page shows only published information (cut-offs, fees, documents); it never shows seat counts or other students, and nothing is created except the enquiry.

## Stage 1 — Walk-in at the admission desk: is the student eligible?

👤 **Adam Admissions** · App Launcher → **KT College** → **Home**

**Step 1.1 — A walk-in who misses the cut-off.** On the **Walk-in admission** card click **New college admission**. A guided screen opens — nothing is saved until the last step.

1. **Programme** — click the tiles: **Yelahanka Campus** → **Bachelor of Engineering (BE)** → **BE Computer Science and Engineering**. Each branch card shows its cut-off (_PUC Science 90% + entrance rank_) and seats left. BE branches also offer **Year 2 (lateral entry from Diploma)**; leave **Year 1 (regular)**. → **Next**.
2. **Marks and cut-off** — the screen now asks only for what BE CSE needs: **SSLC %**, **PUC stream** (already _Science_ — the only stream BE accepts), **PUC %**, and the **entrance exam** (_KCET rank up to 20,000_ or _COMEDK rank up to 15,000_) with the **rank**. Type SSLC **90**, PUC **84**, KCET, rank **25000**.

   As you type, the panel on the right checks each criterion:
   - ✗ PUC (Science) at least 90% — **84%**
   - ✗ Entrance: KCET rank up to 20,000 or COMEDK rank up to 15,000 — **KCET 25,000**

   ✅ **Not eligible for this branch**, and _Eligible instead for:_ **BE Electronics and Communication** (80 %), **BE Mechanical Engineering** (65 %), **BE Civil Engineering** (60 %), each with a **Switch** button. **Next** stays disabled — an ineligible admission cannot be created.

3. Click **Switch** next to **BE Mechanical Engineering** → the cut-off panel turns ✅ **Eligible** with the same marks. → **Next**.
4. **Student** — Pooja Nayak, date of birth 12-05-2008, mobile; the parent section says _recommended: the student is under 18_ → add **Ramesh Nayak** and a mobile. → **Next**.
5. **Documents and fees** — what to bring (Aadhaar · SSLC · PUC marks card · fitness certificate · rank card required; study certificate · PAN optional; _only the last 4 Aadhaar digits are kept_) and the first-year fee (**₹1,10,000 + ₹5,000 = ₹1,15,000**, by DD, cheque or online within 7 days, no cash). Tick the **privacy consent** → **Create admission**.

✅ The new admission opens at _Processing_, already **Eligible**, with consent recorded and the document checklist ready.

🗣 _"The desk never has to remember cut-offs or document lists. The screen asks only what this branch needs, tells the family immediately whether the child qualifies — and which branches they can still join — before anything is saved."_

**Step 1.2 — A refusal for a different reason.** **Admissions Review** tab → open **Sneha Gowda [KEM College]** (recorded earlier in the season).

✅ **Not Eligible — "The qualifying stream is not accepted for this branch."** (PUC Commerce cannot take BE.)

**Step 1.3 — Close to the cut-off.** Open **Meghana Rao [KEM College]** → ✅ "needs 90 %; the student has 86 %", with suggestions.

**Step 1.4 — Our student.** Open **Ravi Kumar [KEM College]** → ✅ **Eligible — "The verified qualification and entrance score meet the active rule."** Stage: _Processing_. Ravi's admission continues in Stage 2 (Pooja's can follow the same steps).

---

## Stage 2 — Documents and verification

👤 **Adam Admissions** · **Admissions Review** → **Ravi Kumar [KEM College]** → the **College admission** panel

**Step 2.1 — Consent.** Click **Record privacy consent**. ✅ "Privacy consent recorded".

🗣 _"Under India's data protection law we record consent before handling Aadhaar or medical documents."_

**Step 2.2 — The checklist.** The panel lists what this student must bring — it depends on the programme and his qualifications: Aadhaar, SSLC marks card, PUC marks card, fitness certificate, entrance rank card (required), study certificate and PAN (optional).

**Step 2.3 — Upload (optional).** Click a document name, e.g. **SSLC marks card** → **Files** → **Upload Files** → any PDF or photo → back to the admission.

**Step 2.4 — Verify each required document.**

- **Aadhaar card:** type the **last 4 digits** (e.g. `4321`) → **Verify**. ✅ Status _Accepted · ends 4321 · file removed_.
  🗣 _"We never keep the full Aadhaar number or the image — only the last four digits, who verified it and when."_
- SSLC marks card, PUC marks card, fitness certificate, entrance rank card → **Verify** each.

**Step 2.5 — Hand over to the Dean.** Click **Mark documents verified**. ✅ Stage **Documents Verified**.

---

## Stage 3 — Dean's interview and decision

👤 **Anjali Advisor** · App Launcher → **KT College** → **Admissions Review** tab → **Ravi Kumar [KEM College]**

**Step 3.1 — Schedule.** In the **Dean** block, leave the date/time as now → **Schedule interview**. ✅ Stage **Interview Scheduled**.

**Step 3.2 — Record the outcome.** Outcome **Pass**, remarks _"Strong maths, good communication"_ → **Record outcome**. ✅ Stage **Ready For Decision**.

**Step 3.3 — Admit.** Click **Admit**.

✅ Stage **Fee Pending** · Programme enrolment **Provisional** · roll number _"issued when the fee is received"_.
Behind the scenes: one of the 60 BE-CSE seats at Yelahanka is **reserved**, and the **annual invoice** (₹1,50,000 tuition + ₹5,000 admission fee) is issued with a 7-day payment deadline.

🗣 _"The seat is held only for 7 days. If the fee doesn't come, the nightly run releases the seat to the next student. If a DD is already with us, the admission waits on the Dean's overdue list instead."_

**Step 3.4 (optional) — A rejection.** Open **Meghana Rao** → **Reason for rejecting**: _"Below the BE CSE cut-off; offered BE ECE"_ → **Reject**. ✅ Stage **Application Decision**, decision _Reject_.

---

## Stage 4 — Fee payment: no cash, DD clears through the bank

👤 **Andrea Advancement** · KTEdutech app

**Step 4.1 — Find the invoice.** **Invoices** tab → open Ravi's invoice (Learner: _Ravi Kumar [KEM College]_, total ₹1,55,000).

**Step 4.2 — Try cash.** **Record payment** → Method **Cash**, amount ₹1,55,000 → **Record payment**.
✅ Refused: _"Payment method Cash is not allowed at this college campus."_
🗣 _"No cash and no bargaining — the campus only accepts DD, cheque and online payments, and discounts are switched off."_

**Step 4.3 — Demand draft.** **Record payment** → Method **Demand Draft**, Reference `DD-4512`, **DD / cheque number** `004512`, **Drawn on bank** `Canara Bank`, **DD / cheque date** today → **Record payment**.
✅ Payment recorded as **Pending** — a DD is never counted until the bank clears it.

**Step 4.4 — College dues.** **Finance Desk** tab → scroll to **College dues**: Yelahanka · BE CSE · 2026-27 → Billed ₹1,55,000, **Awaiting clearance ₹1,55,000**.

**Step 4.5 — The bank clears the DD.** **Finance Desk** → **Awaiting confirmation** → Ravi's payment → **Confirm**.

✅ Invoice **Paid**; College dues: Due ₹0.
Behind the scenes, at that moment: the seat becomes **final**, the **roll number** is issued, the programme enrolment becomes **Enrolled**, and Ravi gets an _"Admission confirmed — roll number …"_ message.

---

## Stage 5 — Admission confirmed: the roll number

👤 **Anjali Advisor** · KTEdutech → **Admissions Review** → **Ravi Kumar [KEM College]**

✅ The panel shows **Programme enrolment Enrolled · roll number KT26YBCS001**.

🗣 _"KT, year 26, Y for Yelahanka, B for BE, CS for Computer Science, 001 — the first student. Lateral-entry students start at 401, so the number itself tells you how the student joined. It never changes and is never reused."_

---

## Stage 6 — Joining: section allocation

👤 **Anjali Advisor** · App Launcher → **KT College** · in Ravi's admission click **Open programme enrolment**

**Step 6.1 — Join.** In **Section** choose **YLK · BE-CSE · 2026-27 · Y1 · A**, **Joining date** today → **Join section**.

✅ Section shown on the enrolment; **Subjects**: Engineering Mathematics I and Programming in Python (Term 1, _Draft_).

🗣 _"Ravi now appears on the class list of Section A and on the faculty's registers."_

---

## Stage 7 — Classes: timetable and attendance

👤 **Tara Teacher** · KTEdutech app

**Step 7.1 — Timetable.** **Timetable** tab → this week: Engineering Mathematics I (Mon/Wed/Fri 09:00, A-101) and the Python lab (Tue/Thu 10:00, L-201).

**Step 7.2 — Attendance.** Open today's (or the latest past) period → **Attendance register** → Ravi **Present** (or **Mark all present**) → **Save register**.

✅ Attendance recorded per period; it rolls up **by subject** for the student.

---

## Stage 8 — Marks: internal assessment and exam

👤 **Tara Teacher** · KTEdutech app → **Assessments** tab

**Step 8.1 — Internal assessment.** **New** →

| Field           | Value                                |
| --------------- | ------------------------------------ |
| Assessment Name | Maths Internal Test 1                |
| Class           | YLK · BE-CSE · 2026-27 · Y1 · A      |
| Section Subject | Engineering Mathematics I            |
| Component       | **Internal**                         |
| Assessment Type | Test · Max Score **50** · date today |

**Save** → on the assessment page (**Gradebook**) enter Ravi's score **42** → **Save draft** → **Publish results**.

**Step 8.2 — Semester exam.** **New** again: _Maths Semester Exam_, same class and section subject, Component **Exam**, Max Score **100** → **Save** → Ravi **78** → **Save draft** → **Publish results**.

✅ Marks are scaled into Ravi's subject result: internal 42/50, exam 78/100 → **120/150, Pass** (still _Draft_ — students cannot see it yet).

🗣 _"Faculty enter marks for their own subjects only; the system applies the pass rules — internal, exam and total."_

---

## Stage 9 — Results: the Dean finalises and publishes

👤 **Anjali Advisor** · App Launcher → **KT College** → **Home** → in the catalogue open the section **YLK · BE-CSE · 2026-27 · Y1 · A**

**Step 9.1 — Finalise.** In **Subject results**, Engineering Mathematics I → **Finalise**.

✅ Ravi's result **Final** — locked and visible to the student. (The term result appears once every subject of the term is final; the Python lab has no marks yet.)

**Step 9.2 (optional) — Reopen.** Click **Reopen** on Ravi's row → reason _"Recount requested by the student"_ → **Reopen result** → the result is hidden from the student again → **Finalise** again.

🗣 _"Once final, marks cannot be changed by anyone — only the Dean can reopen, with a reason that is recorded, and the student is told."_

---

## Stage 10 — The student's view

👤 **Ravi Kumar** (portal) · as Kasetti Tech: Ravi's contact → ▾ → **Log in to Experience as User** → **My Learning**

✅ The **college card**:

- Yelahanka Campus · BE Computer Science and Engineering · **Roll number KT26YBCS001** · 2026-27 · year 1 · Section A
- **Fees due ₹0**
- **Today**: today's periods with subject, room and faculty
- **Subjects**: Engineering Mathematics I — attendance %, internal 42, exam 78, **120 / 150, Pass**; Programming in Python — _Result awaited_
- Below: invoices and receipts, messages (fee received, admission confirmed), documents

🗣 _"Students see only their own record, and only marks the Dean has finalised. Parents — optional — see the same for their own child only."_

**Optional — parent view:** log in to the portal as **Suresh Shetty** (set-up guide 6.2) → he sees **Arjun** only.

---

## Stage 11 (optional) — Lateral entry

Repeat Stages 2–5 for **Kiran Patil [KEM College]** (Diploma CS 82 %, DCET 3,200 → BE CSE at Rajajinagar, entering **Year 2**).

✅ Roll number **KT26RBCS401** — R for Rajajinagar, 401 = lateral entry.

---

## Close — what happens after the demo (explain, don't click)

| Later in the year      | Who     | What the system does                                                                                                                                      |
| ---------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Fee not paid in 7 days | Nightly | Unpaid provisional admission expires; seat released; part-paid or DD-pending ones go to the **Dean's overdue list** to extend or cancel                   |
| End of the year        | Dean    | **Promote** to Year 2 (failed subjects carried as backlogs, next year's fee raised automatically), **repeat year**, or **discontinue** (roll number kept) |
| Final year             | Dean    | **Complete programme** → a verified qualification is recorded, so a KT Diploma student can apply for BE without re-entering marks                         |
| Every night            | System  | Recounts every campus's seats and reports any mismatch                                                                                                    |

---

## If something goes wrong during the demo

| Symptom                                                         | Fix                                                                                                                         |
| --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| **Next** stays disabled on _Marks and cut-off_                  | The student is not eligible for this branch: use **Switch** on a suggested branch, or check the marks and the entrance rank |
| Adam or Anjali cannot see a `[KEM College]` admission           | Not in **KEM College Admissions Team** (set-up guide step 5)                                                                |
| No **Dean** block on the admission                              | Anjali is missing **KEM College Dean** (set-up guide step 4)                                                                |
| "Verify the required documents before scheduling"               | Finish Stage 2 (all required documents **Accepted**, then Mark documents verified)                                          |
| "An outcome can be recorded only after the scheduled interview" | Schedule the interview at the current time or earlier                                                                       |
| Roll number does not appear after the DD                        | The DD is still **Pending** — confirm it in Finance Desk                                                                    |
| Ravi has no college card in the portal                          | He is not yet admitted (Stage 3), or his portal user was not created (set-up 6.1)                                           |
| A seeded student was already used in an earlier demo            | Use a new walk-in from Stage 1 for the full journey, or another seeded applicant                                            |
