"""Declarative data model and access matrix for Kasetti Education Management.

Each object entry lists its custom fields. ``standard: True`` marks a standard
or Education Cloud object that only receives custom fields. Permission set
access strings use: C=create, E=edit, D=delete, V=view all, M=modify all.
Read access is always granted when an object is listed.
"""

# ---------------------------------------------------------------------------
# Picklist value sets shared across objects (single source of truth)
# ---------------------------------------------------------------------------
DELIVERY_MODES = ["Classroom", "Online", "Hybrid"]
FEE_TYPES = ["Tuition", "Admission", "Materials", "Assessment", "Other"]
BILLING_FREQUENCIES = ["One-time", "Monthly", "Term"]
GUARDIAN_RELATIONSHIPS = ["Mother", "Father", "Guardian", "Grandparent", "Sibling", "Other"]

OBJECTS = [
    # ------------------------------------------------------------------ Phase 0
    {
        "name": "Branch__c", "label": "Branch", "plural": "Branches", "sharing": "Read",
        "externalSharing": "Read", "history": True, "activities": False,
        "description": "A teaching centre or campus. Branch drives record ownership, policies, and reporting dimensions.",
        "fields": [
            {"name": "Branch_Code__c", "label": "Branch Code", "type": "Text", "length": 20, "unique": True, "externalId": True, "required": True,
             "help": "Short unique code, for example BLR-01. Used in integrations and data migration."},
            {"name": "Active__c", "label": "Active", "type": "Checkbox", "default": True, "track": True},
            {"name": "Branch_Manager__c", "label": "Branch Manager", "type": "Lookup", "ref": "User", "relName": "Managed_Branches", "relLabel": "Managed Branches", "track": True},
            {"name": "Email__c", "label": "Email", "type": "Email"},
            {"name": "Phone__c", "label": "Phone", "type": "Phone"},
            {"name": "Street__c", "label": "Street", "type": "TextArea"},
            {"name": "City__c", "label": "City", "type": "Text", "length": 80},
            {"name": "State__c", "label": "State/Province", "type": "Text", "length": 80},
            {"name": "Postal_Code__c", "label": "Postal Code", "type": "Text", "length": 20},
            {"name": "Country__c", "label": "Country", "type": "Text", "length": 80},
            {"name": "Operating_Hours__c", "label": "Operating Hours", "type": "Text", "length": 255,
             "help": "Human-readable opening hours, for example Mon-Sat 08:00-20:00."},
            {"name": "Delivery_Modes__c", "label": "Delivery Modes", "type": "MultiselectPicklist", "values": DELIVERY_MODES},
            {"name": "Invoice_Due_Days__c", "label": "Invoice Due Days", "type": "Number", "precision": 3, "scale": 0, "track": True,
             "help": "Days after issue that an invoice falls due. Blank uses the organisation default."},
            {"name": "Attendance_Threshold__c", "label": "Attendance Threshold", "type": "Percent", "precision": 5, "scale": 2, "track": True,
             "help": "Learners below this attendance rate are flagged. Blank uses the organisation default."},
            {"name": "Cancellation_Notice_Hours__c", "label": "Cancellation Notice (Hours)", "type": "Number", "precision": 4, "scale": 0,
             "help": "Minimum notice for learner-initiated session cancellations."},
            {"name": "Tax_Rate__c", "label": "Tax Rate", "type": "Percent", "precision": 5, "scale": 2, "track": True,
             "help": "Tax rate applied to invoice lines raised for this branch."},
            {"name": "Invoice_Prefix__c", "label": "Invoice Prefix", "type": "Text", "length": 10,
             "help": "Prefix for invoice numbers issued by this branch."},
            {"name": "External_Id__c", "label": "External ID", "type": "Text", "length": 80, "unique": True, "externalId": True},
        ],
        "validationRules": [
            {"name": "Attendance_Threshold_Range", "formula": "AND(NOT(ISBLANK(Attendance_Threshold__c)), OR(Attendance_Threshold__c < 0, Attendance_Threshold__c > 1))",
             "field": "Attendance_Threshold__c", "message": "Attendance threshold must be between 0% and 100%."},
            {"name": "Tax_Rate_Range", "formula": "AND(NOT(ISBLANK(Tax_Rate__c)), OR(Tax_Rate__c < 0, Tax_Rate__c > 1))",
             "field": "Tax_Rate__c", "message": "Tax rate must be between 0% and 100%."},
            {"name": "Invoice_Due_Days_Positive", "formula": "AND(NOT(ISBLANK(Invoice_Due_Days__c)), Invoice_Due_Days__c < 0)",
             "field": "Invoice_Due_Days__c", "message": "Invoice due days cannot be negative."},
        ],
    },
    {
        "name": "Room__c", "label": "Room", "plural": "Rooms", "sharing": "ControlledByParent", "externalSharing": "ControlledByParent",
        "description": "A bookable teaching space or virtual room belonging to a branch.",
        "fields": [
            {"name": "Branch__c", "label": "Branch", "type": "MasterDetail", "ref": "Branch__c", "relName": "Rooms", "relLabel": "Rooms"},
            {"name": "Room_Type__c", "label": "Room Type", "type": "Picklist", "values": ["Classroom", "Laboratory", "Hall", "Studio", "Virtual"], "default": "Classroom"},
            {"name": "Capacity__c", "label": "Capacity", "type": "Number", "precision": 4, "scale": 0, "required": True},
            {"name": "Equipment__c", "label": "Equipment", "type": "MultiselectPicklist",
             "values": ["Projector", "Smart Board", "Computers", "Audio System", "Video Conferencing", "Lab Equipment"]},
            {"name": "Active__c", "label": "Active", "type": "Checkbox", "default": True},
            {"name": "Meeting_Url__c", "label": "Meeting URL", "type": "Url", "help": "Permanent meeting link for virtual rooms."},
            {"name": "External_Id__c", "label": "External ID", "type": "Text", "length": 80, "unique": True, "externalId": True},
        ],
        "validationRules": [
            {"name": "Capacity_Positive", "formula": "Capacity__c <= 0", "field": "Capacity__c", "message": "Capacity must be greater than zero."},
            {"name": "Virtual_Room_Needs_Url", "formula": "AND(ISPICKVAL(Room_Type__c, 'Virtual'), ISBLANK(Meeting_Url__c))",
             "field": "Meeting_Url__c", "message": "Virtual rooms need a meeting URL."},
        ],
    },
    {
        "name": "Branch_Staff__c", "label": "Branch Staff", "plural": "Branch Staff", "sharing": "ControlledByParent",
        "externalSharing": "ControlledByParent",
        "nameField": {"label": "Assignment Number", "type": "AutoNumber", "format": "BST-{00000}"},
        "description": "Assigns a user to a branch in a role. Drives enquiry routing, branch-scoped views, and teacher allocation.",
        "fields": [
            {"name": "Branch__c", "label": "Branch", "type": "MasterDetail", "ref": "Branch__c", "relName": "Staff", "relLabel": "Staff"},
            {"name": "User__c", "label": "User", "type": "Lookup", "ref": "User", "relName": "Branch_Assignments", "relLabel": "Branch Assignments"},
            {"name": "Role__c", "label": "Role", "type": "Picklist", "required": True,
             "values": ["Admissions Counsellor", "Teacher", "Academic Coordinator", "Finance", "Branch Manager"]},
            {"name": "Active__c", "label": "Active", "type": "Checkbox", "default": True},
            {"name": "Unique_Key__c", "label": "Unique Key", "type": "Text", "length": 80, "unique": True, "systemManaged": True,
             "help": "Branch, user, and role. Prevents duplicate assignments."},
        ],
        "validationRules": [
            {"name": "User_Required", "formula": "ISBLANK(User__c)", "field": "User__c", "message": "Select the user for this branch assignment."},
        ],
    },
    {
        "name": "Fee_Price__c", "label": "Fee Price", "plural": "Fee Prices", "sharing": "Read", "externalSharing": "Read", "history": True,
        "nameField": {"label": "Price Number", "type": "AutoNumber", "format": "PRC-{00000}"},
        "description": "Price of a fee type for a course, optionally specific to a branch and delivery mode, valid for an effective date range.",
        "fields": [
            {"name": "Learning_Course__c", "label": "Course", "type": "Lookup", "ref": "LearningCourse", "relName": "Fee_Prices", "relLabel": "Fee Prices"},
            {"name": "Branch__c", "label": "Branch", "type": "Lookup", "ref": "Branch__c", "relName": "Fee_Prices", "relLabel": "Fee Prices",
             "help": "Leave blank for a price that applies to every branch. A branch-specific price takes precedence."},
            {"name": "Fee_Type__c", "label": "Fee Type", "type": "Picklist", "values": FEE_TYPES, "default": "Tuition", "required": True},
            {"name": "Delivery_Mode__c", "label": "Delivery Mode", "type": "Picklist", "values": DELIVERY_MODES,
             "help": "Leave blank for all delivery modes. A mode-specific price takes precedence."},
            {"name": "Billing_Frequency__c", "label": "Billing Frequency", "type": "Picklist", "values": BILLING_FREQUENCIES, "default": "One-time", "required": True},
            {"name": "Amount__c", "label": "Amount", "type": "Currency", "precision": 16, "scale": 2, "required": True, "track": True},
            {"name": "Effective_From__c", "label": "Effective From", "type": "Date", "required": True, "track": True},
            {"name": "Effective_To__c", "label": "Effective To", "type": "Date", "track": True},
            {"name": "Active__c", "label": "Active", "type": "Checkbox", "default": True, "track": True},
            {"name": "Description__c", "label": "Description", "type": "Text", "length": 255},
            {"name": "External_Id__c", "label": "External ID", "type": "Text", "length": 80, "unique": True, "externalId": True},
        ],
        "validationRules": [
            {"name": "Course_Required", "formula": "ISBLANK(Learning_Course__c)", "field": "Learning_Course__c", "message": "Select the course this price belongs to."},
            {"name": "Amount_Not_Negative", "formula": "Amount__c < 0", "field": "Amount__c", "message": "Amount cannot be negative."},
            {"name": "Effective_Range_Valid", "formula": "AND(NOT(ISBLANK(Effective_To__c)), Effective_To__c < Effective_From__c)",
             "field": "Effective_To__c", "message": "Effective To must be on or after Effective From."},
        ],
    },
    {
        "name": "Discount__c", "label": "Discount", "plural": "Discounts", "sharing": "Read", "externalSharing": "Read", "history": True,
        "description": "Discount code with type, value, validity, scope, and usage limits.",
        "fields": [
            {"name": "Code__c", "label": "Code", "type": "Text", "length": 30, "unique": True, "externalId": True, "required": True,
             "help": "Code entered at enrolment, for example SIBLING10. Stored in upper case."},
            {"name": "Discount_Type__c", "label": "Discount Type", "type": "Picklist", "values": ["Percentage", "Fixed Amount"], "default": "Percentage", "required": True},
            {"name": "Value__c", "label": "Value", "type": "Number", "precision": 16, "scale": 2, "required": True, "track": True,
             "help": "Percentage (0-100) or fixed amount in the org currency."},
            {"name": "Fee_Type__c", "label": "Applies to Fee Type", "type": "Picklist", "values": FEE_TYPES,
             "help": "Leave blank to apply to every fee line."},
            {"name": "Applies_To_Course__c", "label": "Applies to Course", "type": "Lookup", "ref": "LearningCourse", "relName": "Discounts", "relLabel": "Discounts"},
            {"name": "Applies_To_Branch__c", "label": "Applies to Branch", "type": "Lookup", "ref": "Branch__c", "relName": "Discounts", "relLabel": "Discounts"},
            {"name": "Valid_From__c", "label": "Valid From", "type": "Date"},
            {"name": "Valid_To__c", "label": "Valid To", "type": "Date"},
            {"name": "Active__c", "label": "Active", "type": "Checkbox", "default": True, "track": True},
            {"name": "Max_Uses__c", "label": "Maximum Uses", "type": "Number", "precision": 6, "scale": 0, "help": "Blank for unlimited."},
            {"name": "Times_Used__c", "label": "Times Used", "type": "Number", "precision": 6, "scale": 0, "systemManaged": True},
            {"name": "Requires_Approval__c", "label": "Requires Approval", "type": "Checkbox", "default": False,
             "help": "Enrolments using this discount need finance approval before invoicing."},
            {"name": "Description__c", "label": "Description", "type": "Text", "length": 255},
        ],
        "validationRules": [
            {"name": "Value_Positive", "formula": "Value__c <= 0", "field": "Value__c", "message": "Discount value must be greater than zero."},
            {"name": "Percentage_Max_100", "formula": "AND(ISPICKVAL(Discount_Type__c, 'Percentage'), Value__c > 100)", "field": "Value__c",
             "message": "A percentage discount cannot exceed 100%."},
            {"name": "Valid_Range", "formula": "AND(NOT(ISBLANK(Valid_From__c)), NOT(ISBLANK(Valid_To__c)), Valid_To__c < Valid_From__c)",
             "field": "Valid_To__c", "message": "Valid To must be on or after Valid From."},
        ],
    },
    {
        "name": "CourseOffering", "label": "Course Offering", "plural": "Course Offerings", "standard": True,
        "fields": [
            {"name": "Branch__c", "label": "Branch", "type": "Lookup", "ref": "Branch__c", "relName": "Classes", "relLabel": "Classes"},
            {"name": "Room__c", "label": "Default Room", "type": "Lookup", "ref": "Room__c", "relName": "Classes", "relLabel": "Classes"},
            {"name": "Delivery_Mode__c", "label": "Delivery Mode", "type": "Picklist", "values": DELIVERY_MODES, "default": "Classroom"},
            {"name": "Class_Status__c", "label": "Class Status", "type": "Picklist", "values": ["Planned", "Open", "Full", "In Progress", "Completed", "Cancelled"],
             "default": "Planned"},
            {"name": "Seats_Taken__c", "label": "Seats Taken", "type": "Number", "precision": 5, "scale": 0, "systemManaged": True},
            {"name": "Seats_Available__c", "label": "Seats Available", "type": "Formula", "returnType": "Number", "scale": 0,
             "formula": "IF(ISBLANK(EnrollmentCapacity), 0, EnrollmentCapacity - BLANKVALUE(Seats_Taken__c, 0))"},
            {"name": "Teacher_User__c", "label": "Teacher (User)", "type": "Lookup", "ref": "User", "relName": "Taught_Classes", "relLabel": "Taught Classes",
             "help": "The teacher's Salesforce user. Grants roster, attendance, and results access for this class."},
        ],
    },
    {
        "name": "CourseOfferingParticipant", "label": "Course Offering Participant", "plural": "Course Offering Participants", "standard": True,
        "fields": [
            {"name": "Application__c", "label": "Application", "type": "Lookup", "ref": "IndividualApplication", "relName": "Enrolments", "relLabel": "Enrolments", "systemManaged": True},
            {"name": "Branch__c", "label": "Branch", "type": "Lookup", "ref": "Branch__c", "relName": "Enrolments", "relLabel": "Enrolments", "systemManaged": True},
            {"name": "Discount__c", "label": "Discount", "type": "Lookup", "ref": "Discount__c", "relName": "Enrolments", "relLabel": "Enrolments", "systemManaged": True},
            {"name": "Discount_Approval_Status__c", "label": "Discount Approval", "type": "Picklist", "values": ["Not Required", "Pending", "Approved", "Rejected"],
             "default": "Not Required", "systemManaged": True},
            {"name": "Agreed_Subtotal__c", "label": "Agreed Subtotal", "type": "Currency", "precision": 16, "scale": 2, "systemManaged": True},
            {"name": "Agreed_Discount__c", "label": "Agreed Discount", "type": "Currency", "precision": 16, "scale": 2, "systemManaged": True},
            {"name": "Agreed_Tax__c", "label": "Agreed Tax", "type": "Currency", "precision": 16, "scale": 2, "systemManaged": True},
            {"name": "Agreed_Total__c", "label": "Agreed Total", "type": "Currency", "precision": 16, "scale": 2, "systemManaged": True},
            {"name": "Withdrawal_Reason__c", "label": "Withdrawal Reason", "type": "TextArea", "systemManaged": True},
            {"name": "Billing_Status__c", "label": "Billing Status", "type": "Picklist", "values": ["Not Invoiced", "Invoiced", "Partially Paid", "Paid"],
             "default": "Not Invoiced", "systemManaged": True},
        ],
    },
    {
        "name": "Enrolment_Fee_Line__c", "label": "Enrolment Fee Line", "plural": "Enrolment Fee Lines", "sharing": "Private",
        "nameField": {"label": "Line Number", "type": "AutoNumber", "format": "EFL-{000000}"},
        "description": "Snapshot of the price agreed at enrolment for one fee. Invoices are raised from these lines, never from the live price list.",
        "fields": [
            {"name": "Enrolment__c", "label": "Enrolment", "type": "Lookup", "ref": "CourseOfferingParticipant", "relName": "Fee_Lines", "relLabel": "Fee Lines", "systemManaged": True},
            {"name": "Fee_Price__c", "label": "Fee Price", "type": "Lookup", "ref": "Fee_Price__c", "relName": "Enrolment_Fee_Lines", "relLabel": "Enrolment Fee Lines", "systemManaged": True},
            {"name": "Fee_Type__c", "label": "Fee Type", "type": "Picklist", "values": FEE_TYPES, "systemManaged": True},
            {"name": "Billing_Frequency__c", "label": "Billing Frequency", "type": "Picklist", "values": BILLING_FREQUENCIES, "systemManaged": True},
            {"name": "Description__c", "label": "Description", "type": "Text", "length": 255, "systemManaged": True},
            {"name": "Unit_Amount__c", "label": "Unit Amount", "type": "Currency", "precision": 16, "scale": 2, "systemManaged": True},
            {"name": "Discount_Amount__c", "label": "Discount Amount", "type": "Currency", "precision": 16, "scale": 2, "systemManaged": True},
            {"name": "Tax_Rate__c", "label": "Tax Rate", "type": "Percent", "precision": 5, "scale": 2, "systemManaged": True},
            {"name": "Tax_Amount__c", "label": "Tax Amount", "type": "Currency", "precision": 16, "scale": 2, "systemManaged": True},
            {"name": "Line_Total__c", "label": "Line Total", "type": "Currency", "precision": 16, "scale": 2, "systemManaged": True},
            {"name": "Invoiced__c", "label": "Invoiced", "type": "Checkbox", "default": False, "systemManaged": True},
        ],
        "validationRules": [
            {"name": "Enrolment_Required", "formula": "ISBLANK(Enrolment__c)", "field": "Enrolment__c", "message": "A fee line must belong to an enrolment."},
        ],
    },
    {
        "name": "Error_Log__c", "label": "Error Log", "plural": "Error Logs", "sharing": "Private", "search": False,
        "nameField": {"label": "Log Number", "type": "AutoNumber", "format": "LOG-{000000}"},
        "description": "Persistent application log written asynchronously from Log_Event__e so that entries survive transaction rollback.",
        "fields": [
            {"name": "Severity__c", "label": "Severity", "type": "Picklist", "values": ["DEBUG", "INFO", "WARN", "ERROR", "FATAL"], "default": "ERROR"},
            {"name": "Source__c", "label": "Source", "type": "Text", "length": 255, "help": "Apex class and method, flow, or integration that raised the entry."},
            {"name": "Message__c", "label": "Message", "type": "LongTextArea", "length": 32768},
            {"name": "Stack_Trace__c", "label": "Stack Trace", "type": "LongTextArea", "length": 32768},
            {"name": "Exception_Type__c", "label": "Exception Type", "type": "Text", "length": 255},
            {"name": "Record_Id__c", "label": "Related Record ID", "type": "Text", "length": 18},
            {"name": "Context__c", "label": "Context", "type": "LongTextArea", "length": 32768, "help": "Serialized payload or diagnostic context."},
            {"name": "Transaction_Id__c", "label": "Transaction ID", "type": "Text", "length": 64, "externalId": True},
            {"name": "Running_User__c", "label": "Running User", "type": "Lookup", "ref": "User", "relName": "Error_Logs", "relLabel": "Error Logs"},
            {"name": "Resolved__c", "label": "Resolved", "type": "Checkbox", "default": False},
        ],
    },
    # ------------------------------------------------------------ Phase 1.1
    {
        "name": "Lead", "label": "Enquiry", "plural": "Enquiries", "standard": True,
        "fields": [
            {"name": "Branch__c", "label": "Branch", "type": "Lookup", "ref": "Branch__c", "relName": "Enquiries", "relLabel": "Enquiries"},
            {"name": "Interested_Course__c", "label": "Interested Course", "type": "Lookup", "ref": "LearningCourse", "relName": "Enquiries", "relLabel": "Enquiries"},
            {"name": "Interested_Program__c", "label": "Interested Program", "type": "Lookup", "ref": "LearningProgram", "relName": "Enquiries", "relLabel": "Enquiries"},
            {"name": "Enquiry_Channel__c", "label": "Enquiry Channel", "type": "Picklist",
             "values": ["Walk-in", "Phone", "Website", "Referral", "Social Media", "Campaign", "Event", "Other"], "default": "Phone"},
            {"name": "Preferred_Delivery_Mode__c", "label": "Preferred Delivery Mode", "type": "Picklist", "values": DELIVERY_MODES},
            {"name": "Learner_Birthdate__c", "label": "Learner Date of Birth", "type": "Date"},
            {"name": "Guardian_First_Name__c", "label": "Guardian First Name", "type": "Text", "length": 40},
            {"name": "Guardian_Last_Name__c", "label": "Guardian Last Name", "type": "Text", "length": 80},
            {"name": "Guardian_Email__c", "label": "Guardian Email", "type": "Email"},
            {"name": "Guardian_Phone__c", "label": "Guardian Phone", "type": "Phone"},
            {"name": "Guardian_Relationship__c", "label": "Guardian Relationship", "type": "Picklist", "values": GUARDIAN_RELATIONSHIPS},
            {"name": "Next_Follow_Up__c", "label": "Next Follow-up", "type": "DateTime"},
            {"name": "Last_Contacted__c", "label": "Last Contacted", "type": "DateTime"},
            {"name": "Trial_Session_Date__c", "label": "Trial Session Date", "type": "DateTime"},
            {"name": "Lost_Reason__c", "label": "Lost Reason", "type": "Picklist",
             "values": ["Price", "Schedule", "Location", "Chose Competitor", "Not Interested", "Unreachable", "Duplicate", "Other"]},
            {"name": "Possible_Duplicate__c", "label": "Possible Duplicate", "type": "Checkbox", "default": False, "systemManaged": True},
            {"name": "Duplicate_Details__c", "label": "Duplicate Details", "type": "TextArea", "systemManaged": True},
            {"name": "Converted_Learner__c", "label": "Converted Learner", "type": "Lookup", "ref": "Account", "relName": "Converted_Enquiries", "relLabel": "Converted Enquiries", "systemManaged": True},
            {"name": "Converted_Application__c", "label": "Converted Application", "type": "Lookup", "ref": "IndividualApplication", "relName": "Source_Enquiries", "relLabel": "Source Enquiries", "systemManaged": True},
            {"name": "Submission_Id__c", "label": "Submission ID", "type": "Text", "length": 80, "unique": True, "externalId": True,
             "help": "Idempotency key supplied by the website or another channel. Repeated submissions with the same key update the same enquiry."},
            {"name": "Follow_Up_Status__c", "label": "Follow-up Status", "type": "Formula", "returnType": "Text", "blanks": "BlankAsBlank",
             "formula": "IF(IsConverted, 'Converted', IF(ISBLANK(Next_Follow_Up__c), 'Not Scheduled', IF(Next_Follow_Up__c < NOW(), 'Overdue', IF(DATEVALUE(Next_Follow_Up__c) <= TODAY(), 'Due Today', 'Scheduled'))))"},
        ],
        "validationRules": [
            {"name": "KEM_Lost_Reason_Required", "formula": "AND(ISPICKVAL(Status, 'Unqualified'), ISBLANK(TEXT(Lost_Reason__c)))",
             "field": "Lost_Reason__c", "message": "Select a lost reason when marking an enquiry as Unqualified."},
            {"name": "KEM_Contact_Detail_Required", "formula": "AND(NOT(ISBLANK(Branch__c)), ISBLANK(Email), ISBLANK(Phone), ISBLANK(MobilePhone), ISBLANK(Guardian_Email__c), ISBLANK(Guardian_Phone__c))",
             "message": "Provide at least one email address or phone number for the learner or guardian."},
        ],
    },
    {
        "name": "Account", "label": "Account", "plural": "Accounts", "standard": True,
        "fields": [
            {"name": "Branch__c", "label": "Home Branch", "type": "Lookup", "ref": "Branch__c", "relName": "Accounts", "relLabel": "Learners and Guardians"},
            {"name": "KEM_Role__c", "label": "Education Role", "type": "Picklist", "values": ["Learner", "Guardian", "Learner and Guardian"],
             "help": "Whether this person is a learner, a guardian, or both."},
        ],
    },
    {
        "name": "Contact", "label": "Contact", "plural": "Contacts", "standard": True,
        "fields": [
            {"name": "Preferred_Channel__c", "label": "Preferred Channel", "type": "Picklist", "values": ["Email", "SMS", "WhatsApp", "Phone"], "default": "Email"},
            {"name": "Preferred_Language__c", "label": "Preferred Language", "type": "Picklist",
             "values": ["English", "Hindi", "Kannada", "Tamil", "Telugu", "Malayalam", "Marathi", "Bengali", "Other"], "default": "English"},
            {"name": "SMS_Opt_In__c", "label": "SMS Opt-in", "type": "Checkbox", "default": False},
            {"name": "WhatsApp_Opt_In__c", "label": "WhatsApp Opt-in", "type": "Checkbox", "default": False},
            {"name": "Emergency_Instructions__c", "label": "Emergency Instructions", "type": "LongTextArea", "length": 2000, "lines": 3,
             "help": "Medical or safety information staff must know, for example allergies or authorised pickup notes."},
        ],
    },
    {
        "name": "LearnerProfile", "label": "Learner Profile", "plural": "Learner Profiles", "standard": True,
        "fields": [
            {"name": "Student_Number__c", "label": "Student Number", "type": "AutoNumber", "format": "STU-{00000}",
             "help": "Institution-wide learner number, generated when the learner profile is created."},
            {"name": "Branch__c", "label": "Home Branch", "type": "Lookup", "ref": "Branch__c", "relName": "Learner_Profiles", "relLabel": "Learner Profiles"},
        ],
    },
    {
        "name": "IndividualApplication", "label": "Application", "plural": "Applications", "standard": True,
        "fields": [
            {"name": "Branch__c", "label": "Branch", "type": "Lookup", "ref": "Branch__c", "relName": "Applications", "relLabel": "Applications"},
            {"name": "Learning_Course__c", "label": "Learning Course", "type": "Lookup", "ref": "LearningCourse", "relName": "Applications", "relLabel": "Applications"},
            {"name": "Learning_Program__c", "label": "Learning Program", "type": "Lookup", "ref": "LearningProgram", "relName": "Applications", "relLabel": "Applications"},
            {"name": "Source_Enquiry__c", "label": "Source Enquiry", "type": "Lookup", "ref": "Lead", "relName": "Applications", "relLabel": "Applications", "systemManaged": True},
            {"name": "Requested_Offering__c", "label": "Preferred Class", "type": "Lookup", "ref": "CourseOffering", "relName": "Applications", "relLabel": "Applications",
             "help": "The class (course offering) the applicant would like to join."},
            {"name": "Reviewer__c", "label": "Reviewer", "type": "Lookup", "ref": "User", "relName": "Reviewed_Applications", "relLabel": "Reviewed Applications"},
            {"name": "Eligibility_Status__c", "label": "Eligibility", "type": "Picklist", "values": ["Not Checked", "Eligible", "Not Eligible", "Overridden"],
             "default": "Not Checked", "systemManaged": True},
            {"name": "Eligibility_Notes__c", "label": "Eligibility Notes", "type": "TextArea", "systemManaged": True},
            {"name": "Checklist_Complete__c", "label": "Checklist Complete", "type": "Checkbox", "default": False, "systemManaged": True,
             "help": "All required checklist items are accepted or waived."},
            {"name": "Decision__c", "label": "Decision", "type": "Picklist", "values": ["Admit", "Waitlist", "Reject"], "systemManaged": True},
            {"name": "Decision_Reason__c", "label": "Decision Reason", "type": "TextArea", "systemManaged": True},
            {"name": "Decision_Date__c", "label": "Decision Date", "type": "DateTime", "systemManaged": True},
            {"name": "Decided_By__c", "label": "Decided By", "type": "Lookup", "ref": "User", "relName": "Decided_Applications", "relLabel": "Decided Applications", "systemManaged": True},
            {"name": "Offer_Status__c", "label": "Offer Status", "type": "Picklist", "values": ["Not Offered", "Offered", "Accepted", "Declined", "Expired"],
             "default": "Not Offered", "systemManaged": True},
            {"name": "Offer_Expiry_Date__c", "label": "Offer Expiry Date", "type": "Date", "systemManaged": True},
            {"name": "Offer_Responded_Date__c", "label": "Offer Responded", "type": "DateTime", "systemManaged": True},
        ],
    },
    {
        "name": "LearningCourse", "label": "Learning Course", "plural": "Learning Courses", "standard": True,
        "fields": [
            {"name": "Minimum_Age__c", "label": "Minimum Age", "type": "Number", "precision": 3, "scale": 0,
             "help": "Applicants younger than this (in years, at application) are not eligible."},
            {"name": "Maximum_Age__c", "label": "Maximum Age", "type": "Number", "precision": 3, "scale": 0},
            {"name": "Entry_Requirements__c", "label": "Entry Requirements", "type": "TextArea"},
        ],
    },
    {
        "name": "ContactContactRelation", "label": "Contact Contact Relationship", "plural": "Contact Contact Relationships", "standard": True,
        "fields": [
            {"name": "Is_Fee_Payer__c", "label": "Fee Payer", "type": "Checkbox", "default": False, "help": "This guardian receives invoices for the learner."},
            {"name": "Is_Emergency_Contact__c", "label": "Emergency Contact", "type": "Checkbox", "default": False},
            {"name": "Portal_Access__c", "label": "Portal Access", "type": "Checkbox", "default": False,
             "help": "Grants this guardian portal visibility of the learner's records. Access is never inferred from household membership."},
            {"name": "Guardian_Relationship__c", "label": "Guardian Relationship", "type": "Picklist", "values": GUARDIAN_RELATIONSHIPS},
        ],
    },

]

