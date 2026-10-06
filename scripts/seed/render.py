#!/usr/bin/env python3
"""Renders a seed template with a slice of families.json: render.py <template> <start> <count> <out>."""
import json, sys
tpl, start, count, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
fams = json.load(open(__file__.replace("render.py", "families.json")))[start:start + count]
payload = json.dumps(fams, separators=(",", ":")).replace("\\", "\\\\").replace("'", "\\'")
open(out, "w").write(open(tpl).read().replace("__FAMILIES__", payload))
print(len(fams))
