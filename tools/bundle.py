#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build the one-click bundle: vendor installer + Mongolian pack + installer script.

    python tools/bundle.py installers/KYSONA_M600_driver.exe [more.exe ...]

The customer downloads one zip, double-clicks one file, clicks through KYSONA's
own wizard, and the driver then opens in Mongolian. No second download, no
language menu to find.

The vendor installer inside the zip is KYSONA's original, byte for byte - the
SHA-256 is printed here and recorded in the zip so it can be checked against
KYSONA's own download. We add files beside it; we never modify it.

Run tools/build.py first: this reuses the text.xml it generates.
"""
import hashlib
import io
import os
import re
import shutil
import subprocess
import sys

sys.stdout.reconfigure(encoding='utf-8')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, 'dist')
BUNDLE = os.path.join(ROOT, 'dist-auto')
WORK = os.path.join(ROOT, '.work')

README = u"""{title} — Монгол хэлтэй драйвер
{rule}

НЭГ ТОВШИЛТООР СУУЛГАХ:

  "Суулгах.bat" дээр хоёр товшино уу.

  Дараа нь:
    1. KYSONA-гийн суулгагч нээгдэнэ — Next / Install дарж дуусгана
    2. Администратор эрх асууна — Тийм гэж хариулна
    3. Дуусна

  Драйверыг нээхэд шууд МОНГОЛ хэл дээр гарна.


ЮУ ХИЙГДЭХ ВЭ:

  - KYSONA-гийн ЖИНХЭНЭ драйверыг суулгана (энэ zip дотор байгаа,
    өөрчлөөгүй эх файл)
  - Монгол хэлний файлыг нэмнэ (app\\Text\\mn\\text.xml)
  - Драйверыг монголоор нээгдэхээр тохируулна

  Драйверын программ (Mouse Drive Beta.exe) ОГТ өөрчлөгдөхгүй.


ХЭЛЭЭ БУЦААХ:
  Драйвер дотор Setting -> Language -> English


ЭХ ФАЙЛЫН БАТАЛГАА:
  driver\\{setup}
  SHA-256: {sha}

  Энэ бол KYSONA-гийн албан ёсны сайтаас татсан файл, өөрчлөөгүй.
  Шалгах:  certutil -hashfile "driver\\{setup}" SHA256

Асуудал гарвал Peaklab-т хандана уу.
"""

BAT = '@echo off\r\nchcp 65001 >nul\r\npowershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-auto.ps1"\r\npause\r\n'


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)

    os.makedirs(BUNDLE, exist_ok=True)
    built = []

    for installer in sys.argv[1:]:
        if not os.path.isfile(installer):
            print('SKIP (not found): %s' % installer)
            continue
        model = re.sub(r'[^A-Za-z0-9]+', '_',
                       os.path.splitext(os.path.basename(installer))[0]).strip('_')

        pack = os.path.join(DIST, model)
        xml = None
        if os.path.isdir(pack):
            for name in sorted(os.listdir(pack)):
                if name.lower().endswith('.xml'):
                    xml = os.path.join(pack, name)
                    break
        if not xml:
            print('== %s\n    no Mongolian pack in dist/ - run tools/build.py first, skipped' % model)
            continue

        title = model
        cfg = os.path.join(WORK, model, 'app', 'Config.ini')
        if os.path.isfile(cfg):
            text = open(cfg, 'rb').read().decode('utf-8-sig', 'replace')
            m = re.search(r'^DriveName=(.*)$', text, re.M)
            if m:
                title = m.group(1).strip()

        print('== %s  (%s)' % (model, title))

        out = os.path.join(BUNDLE, model)
        shutil.rmtree(out, ignore_errors=True)
        os.makedirs(os.path.join(out, 'driver'), exist_ok=True)
        os.makedirs(os.path.join(out, 'lang'), exist_ok=True)

        setup_name = os.path.basename(installer)
        shutil.copy(installer, os.path.join(out, 'driver', setup_name))
        shutil.copy(xml, os.path.join(out, 'lang', os.path.basename(xml)))
        shutil.copy(os.path.join(ROOT, 'pack', 'install-auto.ps1'),
                    os.path.join(out, 'install-auto.ps1'))
        with io.open(os.path.join(out, 'Суулгах.bat'), 'w',
                     encoding='utf-8', newline='') as fh:
            fh.write(BAT)

        digest = sha256(installer)
        with io.open(os.path.join(out, 'ЗААВАР.txt'), 'w',
                     encoding='utf-8-sig', newline='\r\n') as fh:
            fh.write(README.format(title=title, rule='=' * 42,
                                   setup=setup_name, sha=digest))

        zip_path = os.path.join(BUNDLE, '%s_mn_auto' % model)
        shutil.make_archive(zip_path, 'zip', out)
        size = os.path.getsize(zip_path + '.zip')
        built.append((model, title, size, digest))
        print('    vendor sha256 %s' % digest[:24])
        print('    -> dist-auto/%s_mn_auto.zip  (%.1f MB)' % (model, size / 1048576.0))

    print()
    if built:
        print('Built %d one-click bundle(s):' % len(built))
        for model, title, size, _d in built:
            print('  %-26s %-26s %.1f MB' % (model, title, size / 1048576.0))
        print('\nCustomer flow: download one zip -> Суулгах.bat -> click through')
        print('KYSONA\'s wizard -> driver opens in Mongolian.')
    else:
        print('Nothing built.')


if __name__ == '__main__':
    main()
