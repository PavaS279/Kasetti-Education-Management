"""Metadata generator for Kasetti Education Management.

Generates CustomObject, CustomField, and PermissionSet source files from the
declarative specs in ``specs.py``. Keeping the data model and the access
matrix in one place guarantees that every field gets field-level security in
every permission set that grants the object.

Usage:  python3 scripts/tooling/mdgen.py
"""
import os
import sys
from xml.sax.saxutils import escape

sys.path.insert(0, os.path.dirname(__file__))
import specs  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OBJ_DIR = os.path.join(ROOT, "force-app", "main", "default", "objects")
PS_DIR = os.path.join(ROOT, "force-app", "main", "default", "permissionsets")
NS = 'xmlns="http://soap.sforce.com/2006/04/metadata"'
HEADER = '<?xml version="1.0" encoding="UTF-8"?>\n'

# Objects that receive field permissions only (object permissions are not grantable).
NO_OBJECT_PERMS = {"User"}

# Field types that never accept field-level security entries.
NO_FLS_TYPES = {"MasterDetail"}


def tag(name, value, indent=4):
    if value is None:
        return ""
    if isinstance(value, bool):
        value = "true" if value else "false"
    return f"{' ' * indent}<{name}>{escape(str(value))}</{name}>\n"


def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)


def picklist_xml(values, restricted=True, default=None, sorted_=False):
    out = "    <valueSet>\n"
    out += tag("restricted", restricted, 8)
    out += "        <valueSetDefinition>\n"
    out += tag("sorted", sorted_, 12)
    for v in values:
        out += "            <value>\n"
        out += tag("fullName", v, 16)
        out += tag("default", v == default, 16)
        out += tag("label", v, 16)
        out += "            </value>\n"
    out += "        </valueSetDefinition>\n"
    out += "    </valueSet>\n"
    return out


def field_xml(obj, f):
    t = f["type"]
    x = HEADER + f"<CustomField {NS}>\n"
    x += tag("fullName", f["name"])
    if f.get("description"):
        x += tag("description", f["description"])
    if f.get("externalId"):
        x += tag("externalId", True)
    if f.get("help"):
        x += tag("inlineHelpText", f["help"])
    x += tag("label", f["label"])
    if t == "Formula":
        x += tag("formula", f["formula"])
        x += tag("formulaTreatBlanksAs", f.get("blanks", "BlankAsZero"))
        rt = f["returnType"]
        if rt in ("Number", "Currency", "Percent"):
            x += tag("precision", 18)
            x += tag("scale", f.get("scale", 2))
        x += tag("type", rt)
        x += tag("unique", False) if False else ""
    elif t == "AutoNumber":
        x += tag("displayFormat", f["format"])
        x += tag("externalId", False) if not f.get("externalId") else ""
        x += tag("type", "AutoNumber")
    elif t == "Summary":
        x += tag("summarizedField", f.get("summarizedField"))
        for flt in f.get("filters", []):
            x += "    <summaryFilterItems>\n"
            x += tag("field", flt[0], 8)
            x += tag("operation", flt[1], 8)
            x += tag("value", flt[2], 8)
            x += "    </summaryFilterItems>\n"
        x += tag("summaryForeignKey", f["foreignKey"])
        x += tag("summaryOperation", f["operation"])
        x += tag("type", "Summary")
    else:
        if t in ("Text", "Email", "Phone", "Url", "Number", "Currency", "Percent", "Date",
                 "DateTime", "Time", "Picklist", "MultiselectPicklist", "TextArea"):
            x += tag("required", f.get("required", False))
        if t == "Text":
            x += tag("length", f.get("length", 255))
            x += tag("caseSensitive", False) if f.get("unique") else ""
            x += tag("unique", f.get("unique", False))
        elif t in ("LongTextArea", "Html"):
            x += tag("length", f.get("length", 32768))
            x += tag("visibleLines", f.get("lines", 5))
        elif t in ("Number", "Currency", "Percent"):
            x += tag("precision", f.get("precision", 18))
            x += tag("scale", f.get("scale", 2 if t != "Number" else 0))
            if f.get("unique"):
                x += tag("unique", True)
        elif t == "Checkbox":
            x += tag("defaultValue", f.get("default", False))
        elif t == "Lookup":
            if f["ref"] != "User":
                x += tag("deleteConstraint", f.get("deleteConstraint", "SetNull" if not f.get("required") else "Restrict"))
            x += tag("referenceTo", f["ref"])
            x += tag("relationshipLabel", f.get("relLabel", obj["plural"]))
            x += tag("relationshipName", f.get("relName", obj["name"].replace("__c", "").replace("_", "") + "s"))
            x += tag("required", f.get("required", False))
            if f.get("lookupFilter"):
                x += f.get("lookupFilter")
        elif t == "MasterDetail":
            x += tag("referenceTo", f["ref"])
            x += tag("relationshipLabel", f.get("relLabel", obj["plural"]))
            x += tag("relationshipName", f.get("relName", obj["name"].replace("__c", "").replace("_", "") + "s"))
            x += tag("relationshipOrder", f.get("order", 0))
            x += tag("reparentableMasterDetail", f.get("reparentable", False))
            x += tag("writeRequiresMasterRead", False)
        if t in ("Date", "DateTime", "Text", "Number", "Currency", "Percent") and f.get("defaultFormula"):
            x += tag("defaultValue", f["defaultFormula"])
        x += tag("trackHistory", f.get("track", False)) if obj.get("history") else ""
        x += tag("type", t)
        if t == "Picklist":
            x += picklist_xml(f["values"], default=f.get("default"))
        if t == "MultiselectPicklist":
            x += tag("visibleLines", 4)
            x += picklist_xml(f["values"])
    x += "</CustomField>\n"
    return x


