# KYSONA M600 драйверт монгол хэл нэмэх
#
# Драйверын программыг ӨӨРЧЛӨХГҮЙ. Зөвхөн app\Language хавтас руу
# нэг XML файл хуулна. Драйвер өөрөө тэр хавтсыг уншиж хэлний
# жагсаалтаа үүсгэдэг тул шинэ хэл автоматаар гарч ирнэ.
#
# Ажиллуулах: install-mn.bat дээр хоёр товшино уу

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

function Say($msg, $color = 'White') { Write-Host $msg -ForegroundColor $color }

Say ''
Say '  KYSONA M600 — Монгол хэлний багц' Cyan
Say '  ================================' Cyan
Say ''

$admin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $admin) {
    Say '  Администратор эрх шаардлагатай. Дахин ажиллуулж байна...' Yellow
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    )
    exit
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcXml = Get-ChildItem $here -Filter '*.xml' -File | Select-Object -First 1
if (-not $srcXml) { Say '  АЛДАА: хэлний XML файл олдсонгүй' Red; Read-Host '  Enter'; exit 1 }
Say ("  Хэлний файл: " + $srcXml.Name) Gray

# --- суулгасан драйверыг олох ----------------------------------------------
Say '  Драйверыг хайж байна...' Gray
$roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs") |
         Where-Object { $_ -and (Test-Path $_) }

$found = @()
foreach ($r in $roots) {
    $found += Get-ChildItem $r -Filter 'Mouse Drive*.exe' -Recurse -File -Depth 4 -ErrorAction SilentlyContinue
}
$found = $found | Sort-Object FullName -Unique

if ($found.Count -eq 0) {
    Say ''
    Say '  Драйвер олдсонгүй.' Red
    Say '  Эхлээд KYSONA-гийн жинхэнэ драйверыг суулгана уу:' Yellow
    Say '    https://shop.kysona.com/pages/downloads' Yellow
    Say ''
    Say '  Эсвэл "Mouse Drive Beta.exe" байгаа хавтсыг оруулна уу (хоосон = гарах):' Gray
    $manual = Read-Host '  Зам'
    if (-not $manual -or -not (Test-Path $manual)) { exit 1 }
    $hit = Get-ChildItem $manual -Filter 'Mouse Drive*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $hit) { Say '  Тэр хавтсанд драйвер алга.' Red; Read-Host '  Enter'; exit 1 }
    $found = @($hit)
}

$patched = 0
foreach ($drv in $found) {
    $app = Split-Path -Parent $drv.FullName
    $langDir = Join-Path $app 'Language'
    if (-not (Test-Path $langDir)) {
        Say "  ! Language хавтас алга: $app" Yellow
        continue
    }

    Say ''
    Say "  Олдлоо: $app" Green
    $before = @(Get-ChildItem $langDir -Filter '*.xml' -File | ForEach-Object { $_.BaseName })
    Say ("   Одоогийн хэлүүд: " + ($before -join ', ')) Gray

    # Хуучин монгол файл байвал устгаад дахин хуулна (индекс өөрчлөгдсөн байж болно)
    Get-ChildItem $langDir -Filter '*.xml' -File |
        Where-Object { $_.Name -match 'Монгол' } |
        ForEach-Object { [IO.File]::Delete($_.FullName) }

    # Дараагийн сул индексийг олох
    $used = @()
    foreach ($f in (Get-ChildItem $langDir -Filter '*.xml' -File)) {
        if ($f.Name -match '^([0-9]+)-') { $used += [int]$Matches[1] }
    }
    $next = if ($used.Count) { ($used | Measure-Object -Maximum).Maximum + 1 } else { 0 }
    $target = Join-Path $langDir ("$next-" + [char]0x041C+[char]0x043E+[char]0x043D+[char]0x0433+[char]0x043E+[char]0x043B + '.xml')

    Copy-Item $srcXml.FullName $target -Force
    Say ("   + " + (Split-Path $target -Leaf)) Gray
    $patched++
}

Say ''
if ($patched -gt 0) {
    Say "  Бэлэн боллоо ($patched драйвер)." Green
    Say '  Драйверыг нээгээд Setting -> Language хэсгээс "Монгол" сонгоно уу.' White
    Say '  (Драйвер аль хэдийн нээлттэй байсан бол хаагаад дахин нээнэ үү)' Gray
} else {
    Say '  Юу ч өөрчлөгдсөнгүй.' Yellow
}
Say ''
Read-Host '  Хаахын тулд Enter дарна уу' | Out-Null
