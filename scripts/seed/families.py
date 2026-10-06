#!/usr/bin/env python3
"""Generates realistic KTEdutech households and their class plan (deterministic).

Writes scripts/seed/families.json, used by the stage 3-4 Apex scripts.
Emails use the reserved example.com domain so nothing can reach a real inbox.
"""
import json, random, datetime, os

random.seed(20260706)
TODAY = datetime.date(2026, 10, 6)

# Name pools by community, so first names and surnames go together.
COMMUNITIES = [
    (6, ["Iyer", "Reddy", "Nair", "Rao", "Menon", "Hegde", "Shetty", "Pillai", "Bhat", "Gowda", "Krishnan",
         "Subramaniam", "Naidu", "Prasad", "Murthy", "Acharya", "Kamath", "Pai", "Shenoy", "Srinivasan", "Chandran",
         "Raghunath", "Venkatesan", "Ramaswamy"],
     ["Lakshmi", "Deepa", "Kavitha", "Anitha", "Swathi", "Vidya", "Radhika", "Harini", "Revathi", "Gayathri", "Rashmi",
      "Nandini", "Sneha", "Divya", "Meera", "Bhavana", "Aparna", "Sowmya", "Pavithra"],
     ["Suresh", "Ramesh", "Prakash", "Kiran", "Naveen", "Srinivas", "Ravi", "Mahesh", "Ganesh", "Girish", "Venkatesh",
      "Sudhir", "Karthik", "Harish", "Satish", "Mohan", "Arun", "Raghav", "Shankar"],
     ["Aadhya", "Ananya", "Diya", "Kavya", "Saanvi", "Navya", "Meghana", "Shreya", "Vaishnavi", "Samhita", "Tanvi",
      "Nithya", "Charvi", "Ishita", "Avni"],
     ["Aarav", "Arjun", "Ishaan", "Atharv", "Advik", "Rohan", "Dhruv", "Pranav", "Rishi", "Siddharth", "Varun",
      "Aditya", "Samarth", "Tejas", "Vihaan", "Krish"]),
    (3, ["Sharma", "Kulkarni", "Patil", "Desai", "Joshi", "Agarwal", "Gupta", "Mehta", "Malhotra", "Kapoor", "Singh",
         "Jain", "Saxena", "Verma"],
     ["Priya", "Pooja", "Neha", "Sonia", "Shruti", "Sunita", "Madhuri", "Rekha", "Asha", "Shalini", "Ritu", "Kirti"],
     ["Rajesh", "Vikram", "Sanjay", "Manoj", "Amit", "Rahul", "Deepak", "Anil", "Ashok", "Vinod", "Nitin", "Gaurav"],
     ["Myra", "Riya", "Anika", "Prisha", "Kiara", "Aditi", "Ishita", "Saanvi", "Tara", "Avni"],
     ["Vivaan", "Reyansh", "Shaurya", "Kabir", "Yash", "Aryan", "Dhruv", "Krish", "Nikhil", "Advik"]),
    (1, ["Banerjee", "Chatterjee", "Mukherjee", "Das", "Bose", "Ghosh", "Sen"],
     ["Sudeshna", "Moumita", "Rituparna", "Sanchita", "Payel", "Debolina"],
     ["Sourav", "Debashish", "Arindam", "Abhijit", "Subhasis", "Indranil"],
     ["Aishani", "Anushka", "Ishani", "Rupsa", "Srijita"],
     ["Arnab", "Rishabh", "Aritra", "Sayan", "Ayush"]),
    (1, ["Fernandes", "D'Costa", "Kurian", "Varghese", "Mathews", "D'Souza", "Pereira"],
     ["Mary", "Jessy", "Reena", "Sheela", "Anita", "Lynette"],
     ["Joseph", "George", "Anthony", "Sunil", "Roshan", "Jacob"],
     ["Sara", "Annie", "Ria", "Elena", "Tara"],
     ["Ryan", "Aaron", "Joel", "Neil", "Ethan"]),
    (1, ["Khan", "Siddiqui", "Ahmed", "Shaikh", "Qureshi", "Hussain"],
     ["Fathima", "Ayesha", "Nazia", "Sana", "Rukhsar", "Shabana"],
     ["Imran", "Faisal", "Arif", "Salman", "Irfan", "Zubair"],
     ["Zara", "Inaaya", "Aliya", "Mehreen", "Zoya"],
     ["Ayaan", "Rehan", "Aamir", "Zayan", "Arham"]),
]
AREAS = {
    "IND-01": [("Indiranagar 2nd Stage", "560038"), ("Domlur Layout", "560071"), ("HAL 3rd Stage", "560075"),
               ("Jeevan Bima Nagar", "560075"), ("Old Airport Road, Kodihalli", "560008")],
    "KOR-01": [("Koramangala 4th Block", "560034"), ("Ejipura", "560047"), ("BTM Layout 1st Stage", "560029"),
               ("Koramangala 8th Block", "560095"), ("Adugodi", "560030")],
    "HSR-01": [("HSR Layout Sector 1", "560102"), ("HSR Layout Sector 6", "560102"), ("Agara", "560102"),
               ("Bellandur", "560103"), ("Haralur Road", "560102")],
}
STREETS = ["Cross", "Main Road", "Cross Road"]
SCHOOLS = ["National Public School", "Delhi Public School East", "Kendriya Vidyalaya", "Vibgyor High",
           "Greenwood High", "Inventure Academy", "Christ Academy", "Sri Kumaran Children's Home",
           "Frank Anthony Public School", "Bethany High", "The Brigade School", "Presidency School"]
