#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Check a generated language file against the vendor's English original.

    python tools/verify.py .work/<MODEL>/app/Language/0-English.xml dist/<MODEL>/2-Монгол.xml
"""
import re
import sys
import xml.etree.ElementTree as ET

sys.stdout.reconfigure(encoding='utf-8')

NEVER_TRANSLATE = {'ComboBoxName'}


def tree(path):
    raw = open(path, 'rb').read()
    root = ET.fromstring(raw.decode('utf-8-sig'))
    items = []

    def walk(node, path_parts):
        kids = list(node)
        if kids:
            for c in kids:
                walk(c, path_parts + [node.tag])
        else:
            items.append(('/'.join(path_parts + [node.tag]), node.text or ''))

    for c in root:
        walk(c, [])
    return root.tag, items, raw


def main():
    en_path, mn_path = sys.argv[1], sys.argv[2]
    en_root, en_items, _ = tree(en_path)
    mn_root, mn_items, mn_raw = tree(mn_path)

    ok = True

    def check(label, cond, detail=''):
        nonlocal ok
        ok &= bool(cond)
        print('  %-38s %s%s' % (label, 'PASS' if cond else 'FAIL',
                                (' — ' + detail) if detail else ''))

    print('English root <%s>  |  Mongolian root <%s>\n' % (en_root, mn_root))

    check('element tree matches exactly',
          [p for p, _ in en_items] == [p for p, _ in mn_items],
          '%d vs %d leaves' % (len(en_items), len(mn_items)))

    check('UTF-8 BOM (same as vendor)', mn_raw[:3] == b'\xef\xbb\xbf')
    check('CRLF line endings', b'\r\n' in mn_raw)

    # control identifiers must be byte-identical
    bad_ids = [(p, a, b) for (p, a), (_, b) in zip(en_items, mn_items)
               if p.split('/')[-1] in NEVER_TRANSLATE and a != b]
    check('ComboBoxName identifiers untouched', not bad_ids,
          str(bad_ids[:2]) if bad_ids else '')

    # numeric / unit values must survive unchanged
    numeric = [(p, a, b) for (p, a), (_, b) in zip(en_items, mn_items)
               if re.fullmatch(r'[\d.]+\s*(ms|mm|sec|min|Hz)?', (a or '').strip())]
    changed_nums = [x for x in numeric if x[1] != x[2]]
    check('numbers/units unchanged', not changed_nums,
          '%d numeric values' % len(numeric))

    cyr = sum(1 for _, v in mn_items if re.search(r'[Ѐ-ӿ]', v or ''))
    check('Mongolian text present', cyr > 150, '%d Cyrillic values' % cyr)

    # anything still identical to English that is not deliberately kept
    same = [(p, a) for (p, a), (_, b) in zip(en_items, mn_items)
            if a == b and a.strip()
            and p.split('/')[-1] not in NEVER_TRANSLATE
            and not re.fullmatch(r'[\d.]+\s*(ms|mm|sec|min|Hz)?', a.strip())
            and a.strip() not in {'LP', 'HP', 'LOD', 'B:', 'G:', 'R:', 'DPI+', 'DPI-', 'Neon'}]
    print()
    if same:
        print('  still English (%d) — check these are intentional:' % len(same))
        for p, a in same[:15]:
            print('     %-28s %s' % (p.split('/')[-1], a[:50]))
    else:
        print('  every translatable string is in Mongolian')

    print('\n%s' % ('ALL CHECKS PASS' if ok else 'PROBLEMS FOUND'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
