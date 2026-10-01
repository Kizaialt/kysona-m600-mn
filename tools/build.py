#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build the Mongolian language pack for the KYSONA M600 mouse driver.

    python tools/build.py installers/KYSONA_M600_driver.exe

For each installer it:
  1. extracts it with innoextract,
  2. reads app/Language/0-English.xml to learn the exact element tree,
  3. writes app/Language/<n>-Монгол.xml in the vendor's own format
     (UTF-8 with BOM, CRLF, 2-space indent, root element named after the
     language, same elements in the same order),
  4. packages it with an installer script.

The driver enumerates Language\\*.xml itself - `GetLanguageFileCount`,
`SaveLanguageIndex` and a `*.xml` glob are all present in the executable -
so a new file simply shows up in the language dropdown. Nothing else is
touched: no config edit, and the driver binary stays AULA... KYSONA's own.
"""

import io
import json
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MN_FILE = os.path.join(ROOT, 'tools', 'mn.json')
DIST = os.path.join(ROOT, 'dist')
WORK = os.path.join(ROOT, '.work')

LANG_NAME = 'Монгол'          # shown in the driver's Language dropdown
NEVER_TRANSLATE = {'ComboBoxName'}   # these are control identifiers, not text


def find_innoextract():
    exe = shutil.which('innoextract')
    if exe:
        return exe
    base = os.path.expandvars(r'%LOCALAPPDATA%\Microsoft\WinGet\Packages')
    for dirpath, _dirs, files in os.walk(base):
        if 'innoextract.exe' in files:
            return os.path.join(dirpath, 'innoextract.exe')
    sys.exit('innoextract not found. Install it with:\n'
             '  winget install --id dscharrer.innoextract -e')


def load_mn():
    with io.open(MN_FILE, encoding='utf-8') as fh:
        data = json.load(fh)
    return (data['strings'],
            set(data.get('_keep_as_is', [])),
            data.get('_font_size', '9.5'))


def render(node, depth, strings, keep, missing, out):
    """Re-emit the element tree, translating leaf text."""
    pad = '  ' * depth
    kids = list(node)
    if kids:
        out.append('%s<%s>' % (pad, node.tag))
        for child in kids:
            render(child, depth + 1, strings, keep, missing, out)
        out.append('%s</%s>' % (pad, node.tag))
        return

    text = node.text or ''
    if node.tag in NEVER_TRANSLATE:
        value = text                       # control id - must not change
    elif text in strings:
        value = strings[text]
    elif text.strip() in keep or not text.strip():
        value = text                       # numbers, units, deliberate blanks
    else:
        value = text
        missing.append((node.tag, text))
    out.append('%s<%s>%s</%s>' % (pad, node.tag, esc(value), node.tag))


def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def build_xml(src_path, strings, keep, font_size):
    text = open(src_path, 'rb').read().decode('utf-8-sig')
    root = ET.fromstring(text)

    missing = []
    out = ['<?xml version="1.0" encoding="utf-8"?>', '<%s>' % LANG_NAME]
    for child in root:
        if child.tag == 'FontSize':
            out.append('  <FontSize>%s</FontSize>' % font_size)
            continue
        render(child, 1, strings, keep, missing, out)
    out.append('</%s>' % LANG_NAME)
    out.append('')

    if missing:
        print('    WARNING: %d string(s) left in English:' % len(missing))
        for tag, txt in missing[:12]:
            print('      %-22s %s' % (tag, txt[:58]))

    blob = '\r\n'.join(out).encode('utf-8')
    return b'\xef\xbb\xbf' + blob, len(missing)


def next_index(lang_dir):
    """Language files are named <index>-<Name>.xml; take the next free index."""
    used = []
    for name in os.listdir(lang_dir):
        m = re.match(r'^(\d+)-', name)
        if m:
            used.append(int(m.group(1)))
    return max(used) + 1 if used else 0


README = u"""KYSONA M600 — Монгол хэлний багц
========================================