# Standard objects that permission sets may grant object-level access to.
from edu_fields import EDU_STANDARD_FIELDS  # noqa: E402

# Standard fields that may be hidden by profiles in this org; permission sets grant them explicitly.
STANDARD_FIELD_ACCESS = {
    **EDU_STANDARD_FIELDS,
    "Lead": ["Email", "Phone", "MobilePhone", "Description", "LeadSource", "Company"],
    "Account": ["Phone", "PersonEmail", "PersonMobilePhone", "PersonBirthdate", "Description", "PersonHasOptedOutOfEmail"],
    "Contact": ["Email", "Phone", "MobilePhone", "Birthdate", "HasOptedOutOfEmail"],
}

# Object permissions that Salesforce requires alongside others (read access is added automatically).
OBJECT_DEPENDENCIES = {"ContactContactRelation": ["PartyRoleRelation"], "DocumentChecklistItem": ["ContactContactRelation"]}

EDU_CURRICULUM = ["Learning", "LearningCourse", "LearningProgram"]

STANDARD_OBJECT_PERMS = {"Learning", "LearningCourse", "LearningProgram", "PartyRoleRelation", "Lead", "Account", "Contact", "IndividualApplication", "ContactContactRelation"}

# Apex classes every staff persona needs.
COMMON_CLASSES = {
    "staff": [],
    "portal": [],
}

