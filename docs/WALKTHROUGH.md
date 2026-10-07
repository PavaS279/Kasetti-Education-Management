# Kasetti Education Management — Complete Walkthrough and Demo Script

_One document to understand, set up and demonstrate the whole solution, from the first enquiry to alumni, through the eyes of every user. Last updated 2026-10-06 (Phases 0–4 complete)._

**How to use this document**

- **Part 1** explains the story, the people and the addresses you will use.
- **Part 2** is the set-up you do once before the walkthrough. Do the _Required_ items, then the _Recommended_ ones for the parts you want to show.
- **Part 3** is a map of every screen with its address and who uses it.
- **Part 4** is the walkthrough itself, in the order a real family meets the institution. Every step says **who** does it, **where** (address), **what to do**, **what you should see**, and **why it matters** in the real world.
- **Part 5** has quick automated runs, the guard rails to show, a feature index and clean-up notes.

Time needed: the full walkthrough is about 3 hours; a 45-minute highlights path is at the end of Part 1.

---

> **Operating data:** besides the `[KEM Demo]` records used below, the org now holds a realistic data set for three KT Edutech centres (64 families, 107 enrolments, July–October history). Every step below works the same on it; see [DATA-SEED.md](DATA-SEED.md) for the records to open.

## Part 1 — The story, the people and the addresses

### 1.1 The institution

**Kasetti Technologies Pvt Ltd** runs after-school learning centres (maths, coding, art) in Bengaluru. Families enquire through the website, walk-ins and referrals; children are admitted, placed in weekly classes, attend, sit tests and exams, travel on the centre bus, and families pay monthly or termly fees. Head office needs every centre to work the same way, see the numbers, and use AI safely to save staff time.

The solution runs on **Salesforce Education Cloud** in the production org _Kasetti Technologies Pvt Ltd_ (Enterprise Edition), inside the Lightning app **KTEdutech** (API name `Kasetti_Education`), plus a family portal.

### 1.2 The demo world (all records are tagged `[KEM Demo]`)

| Thing                 | Demo record                                                                                                                                                                       |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Main centre           | **[KEM Demo] Bengaluru Central** (code `DEMO-01`, invoice prefix `BLR`); second centre **[KEM Demo] Whitefield** (`DEMO-02`)                                                      |
| Courses               | **[KEM Demo] Mathematics Foundation** (termly: admission 2,000 + tuition 10,500 + workbooks 1,500 + 18% tax = 16,520); **[KEM Demo] Coding Club (Monthly)** (1,000 + 2,500/month) |
| Classes               | Maths Foundation – Saturday AM (full, used for grades and exams), Journey D2 (Mondays, has free seats), Coding Club – Weekday, Art Club – Saturday, Waitlist Demo – Sunday        |
| The Sharma family     | Father **Rohit Sharma** (fee payer, portal user), mother **Priya Sharma** (portal user), children **Ananya** (A+ student) and **Arjun** (69%, needs support)                      |
| The Iyer family       | Mother **Lakshmi Iyer** (portal user), daughter **Kavya**                                                                                                                         |
| The Nair family (new) | Mother **Lata Nair** and daughter **Meera** — referred by Rohit with his code `SHA-S8EZ`, enrolled in Coding Club                                                                 |
| Monthly billing       | **Ishaan Rao** in Coding Club with invoices BLR-000005 … BLR-000008, an instalment plan, credit notes and refunds                                                                 |
| Bus                   | Route **DEMO-R1** ([KEM Demo] Route 1 – Indiranagar) carrying Ananya, Arjun and Kavya from 1 November                                                                             |
| Exam                  | **DEMO-T1** ([KEM Demo] Term 1 Exams) with hall tickets DEMO-T1-0001 … 0003                                                                                                       |

### 1.3 The people (users and what they do)

| Role (persona)                | Demo user                                              | Permission set group                             | What they do every day                                                                                                             |
| ----------------------------- | ------------------------------------------------------ | ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| **Institution administrator** | **Kasetti Tech** (you)                                 | `KEM_Administrator_Persona`                      | Sets up centres, courses, prices; sees everything; runs operations, AI console, evaluations; also the demo class teacher           |
| **Branch manager**            | **Rahul Registrar**                                    | `KEM_Branch_Manager_Persona`                     | Runs one centre: rooms, routes, exams, approves refunds, watches retention and forecasts                                           |
| **Admissions counsellor**     | **Adam Admissions**                                    | `KEM_Admissions_Counsellor_Persona`              | Answers enquiries, follows up, converts, reviews applications, makes offers, assigns bus riders                                    |
| **Academic coordinator**      | **Anjali Advisor**                                     | `KEM_Academic_Coordinator_Persona`               | Classes, timetable, enrolments, cover for absent teachers, exams; also a teacher at the demo centre                                |
| **Teacher**                   | Kasetti Tech / Anjali (or a user you create — see 2.3) | `KEM_Teacher_Persona`                            | Takes attendance, enters marks, writes report-card comments                                                                        |
| **Finance**                   | **Andrea Advancement**                                 | `KEM_Finance_Persona`                            | Invoices, payments, reconciliation, instalments, credit notes, refunds, ERP export, referral rewards                               |
| **Guardian (parent)**         | **Rohit**, **Priya**, **Lakshmi** (portal users)       | Profile _EDC Community User_ + `KEM_Portal_User` | Sees children's timetable, attendance, results, report cards, fees, messages, documents, bus, library; pays online; refers friends |
| **Student (learner)**         | Ananya (optional portal user — see 2.3)                | same as guardian                                 | Sees own timetable, results, attendance, documents (hall ticket), library loans, bus                                               |
| **Integration (system)**      | API-only user (to create — see 2.3)                    | `KEM_Integration_Persona`                        | LMS, ERP and payment gateway calls                                                                                                 |
| **AI add-on**                 | anyone above                                           | + permission set **KEM AI User**                 | Einstein assistants and the Agentforce **KEM Staff Assistant**                                                                     |

### 1.4 Addresses (URLs)

| What                 | Address                                                                                                                                     |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Login (staff)        | `https://kasettitechnologiespvtltd.my.salesforce.com`                                                                                       |
| Lightning base (`L`) | `https://kasettitechnologiespvtltd.lightning.force.com`                                                                                     |
| The app              | App Launcher (9 dots) → **KTEdutech** (or `L/lightning/app/c__Kasetti_Education`)                                                           |
| Family portal (`P`)  | Site **TrialOrgPortal** on `https://kasettitechnologiespvtltd.my.site.com` → page **My Learning** `P/s/my-learning` (log in at `P/s/login`) |
| REST APIs            | `https://kasettitechnologiespvtltd.my.salesforce.com/services/apexrest/kem/v1/…`                                                            |

