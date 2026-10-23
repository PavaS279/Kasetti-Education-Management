# KT College — Set-up Guide (users and everything else)

_Do this once, before the demo. About 60 minutes. You do every step yourself as **Kasetti Tech** (System Administrator), so you see how access is built. Version 2026-10-14._

Org: `https://kasettitechnologiespvtltd.lightning.force.com` · Portal: the Experience Cloud site, page `/s/my-learning`.

**Contents**

1. What is already set up in the org
2. Check the institution set-up (campuses, programmes, cut-offs, fees, documents, timetable)
3. Allow logging in as other users
4. Staff users: give each person their college access
5. Record sharing: the admissions team
6. Student and parent portal logins
7. Final checklist
8. Reset after a demo

---

## 1. What is already set up in the org

The demo data was loaded by scripts (`scripts/seed/college/seed-college.sh`). You do **not** need to create it.

| Area             | What exists                                                                                                                                                                                  |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Campuses         | **Yelahanka Campus** (code Y) and **Rajajinagar Campus** (code R), 4 rooms each (A-101, A-102, A-103, lab L-201)                                                                             |
| Programmes       | PUC (2 years), Diploma (3 years, semesters), BE (4 years, semesters)                                                                                                                         |
| Branches         | PUC: Science PCMB, Science PCMC, Commerce, Arts · Diploma: CS, Mechanical, Electrical · BE: CSE, ECE, Mechanical, Civil                                                                      |
| Intake (2026-27) | All 11 branches at both campuses = 22 campus branches. BE: 60 regular + 6 lateral seats; others: 40 seats                                                                                    |
| Cut-offs         | 15 active admission rules (examples below)                                                                                                                                                   |
| Fees             | Annual tuition per branch + one-time admission fee ₹5,000                                                                                                                                    |
| Documents        | 8 document rules (Aadhaar, SSLC marks card, fitness certificate, study certificate, PAN, PUC marks card, Diploma certificate, rank card)                                                     |
| Curriculum       | 2 Year-1 subjects per branch; **Section A** for every campus branch                                                                                                                          |
| Timetable        | Section **YLK · BE-CSE · 2026-27 · Y1 · A**: Engineering Mathematics I (Mon/Wed/Fri 09:00–10:00, A-101) and Programming in Python lab (Tue/Thu 10:00–12:00, L-201), faculty **Tara Teacher** |
| Demo applicants  | Ravi Kumar, Meghana Rao, Sneha Gowda, Kiran Patil, Arjun Shetty (all tagged `[KEM College]`), each with an admission at _Processing_                                                         |
| Staff users      | Adam Admissions, Anjali Advisor, Andrea Advancement, Tara Teacher, Rahul Registrar — **exist already**, without college access                                                               |
| Portal users     | **None for college.** You create them in step 6                                                                                                                                              |

Cut-off examples (2026-27):

| Branch        | Route   | Needs           | Minimum | Entrance (any one)               |
| ------------- | ------- | --------------- | ------- | -------------------------------- |
| PUC Science   | Regular | SSLC            | 75 %    | —                                |
| PUC Commerce  | Regular | SSLC            | 50 %    | —                                |
| Diploma CS    | Regular | SSLC (or PUC)   | 60 %    | —                                |
| BE CSE        | Regular | PUC **Science** | 90 %    | KCET ≤ 20,000 or COMEDK ≤ 15,000 |
| BE Mechanical | Regular | PUC Science     | 65 %    | KCET or COMEDK (any rank)        |
| BE CSE        | Lateral | Diploma CS      | 75 %    | DCET ≤ 5,000                     |

Annual tuition: BE CSE ₹1,50,000 · BE ECE ₹1,30,000 · BE Mechanical/Civil ₹1,10,000 · Diploma ₹75,000 · PUC Science ₹60,000 · PUC Commerce/Arts ₹45,000.

---

## 2. Check the institution set-up (10 minutes)