ENQUIRY_CLASSES = ["EnquiryController", "ApplicationController"]
LEARNER_CLASSES = ["Learner360Controller"]
PRICING_CLASSES = ["PricingController"]
ENROLMENT_CLASSES = ["EnrolmentController"]

# Education Cloud objects are only granted through permission sets tied to these licences.
STAFF_LICENSE = "EducationCloudAccessPsl"
PORTAL_LICENSE = "EducationCloudExprcCloudAccessPsl"
STAFF_APPS = ["Kasetti_Education"]

# Objects governed by the Education Cloud licences. Each persona permission set
# with a "license" is split into <name> (licence-free: custom and CRM objects,
# tabs, apps, classes, user permissions) and <name>_Edu (licensed: these objects).
EDU_OBJECTS = {
    "Learning", "LearningCourse", "LearningProgram", "LearningProgramPlan", "IndividualApplication",
    "ContactContactRelation", "PartyRoleRelation", "CourseOffering", "CourseOfferingParticipant",
    "CourseOfferingSchedule", "AcademicTerm", "AcademicSession", "LearnerProfile", "DocumentChecklistItem",
}
STAFF_TABS = ["Branch__c", "Room__c", "Branch_Staff__c", "Fee_Price__c", "Discount__c"]

PERMISSION_SETS = [
    {"name": "KEM_Administrator", "label": "KEM Administrator",
     "description": "Institution administrator: configures branches, policies, and has full access to Kasetti Education Management data.",
     "license": STAFF_LICENSE, "objects": {"Fee_Price__c": "CEDM", "Discount__c": "CEDM", "Enrolment_Fee_Line__c": "CEDM", "DocumentChecklistItem": "CEDV", "Log_Event__e": "C", "Branch_Staff__c": "CEDM", "Learning": "CEDV", "LearningCourse": "CEDV", "LearningProgram": "CEDV", "LearnerProfile": "CEDV", "CourseOffering": "CEDV", "CourseOfferingParticipant": "CEDV", "CourseOfferingSchedule": "CEDV", "Branch__c": "CEDM", "Room__c": "CEDM", "Error_Log__c": "CEDM", "Lead": "CEDV", "Account": "CEV", "Contact": "CEV",
                 "IndividualApplication": "CEDV", "ContactContactRelation": "CEDV"},
     "userPermissions": ["ConvertLeads", "EditTask"], "classes": ENQUIRY_CLASSES + LEARNER_CLASSES + PRICING_CLASSES + ENROLMENT_CLASSES, "custom": ["KEM_Approve_Discounts"], "apps": STAFF_APPS, "tabs": STAFF_TABS + ["KEM_Admissions", "KEM_Applications", "Error_Log__c"]},
    {"name": "KEM_Branch_Manager", "label": "KEM Branch Manager",
     "description": "Branch manager: manages rooms, classes, staff allocation, and learners for their branch.",
     "license": STAFF_LICENSE, "objects": {"Enrolment_Fee_Line__c": "CEV", "Fee_Price__c": "", "Discount__c": "", "DocumentChecklistItem": "CE", "CourseOffering": "CE", "CourseOfferingParticipant": "CE", "CourseOfferingSchedule": "", "LearnerProfile": "CE", "Log_Event__e": "C", "Branch_Staff__c": "CED", "Learning": "", "LearningCourse": "", "LearningProgram": "", "Branch__c": "E", "Room__c": "CED", "Lead": "CE", "Account": "CE", "Contact": "CE", "IndividualApplication": "CE",
                 "ContactContactRelation": "CE"}, "userPermissions": ["ConvertLeads", "EditTask"], "classes": ENQUIRY_CLASSES + LEARNER_CLASSES + PRICING_CLASSES + ENROLMENT_CLASSES, "apps": STAFF_APPS, "tabs": STAFF_TABS + ["KEM_Admissions", "KEM_Applications"]},
    {"name": "KEM_Admissions_Counsellor", "label": "KEM Admissions Counsellor",
     "description": "Admissions counsellor: works enquiries, applications, offers, and follow-ups.",
     "license": STAFF_LICENSE, "objects": {"Enrolment_Fee_Line__c": "CE", "Fee_Price__c": "", "Discount__c": "", "DocumentChecklistItem": "CED", "CourseOffering": "", "CourseOfferingParticipant": "CE", "CourseOfferingSchedule": "", "LearnerProfile": "CE", "Log_Event__e": "C", "Branch_Staff__c": "", "Learning": "", "LearningCourse": "", "LearningProgram": "", "Branch__c": "", "Room__c": "", "Lead": "CE", "Account": "CE", "Contact": "CE", "IndividualApplication": "CE",
                 "ContactContactRelation": "CE"}, "userPermissions": ["ConvertLeads", "EditTask"], "classes": ENQUIRY_CLASSES + LEARNER_CLASSES + PRICING_CLASSES + ENROLMENT_CLASSES, "apps": STAFF_APPS, "tabs": STAFF_TABS + ["KEM_Admissions", "KEM_Applications"]},
    {"name": "KEM_Academic_Coordinator", "label": "KEM Academic Coordinator",
     "description": "Academic coordinator: maintains curriculum, timetable, enrolments, and academic oversight.",
     "license": STAFF_LICENSE, "objects": {"Enrolment_Fee_Line__c": "CEV", "Fee_Price__c": "", "Discount__c": "", "DocumentChecklistItem": "", "Log_Event__e": "C", "Branch_Staff__c": "", "Learning": "CE", "LearningCourse": "CE", "LearningProgram": "CE", "LearnerProfile": "CE", "CourseOffering": "CE", "CourseOfferingParticipant": "CE", "CourseOfferingSchedule": "CE", "Branch__c": "", "Room__c": "CE", "Lead": "", "Account": "E", "Contact": "E", "IndividualApplication": "",
                 "ContactContactRelation": ""}, "classes": LEARNER_CLASSES + PRICING_CLASSES + ENROLMENT_CLASSES, "apps": STAFF_APPS, "tabs": STAFF_TABS},
    {"name": "KEM_Teacher", "label": "KEM Teacher",
     "description": "Teacher: views assigned classes, marks attendance, and enters assessment results.",
     "license": STAFF_LICENSE, "objects": {"Fee_Price__c": "", "Discount__c": "", "CourseOffering": "", "CourseOfferingParticipant": "", "CourseOfferingSchedule": "", "LearnerProfile": "", "Log_Event__e": "C", "Branch_Staff__c": "", "Learning": "", "LearningCourse": "", "LearningProgram": "", "Branch__c": "", "Room__c": "", "Account": "", "Contact": ""}, "classes": LEARNER_CLASSES, "apps": STAFF_APPS, "tabs": STAFF_TABS},
    {"name": "KEM_Finance", "label": "KEM Finance",
     "description": "Finance user: manages fees, invoices, payments, allocations, and reconciliation.",
     "license": STAFF_LICENSE, "objects": {"Enrolment_Fee_Line__c": "CEV", "Fee_Price__c": "CEDV", "Discount__c": "CEDV", "CourseOffering": "", "CourseOfferingParticipant": "", "CourseOfferingSchedule": "", "LearnerProfile": "", "Log_Event__e": "C", "Branch_Staff__c": "", "Learning": "", "LearningCourse": "", "LearningProgram": "", "Branch__c": "", "Room__c": "", "Account": "", "Contact": "", "ContactContactRelation": ""}, "classes": LEARNER_CLASSES + PRICING_CLASSES + ENROLMENT_CLASSES, "custom": ["KEM_Approve_Discounts"], "apps": STAFF_APPS, "tabs": STAFF_TABS},
    {"name": "KEM_Eligibility_Override", "label": "KEM Eligibility Override",
     "description": "Allows overriding a failed eligibility check on an application. Grant to administrators and branch managers.",
     "objects": {}, "custom": ["KEM_Override_Eligibility"]},
    {"name": "KEM_Portal_User", "label": "KEM Portal User", "classAccess": "portal",
     "description": "Learner or guardian portal access. Record visibility is enforced in Apex through explicit guardian relationships.",
     "license": PORTAL_LICENSE, "objects": {"Log_Event__e": "C"}},
]


