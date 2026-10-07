import json, re, sys, glob, os
S = sys.argv[1]
OUT = 'force-app/main/default/layouts'
# parent -> [(relationshipName, [columns])]
WANT = {
  'Branch__c': [('Rooms__r', ['NAME', 'Room_Type__c', 'Capacity__c', 'Active__c']),
                ('Staff__r', ['User__c', 'Role__c', 'Active__c']),
                ('Classes__r', []),
                ('Closures__r', ['NAME', 'Start_Date__c', 'End_Date__c', 'Closure_Type__c']),
                ('Fee_Prices__r', ['NAME', 'Learning_Course__c', 'Fee_Type__c', 'Billing_Frequency__c', 'Amount__c', 'Active__c']),
                ('Discounts__r', ['Code__c', 'Discount_Type__c', 'Value__c', 'Active__c'])],
  'Room__c': [('Classes__r', []), ('Sessions__r', ['NAME', 'Start__c', 'Teacher_User__c', 'Status__c'])],
  'CourseOffering': [('Sessions__r', ['NAME', 'Start__c', 'Teacher_User__c', 'Room__c', 'Status__c']),
                     ('Assessments__r', ['NAME', 'Assessment_Type__c', 'Assessment_Date__c', 'Status__c']),
                     ('Waitlist__r', ['NAME', 'Learner__c', 'Status__c', 'Priority__c'])],
  'Class_Session__c': [('Attendance__r', ['NAME', 'Learner__c', 'Status__c', 'Minutes_Late__c'])],
  'Course_Assessment__c': [('Results__r', ['NAME', 'Learner__c', 'Score__c', 'Grade__c'])],
  'Exam__c': [('Papers__r', ['NAME', 'Start_Time__c', 'Duration_Minutes__c', 'Marks_Status__c']),
              ('Candidates__r', ['NAME', 'Learner_Account__c', 'Status__c', 'Seat_Number__c'])],
  'Exam_Paper__c': [('Marks__r', ['NAME', 'Candidate__c', 'Marks__c', 'Absent__c'])],
  'Exam_Candidate__c': [('Marks__r', ['NAME', 'Marks__c', 'Absent__c'])],
  'Student_Invoice__c': [('Lines__r', ['NAME', 'Description__c', 'Line_Total__c']),
                         ('Instalments__r', ['NAME', 'Due_Date__c', 'Amount__c', 'Status__c']),
                         ('Payments__r', ['NAME', 'Amount__c', 'Method__c', 'Status__c']),
                         ('Allocations__r', ['NAME', 'Amount__c', 'Allocated_On__c']),
                         ('Credit_Notes__r', ['NAME', 'Amount__c', 'Status__c'])],
  'Student_Payment__c': [('Allocations__r', ['NAME', 'Amount__c', 'Allocated_On__c']),
                         ('Credit_Notes__r', ['NAME', 'Amount__c', 'Status__c'])],
  'Credit_Note__c': [('Refunds__r', ['NAME', 'Amount__c', 'Status__c'])],
  'Transport_Route__c': [('Stops__r', ['NAME', 'Pickup_Time__c', 'Drop_Time__c', 'Active__c']),
                         ('Assignments__r', ['NAME', 'Learner_Account__c', 'Stop__c', 'Start_Date__c'])],
  'Transport_Stop__c': [('Assignments__r', ['NAME', 'Learner_Account__c', 'Start_Date__c'])],
  'Library_Item__c': [('Loans__r', ['NAME', 'Learner_Account__c', 'Due_On__c', 'Status__c'])],
  'Staff_Absence__c': [('Sessions__r', ['NAME', 'Start__c', 'Teacher_User__c', 'Status__c'])],
  'Discount__c': [('Enrolments__r', [])],
  'CourseOfferingParticipant': [('Fee_Lines__r', ['NAME', 'Fee_Type__c', 'Billing_Frequency__c', 'Unit_Amount__c']),
                                ('Invoices__r', ['NAME', 'Status__c', 'Due_Date__c']),
                                ('Session_Attendance__r', ['NAME', 'Status__c'])],
}
ANCHORS = ['</relatedLists>', '</relatedContent>', '</quickActionList>', '</platformActionList>',
           '</multilineLayoutFields>', '</miniLayout>', '</layoutSections>']
for parent, wanted in WANT.items():
    desc = json.load(open(f'{S}/desc_{parent}.json'))['result']
    rels = {c['relationshipName']: c for c in desc['childRelationships'] if c.get('relationshipName')}
    files = glob.glob(f'{OUT}/{parent}-*.layout-meta.xml')
    if not files:
        src = glob.glob(f'{S}/klay/unpackaged/unpackaged/layouts/{parent}-*.layout')
        for p in src:
            n = os.path.basename(p)[:-7]
            open(f'{OUT}/{n}.layout-meta.xml', 'w').write(open(p).read())
        files = glob.glob(f'{OUT}/{parent}-*.layout-meta.xml')
    for f in files:
        xml = open(f).read()
        present = set(re.findall(r'<relatedList>([^<]+)</relatedList>', xml))
        cdesc_cache = {}
        add = ''
        names = []
        for rel, cols in wanted:
            c = rels.get(rel)
            if not c:
                print('MISSING', parent, rel); continue
            key = f"{c['childSObject']}.{c['field']}"
            if key in present or rel in present:
                continue
            child = c['childSObject']
            if cols and child not in cdesc_cache:
                p = f'{S}/desc_{child}.json'
                cdesc_cache[child] = {x['name'] for x in json.load(open(p))['result']['fields']} if os.path.exists(p) else None
            okcols = [x for x in cols if x == 'NAME' or (cdesc_cache.get(child) is None) or x in cdesc_cache[child]]
            add += '    <relatedLists>\n'
            for col in okcols:
                add += f'        <fields>{col}</fields>\n'
            add += f'        <relatedList>{key}</relatedList>\n    </relatedLists>\n'
            names.append(rel)
        if not add:
            continue
        pos = max(xml.rfind(a) + len(a) for a in ANCHORS if a in xml)
        nl = xml.index('\n', pos) + 1
        xml = xml[:nl] + add + xml[nl:]
        open(f, 'w').write(xml)
        print(os.path.basename(f), '+', names)
