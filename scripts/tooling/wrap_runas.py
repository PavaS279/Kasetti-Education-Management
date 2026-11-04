"""Wraps every @IsTest method body of the given test classes in
System.runAs(TestDataFactory.admin()) { ... } unless already wrapped.
Works with Prettier-formatted (2-space) Apex."""
import re
import sys

for path in sys.argv[1:]:
    src = open(path).read()
    out, pos = "", 0
    for m in re.finditer(r"(\n  @IsTest\n  static void (\w+)\(\) \{\n)", src):
        start = m.end()
        end = src.index("\n  }\n", start)
        body = src[start:end]
        out += src[pos:m.start()] + m.group(1)
        if "TestDataFactory.admin()" in body.split("\n", 1)[0]:
            out += body
        else:
            indented = "\n".join(("  " + line if line.strip() else line) for line in body.split("\n"))
            out += "    System.runAs(TestDataFactory.admin()) {\n" + indented + "\n    }"
        pos = end
    out += src[pos:]
    open(path, "w").write(out)