# Allowed status transitions (object, field) -> list of (from, to).
TRANSITIONS = {
    ("IndividualApplication", "Status"): [
        ("Processing", "In Review"), ("Processing", "Withdrawn"), ("Processing", "Canceled"),
        ("In Review", "Processing"), ("In Review", "Ready For Decision"), ("In Review", "Withdrawn"), ("In Review", "Canceled"),
        ("Ready For Decision", "In Review"), ("Ready For Decision", "Application Decision"), ("Ready For Decision", "Withdrawn"),
        ("Application Decision", "Enrolled"), ("Application Decision", "Withdrawn"), ("Application Decision", "Enrollment Failed"),
        ("Enrollment Failed", "Enrolled"), ("Enrollment Failed", "Withdrawn"),
    ],
    ("IndividualApplication", "Offer_Status__c"): [
        ("Not Offered", "Offered"), ("Offered", "Accepted"), ("Offered", "Declined"), ("Offered", "Expired"),
        ("Expired", "Offered"), ("Accepted", "Declined"),
    ],
    ("CourseOffering", "Class_Status__c"): [
        ("Planned", "Open"), ("Planned", "Cancelled"), ("Open", "Full"), ("Full", "Open"), ("Open", "In Progress"), ("Full", "In Progress"),
        ("In Progress", "Completed"), ("Open", "Cancelled"), ("Full", "Cancelled"), ("In Progress", "Cancelled"), ("Open", "Planned"),
    ],
    ("CourseOfferingParticipant", "ParticipationStatus"): [
        ("Enrolled", "Withdrew"), ("Enrolled", "Completed"), ("Enrolled", "On Hold"), ("Enrolled", "Failed"),
        ("On Hold", "Enrolled"), ("On Hold", "Withdrew"),
    ],
    ("Lead", "Status"): [
        ("New", "Contacted"), ("New", "Nurturing"), ("New", "Unqualified"), ("New", "Qualified"),
        ("Contacted", "Nurturing"), ("Contacted", "Qualified"), ("Contacted", "Unqualified"),
        ("Nurturing", "Contacted"), ("Nurturing", "Qualified"), ("Nurturing", "Unqualified"),
        ("Unqualified", "Nurturing"), ("Unqualified", "Contacted"),
    ],
}
