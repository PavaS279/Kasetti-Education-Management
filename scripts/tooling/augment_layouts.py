"""Adds a 'KTEdutech' section with every missing KEM custom field to org layouts (additive)."""
import json, os, re, sys, glob
sys.path.insert(0, 'scripts/tooling')
import specs
S = sys.argv[1]
OUT = 'force-app/main/default/layouts'
spec = {o['name']: o for o in specs.OBJECTS}
summary = []
for path in sorted(glob.glob(S + '/klay/unpackaged/unpackaged/layouts/*.layout')):
    name = os.path.basename(path)[:-len('.layout')]
    obj = name.split('-')[0]
    if name == 'Account-Business Account':
        continue
    xml = open(path).read()
    present = set(re.findall(r'<field>([^<]+)</field>', xml))
    desc = json.load(open(f'{S}/desc_{obj}.json'))['result']['fields']
    by = {f['name']: f for f in desc}
    order = [f['name'] for f in spec.get(obj, {}).get('fields', [])]
    meta = {f['name']: f for f in spec.get(obj, {}).get('fields', [])}
    candidates = [n for n in order if n in by] + sorted(n for n in by if n.endswith('__c') and n not in order)
    if name == 'Account-Person Account Layout':
        cfields = [f['name'] for f in spec.get('Contact', {}).get('fields', [])]
        candidates += [n[:-3] + '__pc' for n in cfields if n.endswith('__c') and n[:-3] + '__pc' in by]
        meta.update({n[:-3] + '__pc': f for n, f in ((f['name'], f) for f in spec.get('Contact', {}).get('fields', []))})
    items = []
    for n in candidates:
        if n in present:
            continue
        f = by[n]
        m = meta.get(n, {})
        if f.get('calculated') or f.get('autoNumber') or not f.get('updateable') or m.get('systemManaged'):
            behavior = 'Readonly'
        elif (not f.get('nillable')) and f.get('createable') and f['type'] != 'boolean':
            behavior = 'Required'
        else:
            behavior = 'Edit'
        items.append((n, behavior))
        present.add(n)
    if not items:
        continue
    half = (len(items) + 1) // 2
    cols = ''
    for chunk in (items[:half], items[half:]):
        cols += '        <layoutColumns>\n'
        for n, b in chunk:
            cols += f'            <layoutItems>\n                <behavior>{b}</behavior>\n                <field>{n}</field>\n            </layoutItems>\n'
        cols += '        </layoutColumns>\n'
    section = ('    <layoutSections>\n        <customLabel>true</customLabel>\n        <detailHeading>true</detailHeading>\n'
               '        <editHeading>true</editHeading>\n        <label>KTEdutech</label>\n' + cols +
               '        <style>TwoColumnsTopToBottom</style>\n    </layoutSections>\n')
    i = xml.index('</layoutSections>') + len('</layoutSections>\n')
    xml = xml[:i] + section + xml[i:]
    open(f'{OUT}/{name}.layout-meta.xml', 'w').write(xml)
    summary.append(f'{name}: +{len(items)} ({", ".join(n for n, _ in items[:8])}{"…" if len(items) > 8 else ""})')
print('\n'.join(summary)); print(len(summary), 'layouts')