def object_xml(o):
    x = HEADER + f"<CustomObject {NS}>\n"
    for a in ("Accept", "CancelEdit", "Clone", "Delete", "Edit", "List", "New", "SaveEdit", "Tab", "View"):
        x += "    <actionOverrides>\n" + tag("actionName", a, 8) + tag("type", "Default", 8) + "    </actionOverrides>\n"
    x += tag("allowInChatterGroups", False)
    x += tag("compactLayoutAssignment", "SYSTEM")
    x += tag("deploymentStatus", "Deployed")
    if o.get("description"):
        x += tag("description", o["description"])
    x += tag("enableActivities", o.get("activities", False))
    x += tag("enableBulkApi", True)
    x += tag("enableFeeds", False)
    x += tag("enableHistory", o.get("history", False))
    x += tag("enableLicensing", False)
    x += tag("enableReports", True)
    x += tag("enableSearch", o.get("search", True))
    x += tag("enableSharing", True)
    x += tag("enableStreamingApi", True)
    x += tag("externalSharingModel", o.get("externalSharing", "Private"))
    x += tag("label", o["label"])
    nf = o.get("nameField", {"label": o["label"] + " Name", "type": "Text"})
    x += "    <nameField>\n"
    if nf["type"] == "AutoNumber":
        x += tag("displayFormat", nf["format"], 8)
    x += tag("label", nf["label"], 8)
    x += tag("trackHistory", False, 8)
    x += tag("type", nf["type"], 8)
    x += "    </nameField>\n"
    x += tag("pluralLabel", o["plural"])
    x += tag("searchLayouts", "") if False else "    <searchLayouts/>\n"
    x += tag("sharingModel", o.get("sharing", "ReadWrite"))
    x += tag("visibility", "Public")
    x += "</CustomObject>\n"
    return x


def gen_objects():
    for o in specs.OBJECTS:
        base = os.path.join(OBJ_DIR, o["name"])
        if not o.get("standard"):
            write(os.path.join(base, o["name"] + ".object-meta.xml"), object_xml(o))
            for vr in o.get("validationRules", []):
                write(os.path.join(base, "validationRules", vr["name"] + ".validationRule-meta.xml"), validation_xml(vr))
        else:
            for vr in o.get("validationRules", []):
                write(os.path.join(base, "validationRules", vr["name"] + ".validationRule-meta.xml"), validation_xml(vr))
        for f in o["fields"]:
            write(os.path.join(base, "fields", f["name"] + ".field-meta.xml"), field_xml(o, f))


def validation_xml(vr):
    x = HEADER + f"<ValidationRule {NS}>\n"
    x += tag("fullName", vr["name"])
    x += tag("active", True)
    x += tag("description", vr.get("description", vr["message"]))
    x += tag("errorConditionFormula", vr["formula"])
    if vr.get("field"):
        x += tag("errorDisplayField", vr["field"])
    x += tag("errorMessage", vr["message"])
    x += "</ValidationRule>\n"
    return x


def obj_index():
    return {o["name"]: o for o in specs.OBJECTS}


