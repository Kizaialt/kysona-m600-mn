#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Read-only check of how the Kysona mouse driver discovers its language files.

    python tools/inspect_driver.py "path/to/Mouse Drive Beta.exe"

Nothing is executed; we only look for the strings the program uses to build
the Language\\<n>-<Name>.xml path and the language menu.
"""
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

path = sys.argv[1] if len(sys.argv) > 1 else 'M600_x/app/Mouse Drive Beta.exe'
data = open(path, 'rb').read()
print('%s  (%d bytes)\n' % (path, len(data)))

BS = chr(92)
TARGETS = [
    'Language',
    'Language' + BS,
    '*.xml',
    '.xml',
    'FontSize',
    'Control',
    'Config.ini',
    'Description.xml',
    'FindFirst',
    'LanguageIndex',
    'Lang',
]

print('string references (ASCII / UTF-16):')
for s in TARGETS:
    asc = data.count(s.encode('latin1'))
    u16 = data.count(s.encode('utf-16-le'))
    mark = 'FOUND' if (asc or u16) else '  -  '
    print('  %-5s %-18r ascii=%-4d utf16=%d' % (mark, s, asc, u16))

print('\nASCII strings containing "Language" or "xml":')
seen = []
for m in re.finditer(rb'[\x20-\x7e]{4,80}', data):
    s = m.group().decode('latin1')
    if re.search(r'(?i)language|\.xml|FontSize', s) and s not in seen:
        seen.append(s)
        print('   %s' % s[:78])
    if len(seen) >= 25:
        break