Log in as **Kasetti Tech** → App Launcher → **KT College**.

| #   | Look at                                  | Where                                                                                                            | What to notice                                                                                                   |
| --- | ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| 2.1 | Campuses, programmes, branches, sections | **KT College Home** (catalogue cards at the top)                                                                 | Counts: 2 campuses, 3 programmes, 22 campus branches, 22 sections                                                |
| 2.2 | A campus                                 | Click **Yelahanka Campus**                                                                                       | Payment methods: DD, cheque, online — **no cash**; discounts not allowed                                         |
| 2.3 | Intake                                   | Click a campus branch (e.g. _BE Computer Science and Engineering_)                                               | Intake seats, reserved, finalised, _Admissions Open_                                                             |
| 2.4 | Cut-off rules                            | **Reports** → **New Report** → report type **Admission Rules** → add Branch, Entry Route, Min Percentage, Status | Each rule is a **version** (Active). Active versions are read-only, so past decisions keep the cut-off they used |
| 2.5 | Fees                                     | App Launcher → **Fee Prices** → filter Academic Year 2026-27                                                     | One _Annual_ tuition and one _Admission_ fee per branch                                                          |
| 2.6 | Documents                                | **Reports** → **New Report** → report type **Admission Document Rules**                                          | Aadhaar and PAN: _Identity_ class — the file is deleted after verification                                       |
| 2.7 | Timetable                                | KTEdutech app → **Timetable**                                                                                    | The BE-CSE Y1 A periods with Tara as faculty                                                                     |

Admission rules and document rules have no screen of their own yet (they will get Set-up Centre tiles in the single-app plan). Changing a cut-off for the demo is not needed; if you must, ask for a new rule version rather than editing the active one.

---

## 3. Allow logging in as other users (2 minutes)

You will switch between the staff users during the demo without knowing their passwords.

Setup → **Login Access Policies** → tick **Administrators Can Log in as Any User** → **Save**.

Test: Setup → **Users** → **Login** next to _Tara Teacher_ → you are now Tara → top right **Log out** returns you to Kasetti Tech.

---

## 4. Staff users: give each person their college access (15 minutes)

The staff users exist with their normal KTEdutech roles (**personas**). College work needs extra **permission sets**. Assign them yourself:

Setup → **Users** → click the user → **Permission Set Assignments** → **Edit Assignments** → move the set from _Available_ to _Enabled_ → **Save**.

| Person in the demo           | User               | Already has (persona)             | Assign now                                          | Why                                                                                                                                |
| ---------------------------- | ------------------ | --------------------------------- | --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **Admission desk** ("Admin") | Adam Admissions    | KEM Admissions Counsellor Persona | **KEM College Admissions**                          | Create college admissions, record consent, verify documents                                                                        |
| **Dean**                     | Anjali Advisor     | KEM Academic Coordinator Persona  | **KEM College Dean** + **KEM Eligibility Override** | Interview, admit/reject, overdue admissions, joining, promotion, finalise/reopen results; override a refused verdict with a reason |
| **Accounts**                 | Andrea Advancement | KEM Finance Persona               | nothing                                             | Already records payments, confirms DD/cheques and sees College dues                                                                |
| **Faculty**                  | Tara Teacher       | KEM Teacher Persona               | nothing                                             | Already faculty on the demo section                                                                                                |
| **Principal** (optional)     | Rahul Registrar    | KEM Branch Manager Persona        | nothing                                             | Read-only view of admissions, dues and results                                                                                     |

**See the difference yourself:** before assigning Anjali's sets, log in as Anjali (step 3) and open Ravi's admission → no **Dean** block. Assign **KEM College Dean**, log in again → the Dean block (interview, admit, reject) appears.

> Two layers of access: a **permission set** says _what_ a person may do. **Sharing** (next step) says _which records_ they may do it on.

---

## 5. Record sharing: the admissions team (3 minutes)