def split_permsets():
    """Splits licensed persona permission sets into a licence-free base set and a licensed _Edu set."""
    result = []
    edu = getattr(specs, "EDU_OBJECTS", set())
    for ps in specs.PERMISSION_SETS:
        if not ps.get("license"):
            result.append(ps)
            continue
        base = dict(ps)
        base.pop("license")
        base["objects"] = {k: v for k, v in ps["objects"].items() if k not in edu}
        licensed = {
            "name": ps["name"] + "_Edu",
            "label": ps["label"] + " (Education Cloud)",
            "description": "Education Cloud object access for the " + ps["label"] + " persona. Requires the Education Cloud licence.",
            "license": ps["license"],
            "objects": {k: v for k, v in ps["objects"].items() if k in edu},
            "readOnlyFields": ps.get("readOnlyFields", {}),
            # Licensed sets cannot hold Apex class access; classes stay on the base set.
            "classAccess": "none",
            # GroupMembershipPsl is required for ContactContactRelation and PartyRoleRelation (found by probe).
            "userPermissions": ["AccessEducationCloud", "GroupMembershipPsl", "DocumentChecklistUserAccess"],
        }
        if licensed["objects"]:
            # Education Cloud objects depend on read access to people records in the same set.
            licensed["objects"].update({"Account": "", "Contact": ""})
        result.append(base)
        if licensed["objects"]:
            result.append(licensed)
            base["group"] = [base["name"], licensed["name"]]
    return result


def gen_groups(permsets):
    group_dir = os.path.join(ROOT, "force-app", "main", "default", "permissionsetgroups")
    for ps in permsets:
        members = ps.get("group")
        if not members:
            continue
        x = HEADER + f"<PermissionSetGroup {NS}>\n"
        x += tag("description", ps["description"])
        x += tag("hasActivationRequired", False)
        x += tag("label", ps["label"] + " Persona")
        for m in members:
            x += tag("permissionSets", m)
        x += tag("status", "Updated")
        x += "</PermissionSetGroup>\n"
        write(os.path.join(group_dir, ps["name"] + "_Persona.permissionsetgroup-meta.xml"), x)


def gen_permsets():
    idx = obj_index()
    permsets = split_permsets()
    gen_groups(permsets)
    for ps in permsets:
        changed = True
        while changed:  # resolve transitive dependencies (e.g. checklist -> relation -> role)
            changed = False
            for oname in list(ps["objects"]):
                for dep in getattr(specs, "OBJECT_DEPENDENCIES", {}).get(oname, []):
                    parent = ps["objects"][oname]
                    needed = "V" if ("V" in parent or "M" in parent) else ""
                    current = ps["objects"].get(dep)
                    updated = (current or "") + needed if needed not in (current or "") else (current or "")
                    if current is None or updated != current:
                        ps["objects"][dep] = updated
                        changed = True
        x = HEADER + f"<PermissionSet {NS}>\n"
        for cls in sorted(set(ps.get("classes", []) + specs.COMMON_CLASSES.get(ps.get("classAccess", "staff"), []))):
            x += "    <classAccesses>\n" + tag("apexClass", cls, 8) + tag("enabled", True, 8) + "    </classAccesses>\n"
        for perm in sorted(ps.get("custom", [])):
            x += "    <customPermissions>\n" + tag("enabled", True, 8) + tag("name", perm, 8) + "    </customPermissions>\n"
        x += tag("description", ps["description"])
        fls = []
        for oname, access in sorted(ps["objects"].items()):
            o = idx.get(oname)
            if o is None:
                continue
            ro_fields = set(ps.get("readOnlyFields", {}).get(oname, []))
            for f in o["fields"]:
                if f["type"] in NO_FLS_TYPES or f.get("required"):
                    continue
                readonly_type = f["type"] in ("Formula", "Summary", "AutoNumber") or f.get("systemManaged")
                editable = ("E" in access or "C" in access) and not readonly_type and f["name"] not in ro_fields
                fls.append((f"{oname}.{f['name']}", editable))
        for oname, fields in getattr(specs, "STANDARD_FIELD_ACCESS", {}).items():
            access = ps["objects"].get(oname)
            if access is None:
                continue
            for fname in fields:
                fls.append((f"{oname}.{fname}", "E" in access or "C" in access))
        for name, editable in sorted(fls):
            x += "    <fieldPermissions>\n" + tag("editable", editable, 8) + tag("field", name, 8) + tag("readable", True, 8) + "    </fieldPermissions>\n"
        x += tag("hasActivationRequired", False)
        x += tag("label", ps["label"])
        if ps.get("license"):
            x += tag("license", ps["license"])
        for oname, access in sorted(ps["objects"].items()):
            if oname in NO_OBJECT_PERMS:
                continue
            x += "    <objectPermissions>\n"
            x += tag("allowCreate", "C" in access, 8)
            x += tag("allowDelete", "D" in access, 8)
            x += tag("allowEdit", "E" in access, 8)
            x += tag("allowRead", True, 8)
            x += tag("modifyAllRecords", "M" in access, 8)
            x += tag("object", oname, 8)
            x += tag("viewAllRecords", "V" in access or "M" in access, 8)
            x += "    </objectPermissions>\n"
        for page in sorted(ps.get("pages", [])):
            x += "    <pageAccesses>\n" + tag("apexPage", page, 8) + tag("enabled", True, 8) + "    </pageAccesses>\n"
        for perm in sorted(ps.get("userPermissions", [])):
            x += "    <userPermissions>\n" + tag("enabled", True, 8) + tag("name", perm, 8) + "    </userPermissions>\n"
        for tab in sorted(ps.get("tabs", [])):
            x += "    <tabSettings>\n" + tag("tab", tab, 8) + tag("visibility", "Visible", 8) + "    </tabSettings>\n"
        for app in sorted(ps.get("apps", [])):
            x += "    <applicationVisibilities>\n" + tag("application", app, 8) + tag("visible", True, 8) + "    </applicationVisibilities>\n"
        x += "</PermissionSet>\n"
        # Salesforce requires applicationVisibilities before classAccesses; reorder sections.
        x = reorder_permset(x)
        write(os.path.join(PS_DIR, ps["name"] + ".permissionset-meta.xml"), x)


