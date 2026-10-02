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
]

# Standard objects that permission sets may grant object-level access to.
STANDARD_OBJECT_PERMS = set()

# Apex classes every staff persona needs.
COMMON_CLASSES = {
    "staff": [],
    "portal": [],
}

STAFF_APPS = ["Kasetti_Education"]
STAFF_TABS = ["Branch__c", "Room__c"]

PERMISSION_SETS = [
    {"name": "KEM_Administrator", "label": "KEM Administrator",
     "description": "Institution administrator: configures branches, policies, and has full access to Kasetti Education Management data.",
     "objects": {"Branch__c": "CEDM", "Room__c": "CEDM", "Error_Log__c": "CEDM"},
     "apps": STAFF_APPS, "tabs": STAFF_TABS + ["Error_Log__c"]},
    {"name": "KEM_Branch_Manager", "label": "KEM Branch Manager",
     "description": "Branch manager: manages rooms, classes, staff allocation, and learners for their branch.",
     "objects": {"Branch__c": "E", "Room__c": "CED"}, "apps": STAFF_APPS, "tabs": STAFF_TABS},
    {"name": "KEM_Admissions_Counsellor", "label": "KEM Admissions Counsellor",
     "description": "Admissions counsellor: works enquiries, applications, offers, and follow-ups.",
     "objects": {"Branch__c": "", "Room__c": ""}, "apps": STAFF_APPS, "tabs": STAFF_TABS},
    {"name": "KEM_Academic_Coordinator", "label": "KEM Academic Coordinator",
     "description": "Academic coordinator: maintains curriculum, timetable, enrolments, and academic oversight.",
     "objects": {"Branch__c": "", "Room__c": "CE"}, "apps": STAFF_APPS, "tabs": STAFF_TABS},
    {"name": "KEM_Teacher", "label": "KEM Teacher",
     "description": "Teacher: views assigned classes, marks attendance, and enters assessment results.",
     "objects": {"Branch__c": "", "Room__c": ""}, "apps": STAFF_APPS, "tabs": STAFF_TABS},
    {"name": "KEM_Finance", "label": "KEM Finance",
     "description": "Finance user: manages fees, invoices, payments, allocations, and reconciliation.",
     "objects": {"Branch__c": "", "Room__c": ""}, "apps": STAFF_APPS, "tabs": STAFF_TABS},
    {"name": "KEM_Portal_User", "label": "KEM Portal User", "classAccess": "portal",
     "description": "Learner or guardian portal access. Record visibility is enforced in Apex through explicit guardian relationships.",
     "objects": {}},
]