LANGS = ["English", "English", "English", "Kannada", "Hindi", "Tamil", "Telugu", "Malayalam", "Bengali"]
CHANNELS = ["WhatsApp", "WhatsApp", "Email", "Phone", "SMS"]

# section: (branch, min age, max age, capacity target, term start)
CLASSES = {
    "KT-IND-ABA2-SAT": ("IND-01", 8, 11, 10, datetime.date(2026, 7, 4)),
    "KT-IND-PYT-SAT": ("IND-01", 10, 15, 10, datetime.date(2026, 7, 4)),
    "KT-IND-OLY7-SUN": ("IND-01", 12, 13, 9, datetime.date(2026, 7, 5)),
    "KT-IND-ROB-WED": ("IND-01", 11, 16, 8, datetime.date(2026, 7, 8)),
    "KT-IND-ENG-TT": ("IND-01", 8, 14, 12, datetime.date(2026, 7, 7)),
    "KT-KOR-VED-SAT": ("KOR-01", 10, 14, 8, datetime.date(2026, 7, 4)),
    "KT-KOR-SCR-SAT": ("KOR-01", 7, 10, 9, datetime.date(2026, 7, 4)),
    "KT-KOR-ART-SUN": ("KOR-01", 6, 12, 11, datetime.date(2026, 7, 5)),
    "KT-KOR-PYT-FRI": ("KOR-01", 10, 15, 7, datetime.date(2026, 7, 10)),
    "KT-HSR-ABA1-WED": ("HSR-01", 6, 8, 9, datetime.date(2026, 7, 8)),
    "KT-HSR-ROB-SAT": ("HSR-01", 11, 16, 10, datetime.date(2026, 7, 4)),
    "KT-HSR-OLY6-SAT": ("HSR-01", 11, 12, 8, datetime.date(2026, 7, 4)),
    "KT-HSR-SCR-SUN": ("HSR-01", 7, 10, 3, datetime.date(2026, 11, 15)),
}
LATE_JOINS = [datetime.date(2026, 8, 3), datetime.date(2026, 8, 17), datetime.date(2026, 9, 7), datetime.date(2026, 9, 21)]

def age_on(dob, day):
    return day.year - dob.year - ((day.month, day.day) < (dob.month, dob.day))

def phone():
    return "+91 " + random.choice(["98450", "99860", "97411", "90083", "88844", "96320", "81470"]) + " " + "%05d" % random.randint(0, 99999)

def email(first, last, n):
    return ("%s.%s%s@example.com" % (first, last, "" if n == 0 else n)).lower().replace("'", "").replace(" ", "")