def reorder_permset(x):
    """Sort top-level child elements alphabetically, as Salesforce source format expects."""
    import re
    body = x.split(f"<PermissionSet {NS}>\n", 1)[1].rsplit("</PermissionSet>", 1)[0]
    blocks = re.findall(r"(    <(\w+)>(?:.*?)</\2>\n|    <(\w+)>[^<]*</\3>\n)", body, re.S)
    items = []
    for b in blocks:
        name = b[1] or b[2]
        items.append((name, b[0]))
    order = sorted(range(len(items)), key=lambda i: (items[i][0], i))
    return HEADER + f"<PermissionSet {NS}>\n" + "".join(items[i][1] for i in order) + "</PermissionSet>\n"


def transition_name(short, frm, to):
    """Developer name for a transition record: <= 40 chars, alphanumeric/underscore, no trailing or double underscores."""
    def clean(value):
        return "".join(ch for ch in value.replace(" ", "_").replace("-", "_") if ch.isalnum() or ch == "_").strip("_")

    def abbreviate(value):
        return "".join(word[:4].capitalize() for word in value.replace("-", " ").split())

    name = f"{short}_{clean(frm)}_{clean(to)}"
    if len(name) > 40:
        initials = "".join(ch for ch in short if ch.isupper()) or short[:4]
        name = f"{initials}_{abbreviate(frm)}_{abbreviate(to)}"
    while "__" in name:
        name = name.replace("__", "_")
    return name[:40].rstrip("_")


def gen_transitions():
    cmd_dir = os.path.join(ROOT, "force-app", "main", "default", "customMetadata")
    for (obj, field), pairs in specs.TRANSITIONS.items():
        short = obj.replace("__c", "").replace("_", "")
        for frm, to in pairs:
            dev = transition_name(short, frm, to)
            values = {"Active__c": ("boolean", "true"), "Field_Name__c": ("string", field), "From_Status__c": ("string", frm),
                      "Object_Name__c": ("string", obj), "To_Status__c": ("string", to)}
            x = HEADER + ('<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" '
                          'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">\n')
            x += tag("label", f"{short} {frm} > {to}"[:40])
            x += tag("protected", False)
            for name, (typ, val) in values.items():
                x += f'    <values>\n        <field>{name}</field>\n        <value xsi:type="xsd:{typ}">{escape(val)}</value>\n    </values>\n'
            x += "</CustomMetadata>\n"
            write(os.path.join(cmd_dir, f"Status_Transition.{dev}.md-meta.xml"), x)


if __name__ == "__main__":
    gen_transitions()
    gen_objects()
    gen_permsets()
    # Match the repository formatting (lint-staged runs Prettier on commit) so regeneration causes no churn.
    import subprocess
    subprocess.run(["npx", "--no-install", "prettier", "--log-level", "warn", "--write",
                    "force-app/main/default/objects", "force-app/main/default/permissionsets",
                    "force-app/main/default/customMetadata", "force-app/main/default/permissionsetgroups"], cwd=ROOT, check=False)
    print(f"Generated {len(specs.OBJECTS)} object specs and {len(specs.PERMISSION_SETS)} permission sets.")
