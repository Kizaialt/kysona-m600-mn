# KYSONA драйверыг монгол хэлтэйгээр суулгах — нэг товшилтоор
#
#   1. KYSONA-гийн ЖИНХЭНЭ драйверыг суулгана (өөрчлөөгүй, эх файл)
#   2. Монгол хэлний файлыг Language хавтас руу нэмнэ
#   3. Монголоор нээгдэхээр тохируулахыг оролдоно
#
# Драйверын программ (Mouse Drive Beta.exe) огт өөрчлөгдөхгүй.

[CmdletBinding()]
param(
    [string]$UserSid,
    [switch]$Applied
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

function Say($m, $c = 'White') { Write-Host $m -ForegroundColor $c }
function Head($m) { Say ''; Say "  $m" Cyan; Say ('  ' + ('-' * $m.Length)) DarkGray }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$MN = [char]0x041C+[char]0x043E+[char]0x043D+[char]0x0433+[char]0x043E+[char]0x043B   # "Монгол"

# ---------------------------------------------------------------- step 1
if (-not $Applied) {
    Head 'KYSONA — Монгол хэлтэй драйвер суулгах'
    Say ''
    Say '  Энэ нь дараах зүйлийг хийнэ:' Gray
    Say '    1. KYSONA-гийн жинхэнэ драйверыг суулгана' Gray
    Say '    2. Монгол хэлний файлыг нэмнэ' Gray
    Say '    3. Монголоор нээгдэхээр тохируулна' Gray
    Say ''

    $setup = Get-ChildItem (Join-Path $here 'driver') -Filter '*.exe' -File -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if (-not $setup) { Say '  АЛДАА: driver хавтас дотор суулгагч алга.' Red; Read-Host '  Enter'; exit 1 }

    Say "  KYSONA-гийн суулгагчийг нээж байна: $($setup.Name)" White
    Say '  Гарч ирэх цонхон дээр Next / Install дарж дуусгана уу.' Yellow
    Say ''
    try { Start-Process -FilePath $setup.FullName -Wait }
    catch { Say "  Суулгагчийг ажиллуулж чадсангүй: $($_.Exception.Message)" Red; Read-Host '  Enter'; exit 1 }
    Say '  Суулгагч дууслаа.' Green
}

# ---------------------------------------------------------------- elevate
$admin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $admin) {
    Say ''
    Say '  Монгол хэлний файлыг нэмэхийн тулд администратор эрх хэрэгтэй...' Yellow
    $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    Start-Process powershell -Verb RunAs -Wait -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
        '-Applied', '-UserSid', $sid
    )
    exit
}

# ---------------------------------------------------------------- step 2
Head 'Монгол хэл нэмж байна'

$srcXml = Get-ChildItem (Join-Path $here 'lang') -Filter '*.xml' -File -ErrorAction SilentlyContinue |
          Select-Object -First 1
if (-not $srcXml) { Say '  АЛДАА: lang хавтас дотор XML алга.' Red; Read-Host '  Enter'; exit 1 }

Say '  Суулгасан драйверыг хайж байна...' Gray
$roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs") |
         Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

$found = @()
foreach ($r in $roots) {
    $found += Get-ChildItem $r -Filter 'Mouse Drive*.exe' -Recurse -File -Depth 4 -ErrorAction SilentlyContinue
}
$found = $found | Sort-Object FullName -Unique

if ($found.Count -eq 0) {
    Say ''; Say '  Драйвер олдсонгүй.' Red
    Say '  Суулгагчийг дуусгасан эсэхээ шалгаад дахин оролдоно уу.' Yellow
    Read-Host '  Enter'; exit 1
}

$done = 0
$mnIndex = $null
foreach ($drv in $found) {
    $app = Split-Path -Parent $drv.FullName
    $langDir = Join-Path $app 'Language'
    if (-not (Test-Path $langDir)) { Say "  ! Language хавтас алга: $app" Yellow; continue }

    Say ''
    Say "  $app" Green
    $before = @(Get-ChildItem $langDir -Filter '*.xml' -File | ForEach-Object { $_.BaseName })
    Say ("   Одоогийн хэлүүд: " + ($before -join ', ')) DarkGray

    Get-ChildItem $langDir -Filter '*.xml' -File |
        Where-Object { $_.Name -match $MN } |
        ForEach-Object { [IO.File]::Delete($_.FullName) }

    $used = @()
    foreach ($f in (Get-ChildItem $langDir -Filter '*.xml' -File)) {
        if ($f.Name -match '^([0-9]+)-') { $used += [int]$Matches[1] }
    }
    $next = if ($used.Count) { ($used | Measure-Object -Maximum).Maximum + 1 } else { 0 }
    Copy-Item $srcXml.FullName (Join-Path $langDir "$next-$MN.xml") -Force
    Say "   + $next-$MN.xml" Gray
    $mnIndex = $next
    $done++
}

# ---------------------------------------------------------------- step 3
# Драйвер сонгосон хэлээ HKCU\Software\Compx дотор LanguageIndex нэрээр
# хадгалдаг (Mouse Drive Beta.exe дотор энэ нэрс байгаа). Түлхүүр нь
# драйверыг анх ажиллуулах хүртэл үүсдэггүй тул утгын төрлийг урьдчилан
# баттай мэдэх боломжгүй — оролдоод үзнэ. Ажиллахгүй бол хэрэглэгч нэг
# удаа гараар сонгоход хангалттай.
if ($null -ne $mnIndex) {
    try {
        $hive = if ($UserSid) { "Registry::HKEY_USERS\$UserSid\Software\Compx" } else { 'HKCU:\Software\Compx' }
        New-Item -Path $hive -Force | Out-Null
        New-ItemProperty -Path $hive -Name 'LanguageIndex' -Value $mnIndex -PropertyType DWord -Force | Out-Null
        Say ''
        Say "   + Монголоор нээгдэхээр тохируулав (LanguageIndex=$mnIndex)" Gray
    } catch {
        Say ''
        Say '   ! Хэлийг урьдчилан тохируулж чадсангүй — драйвер дотроос сонгоно уу' Yellow
    }
}

Say ''
if ($done -gt 0) {
    Head 'Бэлэн боллоо'
    Say ''
    Say '  Драйверыг нээнэ үү.' Green
    Say "  Хэрэв монголоор гарахгүй бол:  Setting -> Language -> $MN" Gray
    Say '  (нэг удаа сонгоход хангалттай, дараа нь санана)' DarkGray
} else {
    Say '  Драйвер олдсон ч Language хавтас алга байна.' Yellow
}
Say ''
Read-Host '  Хаахын тулд Enter дарна уу' | Out-Null