College admissions are private records. A sharing rule shares every college admission with one group, so the desk and the Dean see the same admissions whoever created them.

Setup → **Public Groups** → **KEM College Admissions Team** → **Edit** → search _Users_ → add **Adam Admissions** and **Anjali Advisor** → **Save**.

**See the difference yourself:** before adding Anjali, log in as Anjali → **Admissions Review** tab → the seeded admissions are not visible. After adding → they are.

---

## 6. Student and parent portal logins (15 minutes)

Each portal login uses one **Customer Community Plus** licence. Check first: Setup → **Company Information** → _User Licenses_ → **Customer Community Plus** → _Remaining_ must be at least 1 (2 if you also create the parent).

### 6.1 Student login — Ravi Kumar

Do this **after Act 6 of the demo script** (fee received) if you want his portal to open with a roll number; or now, to show the "pay by" state first.

1. KTEdutech app → **Accounts** → **Ravi Kumar [KEM College]** → **Edit** → **Email**: an address you can read (for example `yourname+ravi@gmail.com`) → **Save**. The portal needs an email and age 13+ (Ravi is 19).
2. On Ravi's learner page → **Portal access** card → **Give access**. This creates a portal user with:
   - profile **EDC Community User**, licence **Customer Community Plus**,
   - permission sets **Education Cloud for Experience Cloud** (`EducationCloudExprcCloudAccessPsl`) and **KEM Portal User**,
   - a welcome email sent at once.
3. Look at what was created: Setup → **Users** → **Ravi Kumar [KEM College]** (user type _Customer Community Plus_; the two permission sets).
4. Open his portal without a password: Ravi's contact record → ▾ (top right) → **Log in to Experience as User** → **My Learning**.

### 6.2 Optional parent login — Suresh Shetty (father of Arjun, PUC)

Parent access is optional for every programme.

1. **Accounts** → **Suresh Shetty [KEM College]** → add an **Email** → **Save**.
2. On Suresh's page → **Portal access** → **Give access**.
3. On the guardian link between Suresh and Arjun → tick **Portal access**.

Untick **Portal access** later and Suresh can no longer see Arjun — nothing else to remove.

### 6.3 Optional student login for Kiran Patil (lateral entry)

Same as 6.1 for **Kiran Patil [KEM College]**.

---

## 7. Final checklist

| ✔   | Check                                                                                                                                                                                |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| ☐   | Login Access Policies allow administrators to log in as users                                                                                                                        |
| ☐   | Adam has **KEM College Admissions**                                                                                                                                                  |
| ☐   | Anjali has **KEM College Dean** and **KEM Eligibility Override**                                                                                                                     |
| ☐   | Adam and Anjali are members of **KEM College Admissions Team**                                                                                                                       |
| ☐   | Log in as Adam: KT College Home shows the **Walk-in admission** card; **New college admission** opens the guided screen; Admissions Review shows the five `[KEM College]` admissions |
| ☐   | Log in as Anjali: Ravi's admission shows the **Dean** block                                                                                                                          |
| ☐   | Log in as Tara: **Timetable** shows the BE-CSE Y1 A periods                                                                                                                          |
| ☐   | Customer Community Plus licence free for Ravi (and Suresh)                                                                                                                           |
| ☐   | (Optional) Ravi's portal opens with **Log in to Experience as User**                                                                                                                 |
| ☐   | Email delivery stays **Off** (Education Setting `Email_Delivery`) unless you want real emails                                                                                        |

---

## 8. Reset after a demo

- **Portal users:** Setup → Users → edit → untick **Active** (frees the licence; history stays).
- **Permission sets and group:** remove them the same way you added them if the users go back to learning-centre work only.
- **Demo admissions:** admitted students, invoices and payments are part of the audit trail and are not deleted. For the next demo, create a new walk-in with **New college admission** (demo script Stage 1) and use the untouched seeded applicants.
- **Missing demo data:** re-run `scripts/seed/college/seed-college.sh` — it only adds what is missing.