seats = {s: 0 for s in CLASSES}
families, used_names, emails, used_surnames = [], set(), set(), set()
fam_no = 0
for branch, weight in (("IND-01", 27), ("KOR-01", 19), ("HSR-01", 18)):
    for _ in range(weight):
        fam_no += 1
        community = random.choices(COMMUNITIES, [c[0] for c in COMMUNITIES])[0]
        _, SURN, MOTHERS, FATHERS, GIRLS, BOYS = community
        options_last = [x for x in SURN if x not in used_surnames] or SURN
        last = random.choice(options_last)
        used_surnames.add(last)
        area, pin = random.choice(AREAS[branch])
        n = random.randint(1, 18)
        suffix = "th" if 10 <= n % 100 <= 20 else {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
        street = "No. %d, %d%s %s, %s" % (random.randint(12, 980), n, suffix, random.choice(STREETS), area)
        mother = random.choice(MOTHERS); father = random.choice(FATHERS)
        both = random.random() < 0.7
        payer_is_mother = random.random() < 0.55
        guardians = []
        for first, rel in ((mother, "Mother"), (father, "Father")):
            is_payer = (rel == "Mother") == payer_is_mother
            if not both and not is_payer:
                continue
            e = email(first, last, 0); n = 1
            while e in emails:
                e = email(first, last, n); n += 1
            emails.add(e)
            guardians.append({"first": first, "last": last, "rel": rel, "email": e, "phone": phone(),
                              "payer": is_payer, "lang": random.choice(LANGS), "channel": random.choice(CHANNELS)})
        guardians.sort(key=lambda g: not g["payer"])
        n_kids = random.choices([1, 2, 3], [0.62, 0.33, 0.05])[0]
        learners = []
        for k in range(n_kids):
            girl = random.random() < 0.5
            first = random.choice(GIRLS if girl else BOYS)
            while (first, last) in used_names:
                first = random.choice(GIRLS if girl else BOYS)
            used_names.add((first, last))
            # Pick a class with free seats at the family's centre first, then an age that fits it.
            free = [c for c, v in CLASSES.items() if v[0] == branch and seats[c] < v[3]]
            plan = []
            if free:
                main = random.choices(free, [CLASSES[c][3] - seats[c] for c in free])[0]
                lo, hi, term = CLASSES[main][1], CLASSES[main][2], CLASSES[main][4]
                age = random.randint(lo, hi)
                dob = datetime.date(term.year - age - 1, random.randint(term.month + 1, 12) if term.month < 12 else 12, random.randint(1, 28))
                picks = [main]
                if random.random() < 0.3:
                    extra = [c for c in free if c != main and CLASSES[c][1] <= age_on(dob, CLASSES[c][4]) <= CLASSES[c][2]
                             and c.split("-")[2][:3] != main.split("-")[2][:3]]
                    if extra:
                        picks.append(random.choice(extra))
                for c in picks:
                    start = CLASSES[c][4]
                    join = start if (random.random() < 0.8 or start > TODAY) else max(start, random.choice(LATE_JOINS))
                    seats[c] += 1
                    plan.append({"section": c, "join": join.isoformat()})
            else:
                age = random.randint(6, 14)
                dob = datetime.date(2026 - age, random.randint(1, 12), random.randint(1, 28))
            age = age_on(dob, TODAY)
            grade = max(1, min(10, age - 5))
            learners.append({"first": first, "last": last, "dob": dob.isoformat(), "school": "%s, Grade %d" % (random.choice(SCHOOLS), grade),
                             "classes": plan})
        families.append({"key": "KT-FAM-%03d" % fam_no, "branch": branch, "street": street, "pin": pin,
                         "guardians": guardians, "learners": learners})

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "families.json")
json.dump(families, open(out, "w"), indent=1)
print("families", len(families), "learners", sum(len(f["learners"]) for f in families),
      "enrolments", sum(len(l["classes"]) for f in families for l in f["learners"]))
print({s: n for s, n in seats.items()})
print("unplaced learners", sum(1 for f in families for l in f["learners"] if not l["classes"]))