ЮУ ВЭ:
  Хулганы драйверын цэсийг монгол болгоно. Драйверын программыг
  ӨӨРЧЛӨХГҮЙ — зөвхөн хэлний нэг файл нэмнэ.

ХЭРХЭН СУУЛГАХ:
  1. Эхлээд KYSONA-гийн жинхэнэ драйверыг суулгасан байх ёстой.
     (https://shop.kysona.com/pages/downloads)
  2. "Install_Suulgah.bat" дээр хоёр товшино уу.
     (Windows администратор эрх асууна — Тийм гэж хариулна уу)
  3. Драйверыг нээгээд:  Setting → Language → {name}

ГАРААР СУУЛГАХ (скрипт ажиллахгүй бол):
  1. Драйвер суулгасан хавтсыг олно (дотор нь "Mouse Drive Beta.exe" байна).
  2. "{file}" файлыг тэнд байгаа  app\\Language  хавтас руу хуулна.
  3. Драйверыг дахин нээнэ.

БУЦААХ:
  app\\Language хавтас доторх "{file}" файлыг устгана.

Асуудал гарвал Peaklab-т хандана уу.
"""


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)

    inno = find_innoextract()
    strings, keep, font_size = load_mn()
    print('innoextract: %s' % inno)
    print('translations: %d strings, %d kept as-is\n' % (len(strings), len(keep)))

    os.makedirs(DIST, exist_ok=True)
    built = []

    for installer in sys.argv[1:]:
        if not os.path.isfile(installer):
            print('SKIP (not found): %s' % installer)
            continue
        model = re.sub(r'[^A-Za-z0-9]+', '_',
                       os.path.splitext(os.path.basename(installer))[0]).strip('_')
        print('== %s' % model)

        work = os.path.join(WORK, model)
        shutil.rmtree(work, ignore_errors=True)
        os.makedirs(work, exist_ok=True)
        subprocess.run([inno, '--extract', '--output-dir', work, '--silent', installer],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        lang_dir = os.path.join(work, 'app', 'Language')
        en_xml = os.path.join(lang_dir, '0-English.xml')
        if not os.path.isfile(en_xml):
            print('    no app/Language/0-English.xml - not this driver family, skipped')
            continue

        existing = sorted(os.listdir(lang_dir))
        print('    existing languages: %s' % ', '.join(existing))

        blob, n_missing = build_xml(en_xml, strings, keep, font_size)
        idx = next_index(lang_dir)
        out_name = '%d-%s.xml' % (idx, LANG_NAME)

        pack_dir = os.path.join(DIST, model)
        shutil.rmtree(pack_dir, ignore_errors=True)
        os.makedirs(pack_dir, exist_ok=True)
        open(os.path.join(pack_dir, out_name), 'wb').write(blob)

        # one launcher name everywhere: the customer is always told to run Install_Suulgah.bat
        shutil.copy(os.path.join(ROOT, 'pack', 'launcher-mn.bat'), os.path.join(pack_dir, 'Install_Suulgah.bat'))
        shutil.copy(os.path.join(ROOT, 'pack', 'install-mn.ps1'), os.path.join(pack_dir, 'install-mn.ps1'))
        if os.path.exists(os.path.join(pack_dir, 'install-mn.bat')):
            os.remove(os.path.join(pack_dir, 'install-mn.bat'))
        with io.open(os.path.join(pack_dir, 'ЗААВАР.txt'), 'w',
                     encoding='utf-8-sig', newline='\r\n') as fh:
            fh.write(README.format(name=LANG_NAME, file=out_name))

        zip_path = os.path.join(DIST, '%s_mn' % model)
        shutil.make_archive(zip_path, 'zip', pack_dir)
        built.append((model, out_name, n_missing))
        print('    -> %s  (%d bytes)' % (out_name, len(blob)))
        print('    -> dist/%s_mn.zip' % model)

    print()
    if built:
        print('Built %d language pack(s):' % len(built))
        for model, name, miss in built:
            note = 'all translated' if not miss else '%d left in English' % miss
            print('  %-28s %-22s %s' % (model, name, note))
    else:
        print('Nothing built.')


if __name__ == '__main__':
    main()