Record pages follow the pattern `L/lightning/r/<Object>/<Record Id>/view`; tabs `L/lightning/n/<Tab>`; lists `L/lightning/o/<Object>/list`. In this document `L` and `P` stand for the two base addresses above. If an address differs in your browser (for example the site uses a path prefix), use the navigation given next to it.

### 1.5 Highlights path (45 minutes)

Part 4 steps **A1** Home → **B1–B4** enquiry with AI reply and referral → **C1–C3** application with AI document reader and offer → **D1** enrolment → **E2** attendance → **E4** grades → **F1–F2** invoice and payment → **G1** bus → **G2** exam and hall ticket → **H** portal as Rohit → **I1** Agentforce → **I3** AI console.

---

## Part 2 — Set-up before you start

Status today: the solution, demo data, scheduled jobs and the Agentforce agent are deployed and active. These items are the ones only you can do (they need a browser session, a human decision or a secret).

**Checked on 2026-10-06 against the org** (each demo user's real permissions compared with every step in Part 4): R1 is done (you logged in as Rahul and Anjali); for R2, Rohit's password is set but Priya's and Lakshmi's are not; R4 is done (Document Details is on the application layout); R5 is done (agent access on the _EDC Staff User_ and _System Administrator_ profiles); the Finance Desk tab for branch managers is fixed and kept in source. Still open: R2 for Priya and Lakshmi, and R3 (no staff user except Kasetti Tech has KEM AI User yet, so their AI panels stay hidden).

### 2.1 Required (15 minutes)

| #   | What                                                 | Why                                                                                                          | How                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| --- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| R1  | **Allow administrators to log in as other users**    | You will switch between the admin, counsellor, finance and branch-manager views                              | Setup → **Login Access Policies** (`L/lightning/setup/LoginAccessPolicies/home`) → tick _Administrators Can Log in as Any User_ → Save. Then Setup → Users → **Login** next to a user.                                                                                                                                                                                                                                                                                                                                   |
| R2  | **Set passwords for the demo portal guardians**      | No passwords were set and no welcome emails were sent                                                        | Setup → **Users** (`L/lightning/setup/ManageUsers/home`) → Rohit Sharma [KEM Demo] / Priya Sharma [KEM Demo] / Lakshmi Iyer [KEM Demo] → **Reset Password** (sent to the user's email — change the email to yours first if needed). Simpler: open Rohit's contact → ▾ → **Log in to Experience as User**.                                                                                                                                                                                                                |
| R3  | **Give yourself (and demo staff) the AI assistants** | AI panels and the Agentforce actions only appear for users with **KEM AI User**. Kasetti Tech already has it | Setup → **Permission Sets** (`L/lightning/setup/PermSets/home`) → **KEM AI User** → Manage Assignments → Add: Adam Admissions, Anjali Advisor, Rahul Registrar, Andrea Advancement (and real staff later). For the Agentforce panel also assign **Access Agentforce Default Agent** (`CopilotSalesforceUser`) and **Agentforce For Education Cloud Access**, which need their permission set licences (Setup → Users → user → Permission Set License Assignments). Without KEM AI User the AI panels simply stay hidden. |
| R4  | **Show Document Details on the application**         | The AI document reader saves extra details into a new field that deployments do not add to layouts           | Setup → Object Manager → **Individual Application** → Page Layouts → drag **Document Details** onto the layout → Save.                                                                                                                                                                                                                                                                                                                                                                                                   |
| R5  | **Check the Agentforce panel**                       | The **KEM Staff Assistant** agent is active; it has only been tested from code                               | Setup → **Agents** (`L/lightning/setup/EinsteinCopilot/home`): KEM Staff Assistant = Active. In the app, open the Agentforce (Einstein) icon top right → choose **KEM Staff Assistant**.                                                                                                                                                                                                                                                                                                                                 |

### 2.2 Recommended (to show specific parts)

| #   | What                                                  | Needed for                                                                                                               | How                                                                                                                                                                                                                                                                                                                                                                                            |
| --- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| S1  | **Approve the waiting demo refund**                   | Shows the two-person refund rule                                                                                         | Log in as **Rahul Registrar** → Finance Desk → **Refunds** → RFD-000001 (1,200 on CN-000001) → **Approve**. (Kasetti Tech requested it, so cannot approve it.)                                                                                                                                                                                                                                 |
| S2  | **Online payments in Test mode** (only while demoing) | Portal **Pay online** and the staff **Simulate payment**                                                                 | Setup → **Custom Metadata Types** (`L/lightning/setup/CustomMetadata/home`) → **Education Setting** → Manage Records → `Payment_Gateway_Mode` → Value `Test`. **Set it back to `Off` afterwards.** For real payments: choose a gateway, set `Payment_Checkout_URL`, enter the webhook secret in Setup → Custom Settings → **KEM Gateway** (never in chat or tickets), try `Test`, then `Live`. |
| S3  | **Email delivery** (optional for a demo)              | Families receive emails as well as portal messages. Today emails are logged as _Not Sent_; portal messages are delivered | Setup → **Deliverability** (`L/lightning/setup/OrgEmailSettings/home`) → Access level _All email_; confirm the sender (Org-Wide Email Address); then Education Setting `Email_Delivery` = `Live`. Use real test addresses — demo guardians have `@example.com` emails.                                                                                                                         |
| S4  | **Real bus routes and exams**                         | Going live (the demo already has DEMO-R1 and DEMO-T1)                                                                    | Branch page → **Transport desk** → **New route** → **Add stop**; **Exam desk** → **New exam** → **Add paper**. There are no separate Transport/Exam tabs: the org has reached its custom tab limit.                                                                                                                                                                                            |
| S5  | **Referral reward rule**                              | Rewards for families who refer friends                                                                                   | Education Setting `Referral_Reward_Amount` (500) and `Referral_Reward_Mode` (`Manual` today; `Auto` or `Off`).                                                                                                                                                                                                                                                                                 |
| S6  | **Eligibility override** for exam staff               | Allowing a withheld exam candidate                                                                                       | Assign permission set **KEM Eligibility Override** to the coordinators who may do it (Kasetti Tech has it).                                                                                                                                                                                                                                                                                    |

### 2.3 Optional (extra viewpoints and integrations)

| #   | What                                                          | Why                                                                                                      | How                                                                                                                                                                                                                                                                                 |
| --- | ------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| O1  | **A pure teacher user**                                       | See exactly what a teacher sees (Home, Timetable, own sessions, gradebook)                               | New user (Salesforce licence, profile _EDC Staff User_) → assign permission set group **KEM Teacher Persona** (+ KEM AI User for report-comment drafts) → open Branch **[KEM Demo] Bengaluru Central** → Branch Staff → add the user as _Teacher_ → set them as teacher on a class. |
| O2  | **A student portal user**                                     | Show the learner's own view                                                                              | Person account **Ananya Sharma [KEM Demo]** → ▾ **Enable Customer User** → profile _EDC Community User_ → save; assign permission sets `EducationCloudExprcCloudAccessPsl` and `KEM_Portal_User`. Licences: 3 of 10 Customer Community Plus used.                                   |
| O3  | **Integration user**                                          | LMS, ERP and payment middleware call the REST APIs                                                       | New user (API only) → permission set group **KEM Integration Persona** → External Client App with client credentials. Keep its secret out of chat and tickets.                                                                                                                      |
| O4  | **ERP decisions**                                             | Finance export                                                                                           | Education Setting `ERP_Outbox` (On: events wait for the ERP to poll `/erp/events`; Off if only the journal export is used); map `ERP_Account_*` codes (defaults 1100/1010/1000/4000/2200/2300/4900) to your chart of accounts.                                                      |
| O5  | **Remove "Full access"** from the build's External Client App | Tighten security after the build                                                                         | Setup → External Client App Manager → the build app → OAuth scopes.                                                                                                                                                                                                                 |
| O6  | **Portal home page**                                          | The site's default `/s/` home still shows template components that fail (AssignedResource, action plans) | Experience Builder → Home → remove those components, or link the home page to **My Learning**. My Learning itself is unaffected.                                                                                                                                                    |
| O7  | **New administrators**                                        | Admins edit other people's classes through the _KEM Administrators_ group                                | After assigning KEM Administrator Persona, Home → **Operations** → **Sync administrators**.                                                                                                                                                                                         |

### 2.4 Ongoing (after go-live)

- **Review AI use monthly**: Home → **AI assistants** console (30 days) — requests, share of drafts used, edits, minutes saved, failures; re-run the **evaluation** after any prompt or model change. Decision rules are in [ai/MEASURED-BENEFIT.md](ai/MEASURED-BENEFIT.md).
- Watch Home → **Operations** for failed jobs and exception queues.

---

## Part 3 — Map of the application

### 3.1 Tabs in the KTEdutech app

| Tab                                | Address                                                                          | Who uses it                        | What it is                                                                                                                    |
| ---------------------------------- | -------------------------------------------------------------------------------- | ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| **Home**                           | `L/lightning/page/home`                                                          | Everyone (content depends on role) | Cockpit: insights, analytics, forecasts, cover desk, retention, referrals, AI console, operations, policy assistant, branches |
| **Admissions**                     | `L/lightning/n/KEM_Admissions`                                                   | Counsellors, managers              | Enquiry pipeline board (New → Contacted → Qualified…), **New enquiry**, due/overdue follow-ups, duplicates                    |
| **Admissions Review**              | `L/lightning/n/KEM_Applications`                                                 | Counsellors, managers              | Applications queue by stage                                                                                                   |
| Leads (enquiries)                  | `L/lightning/o/Lead/list`                                                        | Counsellors                        | Standard list of enquiries (create new ones from the Admissions tab, not here)                                                |
| Accounts (people)                  | `L/lightning/o/Account/list`                                                     | Staff                              | Learners and guardians (person accounts)                                                                                      |
| Learning Courses                   | `L/lightning/o/LearningCourse/list`                                              | Admin, coordinator                 | Courses with pricing                                                                                                          |
| Course Offerings (classes)         | `L/lightning/o/CourseOffering/list`                                              | Coordinator, teachers              | Classes: roster, grades, waitlist, assessments                                                                                |
| **Timetable**                      | `L/lightning/n/KEM_Timetable`                                                    | Coordinator, teachers              | Drag-and-drop weekly calendar with branch/room/teacher filters                                                                |
| Class Sessions                     | `L/lightning/o/Class_Session__c/list`                                            | Teachers                           | Individual lessons: attendance register, teacher and room                                                                     |
| Course Assessments                 | `L/lightning/o/Course_Assessment__c/list`                                        | Teachers                           | Tests and their gradebooks                                                                                                    |
| Calendar Closures                  | `L/lightning/o/Calendar_Closure__c/list`                                         | Admin                              | Holidays skipped by the timetable                                                                                             |
| Branches                           | `L/lightning/o/Branch__c/list`                                                   | Admin, managers                    | Centres — the **Branch page** holds most Phase 3–4 desks                                                                      |
| Rooms, Branch Staff                | `L/lightning/o/Room__c/list`, `L/lightning/o/Branch_Staff__c/list`               | Admin, managers                    | Rooms with capacity; staff roles per branch                                                                                   |
| **Finance Desk**                   | `L/lightning/n/KEM_Finance_Desk`                                                 | Finance, admin, managers           | Payments awaiting confirmation, reconciliation exceptions, refunds, ERP export                                                |
| Student Invoices, Student Payments | `L/lightning/o/Student_Invoice__c/list`, `L/lightning/o/Student_Payment__c/list` | Finance                            | Invoices and payments                                                                                                         |
| Fee Prices, Discounts              | `L/lightning/o/Fee_Price__c/list`, `L/lightning/o/Discount__c/list`              | Admin, finance                     | Price book and discount codes                                                                                                 |
| Reports, Dashboards                | `L/lightning/o/Report/home`, `L/lightning/o/Dashboard/home`                      | Managers, admin                    | Folder **KEM Reports**; dashboard **KEM Operations**                                                                          |
| Error Logs                         | `L/lightning/o/Error_Log__c/list`                                                | Admin                              | Technical errors captured by the platform                                                                                     |

### 3.2 Record pages and what is on them

| Page                             | Demo example (address)                                                                                                      | Panels                                                                                                                                                         |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Branch**                       | Bengaluru Central `L/lightning/r/Branch__c/a0MdN000001Y9hqUAC/view`                                                         | Branch comparison & templates, Analytics, Forecasts, Retention, Library, **Transport desk**, **Exam desk**, Referrals & alumni, Einstein summary (daily brief) |
| **Enquiry (Lead)**               | Meera Nair `L/lightning/r/Lead/00QdN00000H5ukXUAR/view`                                                                     | Enquiry workbench (follow-up, convert), **Reply with Einstein**, Einstein summary                                                                              |
| **Learner / guardian (Account)** | Ananya `L/lightning/r/Account/001dN000013Fo77QAC/view`                                                                      | **Learner 360** (guardians, applications, classes, results, fees, preferences), Einstein summary, **Progress update for the family**, Messages                 |
| **Application**                  | IA-0000000032 `L/lightning/r/IndividualApplication/0iTdN000000Ina9UAC/view`                                                 | Application workbench (checklist, eligibility, decision, offer, enrol), **AI document reader**, Einstein summary, Documents                                    |
| **Class (Course Offering)**      | Maths Saturday `L/lightning/r/CourseOffering/0P0dN00000060uzSAA/view`                                                       | Roster (invoice, transfer, withdraw), Course grades, Einstein summary, **Report-card comments**, Waitlist, Assessments                                         |
| **Course**                       | Mathematics Foundation `L/lightning/r/LearningCourse/0vYdN0000003QkLUAU/view`                                               | Course pricing                                                                                                                                                 |
| **Session**                      | Maths Saturday 10/10 `L/lightning/r/Class_Session__c/a0UdN000007kuHkUAI/view`                                               | Attendance register, Teacher and room (cover, room swap)                                                                                                       |
| **Assessment**                   | Unit Test 1 `L/lightning/r/Course_Assessment__c/a0XdN000009RzAHUA0/view`                                                    | Gradebook                                                                                                                                                      |
| **Invoice**                      | BLR-000007 `L/lightning/r/Student_Invoice__c/a0adN00000ElWkLQAV/view`                                                       | Invoice (payments, instalments, credit), Documents, Online payment links                                                                                       |
| **Credit note**                  | CN-000001 `L/lightning/r/Credit_Note__c/a0edN000009S5sQQAS/view`                                                            | Credit note (apply, refund)                                                                                                                                    |
| **Payment**                      | any payment                                                                                                                 | Documents (receipt)                                                                                                                                            |
| Exam, Route                      | DEMO-T1 `L/lightning/r/Exam__c/a0tdN00000Cr5KPQAZ/view`, DEMO-R1 `L/lightning/r/Transport_Route__c/a0wdN000000gAxRQAU/view` | Standard pages (work is done on the Branch page desks)                                                                                                         |

### 3.3 Family portal — My Learning (`P/s/my-learning`)

Learner switcher (for guardians with several children) and sections: **Timetable** (with waitlist position), **Attendance**, **Results** (course grade and report card download), **Fees** (invoices, **Pay online**, instalments, credit), **Messages** inbox, **Documents** (offer letter, invoices, receipts, report cards, hall tickets), **Library** loans, **Transport** (route, stop, times, driver), **Admission documents** (upload only, while an application is open), **Refer a friend** card, learner information.

---

## Part 4 — The walkthrough

Each step: 👤 **who** · 📍 **where** · ▶ **do** · ✅ **you should see** · 💡 **why it matters**.

### Act A — The administrator sets up the institution

#### A1. Home cockpit

👤 Administrator (Kasetti Tech) · 📍 `L/lightning/page/home`
▶ Open the app. Scroll the Home page.
✅ Greeting and quick links; seats filled and attendance gauges; receivables (outstanding, overdue, collected this month); admissions tiles; **Analytics**, **Forecasts**, **Cover Desk**, **Retention**, **Referrals and alumni**, **AI assistants** console, **Operations**, **Ask about our policies**, **Branches**.
💡 The owner sees the whole institution on one screen every morning: are classes full, is money coming in, who needs attention. Log in as Anjali (coordinator) to compare: no money cards — each role sees only what it needs.

#### A1b. Set-up Centre

👤 Administrator (or branch manager / coordinator) · 📍 Home → **Set-up Centre**
▶ Read the tiles (branches, rooms, staff roles, courses, classes, holidays, discounts, faculty, portal access); click **New** on a tile or **View all**; open a record from **Set-up gaps**.
✅ Counts for what you can see; New only where you may create; gaps such as classes without a teacher or room, unpriced courses, branches without a manager, running classes with no sessions.
💡 One place to start setting up a centre and to see what is still missing before the timetable, billing or the portal are affected.

#### A2. Centres, rooms and staff

👤 Administrator · 📍 Branch page `L/lightning/r/Branch__c/a0MdN000001Y9hqUAC/view`
▶ Look at the details (code, invoice prefix, payment terms, attendance threshold), related **Rooms** (capacity) and **Branch Staff** (roles).
✅ Branch policies drive invoice due dates, the attendance minimum for exams (75% at the demo centre) and numbering (`BLR-…`).
💡 Each centre has its own rules but the same process. A centre manager only edits their own centre.

#### A3. Courses, prices and discounts

👤 Administrator / finance · 📍 Course page `L/lightning/r/LearningCourse/0vYdN0000003QkLUAU/view`, Discounts `L/lightning/o/Discount__c/list`
▶ Open **Course pricing**: fee lines by branch, type (Admission, Tuition, Workbooks, Transport), frequency (one-time, termly, monthly), dates, tax. Open discount **SIBLING10**.
✅ Mathematics Foundation totals 16,520 with tax; SIBLING10 gives 10% (approval rules apply).
💡 Prices change every year and differ by centre; enrolments keep the price agreed on the day (a price rise never changes an existing family's bill).

#### A4. Classes and timetable

👤 Academic coordinator (Anjali) or admin · 📍 Class `L/lightning/r/CourseOffering/0P0dN00000060uzSAA/view`, **Timetable** `L/lightning/n/KEM_Timetable`
▶ On a class: capacity, teacher, room; scheduling menu → **Add weekly pattern** / **Generate sessions**. Open the Timetable, filter by branch, room or teacher, drag a session to another slot.
✅ Sessions skip closures (e.g. _Diwali break_); clashes of a teacher or room are refused with a message.
💡 Replaces the whiteboard timetable: no double-booked rooms or teachers, holidays handled automatically.

#### A5. Open a new centre from a template

👤 Administrator · 📍 Branch page → **Branch comparison** panel
▶ **New branch from this one** → name, code (e.g. `DEMO-03`), invoice prefix, choose what to copy and when classes start → **Open branch**.
✅ A new branch with copied rooms, prices, discounts, closures and Planned classes. (Whitefield and Centres P3A/P3B were opened this way.)
💡 Opening a centre takes minutes instead of days of set-up, and every centre starts with the head-office standard.

### Act B — Admissions: from enquiry to learner

#### B1. Capture an enquiry

👤 Admissions counsellor (Adam) · 📍 **Admissions** `L/lightning/n/KEM_Admissions`
▶ **New enquiry** → learner (name, birth date), guardian (name, relationship, phone/email), interest (branch, course, channel, follow-up date) → **Save enquiry**. Optional: a **Referral code** (try `SHA-S8EZ`).
✅ The card appears in **New**, assigned to a counsellor of the branch; duplicates are flagged; at least one contact detail is required. With a referral code the channel becomes _Referral_ and the enquiry is linked to Rohit.
💡 No enquiry is lost in a notebook or WhatsApp; follow-ups are due-dated; head office sees which channels bring families. Website forms and partners use the same rules through `POST /services/apexrest/kem/v1/enquiries` (with `referralCode`).

#### B2. Draft the reply with Einstein

👤 Counsellor (with KEM AI User) · 📍 The enquiry you created in B1 (the demo enquiries such as Meera Nair `L/lightning/r/Lead/00QdN00000H5ukXUAR/view` are already converted and read-only) → **Reply with Einstein**
▶ Add a note ("offer a free trial on Saturday") → **Draft reply** → edit a sentence → **Copy and record as sent** (or **Discard**).
✅ A warm, plain-text reply that uses the real class times and never invents prices; recorded as a completed task; the AI console counts it as _Edited_ or _Accepted_ with minutes saved.
💡 A counsellor answers 30 enquiries a day; a good first draft in 5 seconds saves several minutes each, and nothing is sent without a human reading it.

#### B3. Summaries and follow-up

👤 Counsellor · 📍 same enquiry → **Einstein summary**, **Log follow-up**
▶ **Summarise** → 👍; **Log follow-up** (outcome, notes, next date).
✅ A three-line summary of the conversation so far; the stage moves on; a follow-up task is created.
💡 A colleague covering the desk understands an enquiry in seconds.

#### B4. Convert to learner and guardian

👤 Counsellor · 📍 enquiry → **Convert**
▶ Keep **Create admissions application** on → **Convert**.
✅ Learner and guardian person accounts (or a match with existing ones), guardian as fee payer/emergency contact/portal access, an application; the referral moves along when the learner enrols.
💡 One click creates the family record correctly — no retyping, no duplicate parents.

#### B5. Learner 360

👤 Any staff · 📍 Ananya `L/lightning/r/Account/001dN000013Fo77QAC/view`
▶ Tabs **Overview · Applications · Classes · Results · Fees · Preferences**; **Guardians** list; **Messages** panel.
✅ Everything about the child on one page: siblings (Arjun), both parents with their roles, attendance rate, grades, balance.
💡 When a parent calls, staff answer from one screen.

### Act C — Applications, documents and offers

#### C1. Checklist and eligibility

👤 Counsellor · 📍 **Admissions Review** `L/lightning/n/KEM_Applications` → an application (e.g. IA-0000000032 `L/lightning/r/IndividualApplication/0iTdN000000Ina9UAC/view`)
▶ **Accept** required documents (birth certificate, address proof, photo ID), **Waive** optional ones; see **Eligibility** (age rule, with override).
✅ _Ready for decision_ is refused until the required items are accepted or waived.
💡 Consistent admissions: every centre checks the same documents and age rules.

#### C2. AI document reader (extraction)

👤 Counsellor (KEM AI User) · 📍 application → **AI document reader**
▶ **Paste text** of a transfer certificate or choose a PDF → **Read** → review the proposals next to the current values (blanks ticked, conflicts not ticked, another parent's details locked) → correct one value → **Apply**.
✅ Address, previous school, dates etc. filled in; extra facts saved in **Document Details**; health, religion, caste, income and ID numbers are never extracted; the console records how many values staff corrected.
💡 Typing data from certificates is slow and error-prone; AI proposes, staff decide.

#### C3. Decision and offer letter

👤 Counsellor / manager · 📍 application → **Submit for review** → **Ready for decision** → **Decide**
▶ Decision **Admit**, offer valid 14 days → **Record decision**; then **Record acceptance**.
✅ Offer **Offered** with expiry; an **Offer Letter PDF** appears in **Documents** within a minute; acceptance after expiry is refused; **Enrol in class** appears.
💡 Professional, consistent offer letters; offers that lapse free the seat for someone else.

### Act D — Enrolment and changes

#### D1. Enrol with the agreed price

👤 Counsellor / coordinator · 📍 application → **Enrol in class**
▶ Choose **[KEM Demo] Journey D2** → see the price breakdown (try `SIBLING10`) → **Confirm enrolment**.
✅ Application **Enrolled**; the class roster shows the learner with the agreed total and billing _Not Invoiced_; a full class is refused.
💡 Seat control prevents over-booking; the agreed price is frozen for the family.

#### D2. Waitlist

👤 Coordinator · 📍 Class _Waitlist Demo – Sunday_ (Course Offerings list) → **Waitlist** panel
▶ **Join waitlist** (priority, discount code); on an offered entry **Accept** / **Decline**.
✅ A freed seat is held 48 hours for the next learner and the family is told; if they decline or the hold expires, the seat passes on.
💡 Popular classes fill fairly and automatically, without phone calls in the evening.

#### D3. Transfer

👤 Coordinator · 📍 Class roster → ▾ **Transfer to another class**
▶ Pick a class → preview current vs new price and the billing effect → confirm.
✅ Old enrolment _Withdrew (Transferred to …)_, new one linked; a cheaper class after invoicing creates a credit note.
💡 Families change days or levels; the money follows correctly.

### Act E — Teaching: timetable, attendance, cover, grades, exams marks

#### E1. My week

👤 Teacher · 📍 **Timetable** `L/lightning/n/KEM_Timetable` → **My sessions**
▶ Click a session → drawer → **Attendance**.
✅ The teacher's own sessions for the week.

#### E2. Attendance register

👤 Teacher · 📍 Session `L/lightning/r/Class_Session__c/a0UdN000007kuHkUAI/view` (registers open one hour before the start; for a live demo add a session starting now — Class → menu → add a make-up session)
▶ **Mark all present** → set one learner **Late** with minutes → note → **Save register**.
✅ Session **Completed**; attendance rates update; corrections after saving are audited; low attendance raises alerts and retention risk.
💡 Attendance feeds parents' portal, exam eligibility and the at-risk list — taken once, used everywhere.

#### E3. Teacher absent → cover

👤 Coordinator · 📍 Home → **Cover Desk**; session → **Teacher and room**
▶ **Report absence** (teacher, date, reason) → ranked suggestions → **Assign**; on a session **Change room**.
✅ Suggestions ranked by free time, experience with the course and load; families of cancelled sessions are told; rooms offered must be big enough.
💡 A sick teacher at 7 am no longer means a cancelled class.

#### E4. Tests and the gradebook

👤 Teacher · 📍 Class → **Assessments** → **New** (e.g. _Unit Quiz_, out of 20) → assessment page (e.g. `L/lightning/r/Course_Assessment__c/a0XdN000009RzAHUA0/view`)
▶ Enter scores → **Save draft** → **Publish results**.
✅ Live percentage and grade (A+ ≥ 90, A ≥ 80, …); published results lock and appear in Learner 360 and the portal; 25 out of 20 is refused.
💡 Marks are entered once and reach parents immediately and correctly.

#### E5. Course grades, AI comments and report cards

👤 Teacher / coordinator · 📍 Class Maths Saturday → **Course grades**, **Report-card comments**
▶ See weights and weighted scores (Ananya 92.67 A+, Arjun 69.00 C, Kavya 85.00 A). In **Report-card comments** → **Draft with Einstein** for a learner → edit → **Save comment**. **Reopen** with a reason → change a weight → **Finalise & issue report cards**.
✅ Report card PDFs filed and families notified; reopening supersedes old cards.
💡 Writing 30 personal comments takes an evening; drafts grounded in the child's real marks and attendance cut that to minutes.

#### E6. Progress update to the family

👤 Teacher / counsellor (KEM AI User) · 📍 Ananya → **Progress update for the family**
▶ **Draft progress update** → edit → **Send to family**.
✅ A short, factual update sent as a portal message to the fee payer.
💡 Parents hear good news, not only problems — and staff do it in a minute.

### Act F — Finance

#### F1. Invoice

👤 Finance (Andrea) · 📍 Class roster → ▾ **Create invoice**
▶ Create for a learner with billing _Not Invoiced_.
✅ Invoice **BLR-…** to the fee-paying guardian, due date from the branch policy, lines with tax, an **Invoice PDF**; enrolment billing **Invoiced**.
💡 Invoices go to the right parent with the agreed price and branch numbering — no spreadsheets.

#### F2. Payments and reconciliation

👤 Finance · 📍 Invoice (e.g. BLR-000007 `L/lightning/r/Student_Invoice__c/a0adN00000ElWkLQAV/view`) → **Record payment**; **Finance Desk** `L/lightning/n/KEM_Finance_Desk`
▶ Record UPI 6,000 (funds received) → receipt; record a cheque (not yet received) → Finance Desk → **Awaiting confirmation** → **Confirm**. Overpay an invoice → **Reconciliation exceptions** → **Hold as credit** or **Close** with a note.
✅ Oldest-due-first allocation, receipts **RCT-…** with PDF, invoice Partially Paid → Paid, exceptions queued.
💡 Every rupee is matched to an invoice; the month-end bank reconciliation is a queue, not a hunt.

#### F3. Monthly billing and instalments

👤 Finance · 📍 Invoice BLR-000005 (Ishaan, Coding Club) `L/lightning/r/Student_Invoice__c/a0adN00000ElVebQAF/view`; Home → **Operations** → _KEM Recurring Billing_
▶ See "Tuition (Sep 2026)" lines and the **Instalments** panel. On an issued invoice → **Pay in instalments** → 3, monthly → **Create plan**.
✅ The nightly job bills each month (including bus fees) automatically; instalments are settled in order; reminders before and after the due date.
💡 Monthly courses bill themselves; families who need to spread a term fee can, under control.

#### F4. Credit notes and refunds

👤 Finance; Branch manager approves · 📍 Paid invoice → **Issue credit note**; Credit note CN-000001 `L/lightning/r/Credit_Note__c/a0edN000009S5sQQAS/view`; Finance Desk → **Refunds**
▶ Issue a withdrawal credit → **Request refund** 800 (auto-approved under 1,000) → **Mark paid**; request 1,200 → waits for another person → Rahul **Approves** (RFD-000001).
✅ Credit applied automatically to the next invoice; refunds above the limit need a second person.
💡 Fair refunds with fraud control (nobody approves their own refund).

#### F5. Online payment (Test mode — set-up S2)

👤 Guardian, then finance · 📍 Portal → Fees → **Pay online**; invoice page → **Online payment**
▶ Pay online as Rohit → staff **Simulate payment** on the link.
✅ "Test mode: payment request PL-… was created. No money is taken." → payment recorded, invoice Paid, receipt and notice.
💡 Parents pay from their phone; the gateway confirms through a signed webhook. Set the mode back to `Off`.

#### F6. Referral reward

👤 Finance · 📍 Home or Branch page → **Referrals and alumni**
▶ On Meera Nair's referral (Rohit) — already **Rewarded** with CN-000004 (500). For a new one: **Grant reward** or **Not eligible** with a note.
✅ A credit note for the referrer used on their next invoice; the _Referral Reward_ message; a second grant is refused.
💡 Word of mouth is the cheapest admissions channel; rewarding it consistently grows it.

#### F7. ERP export

👤 Finance · 📍 Finance Desk → **ERP export**
▶ Choose dates (≤ 92 days) → **Preview** → **Export CSV** → **Download**.
✅ A balanced journal (debits = credits) of invoices, payments, credit notes and refunds per branch.
💡 The accountant imports one file instead of re-keying hundreds of receipts.

### Act G — Running the centre (branch manager)

All on the Branch page `L/lightning/r/Branch__c/a0MdN000001Y9hqUAC/view` unless stated.

#### G1. Transport (bus routes)

👤 Branch manager (Rahul) / counsellor · 📍 **Transport desk**
▶ Select route **DEMO-R1** → manifest (stops, times, riders, payer phones) → **Print**. **Add learner** (search, stop, direction, start date next month, charge fee) → **Message families** ("Bus 15 minutes late on Monday"). **New route** / **Add stop** for a new one.
✅ Seats counted (a full route refuses riders); a monthly **Transport** fee line billed with the class from the start date; one message per family naming all their children; the portal **Transport** section shows route, stop and times.
💡 The driver gets a correct list, parents get one clear message, and bus fees are never forgotten on the invoice.

#### G2. Exams and hall tickets

👤 Branch manager / coordinator · 📍 **Exam desk** (exam **DEMO-T1**)
▶ **New exam** → **Add paper** (class, date, time, marks) → **1. Register candidates** → **2. Check eligibility** (attendance below the minimum or overdue fees → Withheld with the reason; **Allow** with KEM Eligibility Override) → **3. Allocate seats** (choose rooms) → **4. Issue hall tickets**. Then **Enter marks** → **Save marks** → **Publish to gradebook**.
✅ Hall ticket PDFs (candidate, seat "[KEM Demo] Room 101-01", papers, instructions) on the candidate and in the family's portal documents; withheld families told why; published marks become an _Exam_ assessment in the class gradebook; exam **Results Published**.
💡 Exam season paperwork (lists, seating, tickets, mark sheets) done in minutes, with fair, rule-based eligibility.

#### G3. Library

👤 Branch staff · 📍 **Library** desk
▶ **Catalogue** → search "kalam" → **Issue** to a learner; **On loan** → **Renew** / **Return** / **Lost**; **Fines** → **Paid** / **Waive**.
✅ Due dates, renewals (max 2), late fines; a learner with an overdue item cannot borrow.
💡 Books and robotics kits come back; families see loans in the portal.

#### G4. Retention

👤 Branch manager · 📍 Home or Branch → **Retention**
▶ **At risk** list with reasons → **Log follow-up** (Contacted needs a note; Retained). **Re-enrolment** → select learners whose class ends soon → **Send invitations**.
✅ Risk from attendance, scores and unpaid fees; follow-up tasks; invitations as portal messages.
💡 Keeping a family is cheaper than finding a new one; the system tells you whom to call this week.

#### G5. Analytics, comparison and forecasts

👤 Branch manager / admin / finance · 📍 Home or Branch → **Analytics**, **Branch comparison**, **Forecasts**
▶ Switch branch and period; **Show as table**. In Forecasts choose 3 or 6 months → **Explain with Einstein**.
✅ Invoiced vs collected, enrolment flow, attendance trend, retention cohorts, ageing; forecast of enrolments, seats (short/OK per course), invoicing and expected cash, with accuracy or "not enough history" and the basis used.
💡 Decide early whether to open another batch or chase collections — before the problem shows in the bank.

#### G6. Alumni

👤 Counsellor / manager · 📍 **Referrals and alumni** → Alumni
▶ Select alumni who allow contact → **Invite selected** with a short message.
✅ Learners who completed their last class become alumni; invitations include their own referral code.
💡 Former students are the best ambassadors for new courses.

### Act H — The family (portal)

👤 Guardian **Rohit Sharma** · 📍 `P/s/my-learning` (set-up R2)

| Step | Do                                                     | You should see                                                                                                                                                                              | Why                                                     |
| ---- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| H1   | Choose **Ananya**, then **Arjun**                      | Rohit sees both children; Priya sees only Ananya; Lakshmi sees only Kavya                                                                                                                   | Strict privacy: each family sees only its own children  |
| H2   | **Timetable**                                          | Upcoming sessions, cancellations, waitlist position                                                                                                                                         | Parents plan the week                                   |
| H3   | **Attendance**                                         | Rate and history                                                                                                                                                                            | Parents see absences the same day                       |
| H4   | **Results**                                            | Course grade (A+ Final) and **Report card** download                                                                                                                                        | No paper report cards to lose                           |
| H5   | **Fees**                                               | Invoices, balance, **Pay online** (Test mode), instalments, credit                                                                                                                          | Transparent fees; pay from the phone                    |
| H6   | **Messages**                                           | Invoice, payment, reminders, transport notice, hall ticket, referral reward, progress update                                                                                                | One inbox for everything the school sends               |
| H7   | **Documents**                                          | Offer letter, invoices, receipts, report cards, **hall ticket** PDF                                                                                                                         | Download any document any time                          |
| H8   | **Transport**                                          | Route, stop, pick-up and drop times, vehicle, driver                                                                                                                                        | Parents know where and when                             |
| H9   | **Library**                                            | Loans, due dates, fines                                                                                                                                                                     | —                                                       |
| H10  | **Refer a friend**                                     | Code `SHA-S8EZ`, referred 1, joined 1, reward 500                                                                                                                                           | Parents bring friends and are rewarded                  |
| H11  | **Admission documents** (while an application is open) | Each document with its status and a file picker; after an upload it reads _Sent – awaiting review_; staff see the file on the application checklist with **View**; no accept or reject here | Families send certificates from home; only staff decide |

Negative: asking for another family's learner or document → "You do not have access to this learner." / "Document not found or not available to you."

### Act H′ — The student (portal, set-up O2)

👤 Learner **Ananya** · 📍 `P/s/my-learning`
▶ Open each section.
✅ Only her own information: timetable, attendance, results, report card, hall ticket, library loans and bus.
💡 Older students take ownership of their own learning.

### Act I — AI and the Agentforce staff assistant

#### I1. KEM Staff Assistant (Agentforce)

👤 Any staff with KEM AI User · 📍 Agentforce panel (top right) → **KEM Staff Assistant** (set-up R5)
▶ Ask: "How is Ananya Sharma doing?", "Draft a reply to Demo Learner D2 offering a trial", "How is branch demo-01 doing?", "Which learners are at high risk of leaving?", "How many enrolments should we expect next quarter, and will we have enough seats?", "Can I approve a refund I requested myself?"
✅ Answers come from six read-only actions that run with the user's own access (progress summary, enquiry draft, branch brief, at-risk list, forecast, policy answer with sources); the agent cannot send or change anything.
💡 Staff ask questions in plain language instead of hunting through reports.

#### I2. Policy assistant

👤 Any staff · 📍 Home → **Ask about our policies**
▶ "How many days do families have to pay an invoice?" then "What is the hostel curfew?"
✅ The number of days from the live settings, with its sources; for the curfew: "I could not find this in the institution's policies…".
💡 Consistent answers to parents; the assistant admits what it does not know instead of inventing.

#### I3. AI console, evaluation and switches

👤 Administrator · 📍 Home → **AI assistants** (console)
▶ Choose 30 days; read per-feature figures; **Run evaluation**.
✅ Requests, staff using AI, Agentforce actions, share of drafts used, average edit, minutes saved, response time, failures; latest evaluation (11 of 11 passing). Switches: Education Setting `AI_Enabled` and `AI_Disabled_Features`.
💡 AI is measured, not assumed: keep what helps, fix or switch off what does not. Report: [ai/MEASURED-BENEFIT.md](ai/MEASURED-BENEFIT.md).

### Act J — Operations, reports and integrations (administrator)

#### J1. Operations console

👤 Administrator · 📍 Home → **Operations**
▶ Health banner, queues (e.g. 1 refund awaiting approval), scheduled jobs (recurring billing, payment reminders, library and the others) with next run and **Run now**, background runs, recent errors, **Sync administrators**.
💡 One place to see that the nightly work happened.

#### J2. Reports and dashboard

👤 Managers · 📍 Dashboards → **KEM Operations**; Reports → folder **KEM Reports**
▶ Admissions funnel, applications by status, class occupancy, attendance, receivables, collections by method.
💡 Standard Salesforce reporting on top of the same data — anyone can build more.

#### J3. Integrations (set-up O3)

👤 Integration user · 📍 REST client against `…/services/apexrest/kem/v1/…`
▶ `POST /enquiries` (website forms), `POST /payments` (gateway), LMS: `GET /lms/classes?branch=DEMO-01`, `/lms/classes/{id}/roster`, `POST /lms/grades`, `GET /lms/events` + `POST /lms/events/ack`; ERP: `GET /erp/journal?from=…&to=…&format=csv`, `GET /erp/events`.
✅ 201/200 responses; duplicates detected (`duplicate: true`); staff without the integration permission get 403.
💡 The LMS, ERP and payment gateway connect through documented, secure APIs, not manual exports.

---

## Part 5 — Reference

### 5.1 Automated runs (from the repository, org connected with `./scripts/ci/sf-login.sh`)

| Run                      | Command                                | Checks | Last result      |
| ------------------------ | -------------------------------------- | ------ | ---------------- |
| Phase 1 learner journey  | `scripts/demo/full-journey.sh <tag>`   | 23     | all passed       |
| Phase 2 operations       | `scripts/demo/phase2-journey.sh <tag>` | 31     | all passed (P2A) |
| Phase 3 new centre, APIs | `scripts/demo/phase3-journey.sh <tag>` | 26     | 26/26 (P3B)      |
| Phase 4 AI and expansion | `scripts/demo/phase4-journey.sh <tag>` | 31     | 31/31 (P4A)      |

Each run creates its own tagged `[KEM Demo]` records, so runs never collide.

### 5.2 Guard rails worth showing

| Try                                                             | Expected                                                                      |
| --------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Enquiry with no phone or email                                  | "Enter at least one email address or phone number…"                           |
| Enrol into the full Maths Saturday class                        | Refused: class is Full                                                        |
| Ready for decision with checklist incomplete                    | "All required checklist items must be accepted or waived first."              |
| Register for a session starting tomorrow                        | "Attendance can be taken from one hour before the session starts."            |
| 25 marks out of 20; edit published results                      | "Score cannot exceed the maximum"; read-only                                  |
| Payment on a Draft invoice                                      | "Payments can only be taken against issued invoices."                         |
| Approve your own refund                                         | "A refund must be decided by someone other than the person who requested it." |
| Assign a learner to a full route, or twice                      | "Route … is full" / "… already rides …"                                       |
| Allow a withheld exam candidate without the override permission | "Only staff with KEM Eligibility Override can allow a withheld candidate."    |
| Grant the same referral reward twice                            | "This referral has already been rewarded."                                    |
| Pay online while payments are Off                               | "Online payments are not available yet. Please pay at the branch."            |
| A user without KEM AI User                                      | No AI panels; Agentforce actions refuse                                       |
| Coordinator (Anjali) on Home                                    | No receivables, no Finance Desk                                               |

### 5.3 Feature index

| Feature                                     | Where                                 | Who                                     | Detailed guide                                                                            |
| ------------------------------------------- | ------------------------------------- | --------------------------------------- | ----------------------------------------------------------------------------------------- |
| Enquiries, follow-ups, conversion           | Admissions tab, Enquiry page          | Counsellor                              | [F1.1](features/F1.1-enquiries.md)                                                        |
| Learners & guardians, Learner 360           | Account page                          | All staff                               | [F1.2](features/F1.2-learners-guardians.md)                                               |
| Applications, checklist, offers             | Admissions Review, Application page   | Counsellor                              | [F1.3](features/F1.3-applications.md)                                                     |
| Prices and discounts                        | Course page, Fee Prices, Discounts    | Admin, finance                          | [F1.4](features/F1.4-pricing-discounts.md)                                                |
| Enrolment and seats                         | Application, Class roster             | Counsellor, coordinator                 | [F1.5](features/F1.5-enrolment.md)                                                        |
| Timetable                                   | Timetable tab, Class page             | Coordinator, teacher                    | [F1.6](features/F1.6-scheduling.md)                                                       |
| Attendance                                  | Session page                          | Teacher                                 | [F1.7](features/F1.7-attendance.md)                                                       |
| Assessments                                 | Assessment page                       | Teacher                                 | [F1.8](features/F1.8-assessments.md)                                                      |
| Invoices, payments, reconciliation          | Invoice page, Finance Desk            | Finance                                 | [F1.9](features/F1.9-billing.md)                                                          |
| PDFs (offer, invoice, receipt)              | Documents panels                      | All                                     | [F1.10](features/F1.10-documents.md)                                                      |
| Portal                                      | My Learning                           | Families                                | [F1.11](features/F1.11-portal.md), [F2.8](features/F2.8-richer-portal.md)                 |
| Dashboards                                  | Home, Dashboards                      | Managers                                | [F1.12](features/F1.12-dashboards.md)                                                     |
| Waitlists, transfers                        | Class page                            | Coordinator                             | [F2.1](features/F2.1-waitlists.md), [F2.2](features/F2.2-transfers.md)                    |
| Recurring billing, instalments              | Invoice page, Operations              | Finance                                 | [F2.3](features/F2.3-recurring-billing-instalments.md)                                    |
| Credit notes, refunds                       | Credit note page, Finance Desk        | Finance, manager                        | [F2.4](features/F2.4-credit-notes-refunds.md)                                             |
| Messaging                                   | Learner page → Messages               | Staff                                   | [F2.5](features/F2.5-messaging.md)                                                        |
| Teacher cover, room swaps                   | Home → Cover Desk, Session page       | Coordinator                             | [F2.6](features/F2.6-resource-substitution.md)                                            |
| Grades and report cards                     | Class → Course grades                 | Teacher                                 | [F2.7](features/F2.7-advanced-grading.md)                                                 |
| Operations console                          | Home → Operations                     | Admin                                   | [F2.9](features/F2.9-operations-console.md)                                               |
| New centre from a template, comparison      | Branch page                           | Admin                                   | [F3.1](features/F3.1-multi-branch-templates.md)                                           |
| LMS API / ERP export                        | REST, Finance Desk                    | Integration, finance                    | [F3.3](features/F3.3-lms-integration.md), [F3.4](features/F3.4-erp-export.md)             |
| Analytics, retention                        | Home, Branch page                     | Managers                                | [F3.5](features/F3.5-advanced-analytics.md), [F3.6](features/F3.6-retention-workflows.md) |
| Online payments                             | Portal, Invoice page                  | Families, finance                       | [F3.7](features/F3.7-online-payments.md)                                                  |
| Library                                     | Branch page                           | Branch staff                            | [F3.8](features/F3.8-library.md)                                                          |
| AI foundation and console                   | Home → AI assistants                  | Admin                                   | [F4.1](features/F4.1-ai-foundation.md)                                                    |
| AI replies, summaries, comments, policy Q&A | Enquiry, Learner, Class, Branch, Home | Staff with KEM AI User                  | [F4.2–F4.5](features/F4.2-F4.5-ai-assistants.md)                                          |
| Agentforce staff assistant                  | Agentforce panel                      | Staff with KEM AI User                  | [F4.6](features/F4.6-agentforce-staff-assistant.md)                                       |
| Document extraction                         | Application page                      | Counsellor                              | [F4.7](features/F4.7-document-extraction.md)                                              |
| Forecasts                                   | Home, Branch page                     | Managers, finance                       | [F4.8](features/F4.8-forecasting.md)                                                      |
| Transport                                   | Branch → Transport desk; portal       | Manager, counsellor; families           | [F4.9](features/F4.9-transport.md)                                                        |
| Exams and hall tickets                      | Branch → Exam desk; portal            | Manager, coordinator, teacher; families | [F4.10](features/F4.10-exams-and-hall-tickets.md)                                         |
| Alumni and referrals                        | Home/Branch → Referrals; portal       | Manager, finance; families              | [F4.11](features/F4.11-alumni-and-referrals.md)                                           |

More: [DEMO-SCRIPT.md](DEMO-SCRIPT.md) (acceptance tests by phase), [NEXT-STEPS.md](NEXT-STEPS.md) (hand-over), [03-security-model.md](03-security-model.md) (who can do what).

### 5.4 After the demo

- Set `Payment_Gateway_Mode` back to `Off` if you changed it.
- Demo records all carry `[KEM Demo]`; paid invoices and confirmed payments cannot be deleted by design — leave them, or deactivate the demo portal users.
- Record numbers start at 0 in this org (for example CN-000000, REF-000000); this is consistent across all objects.
