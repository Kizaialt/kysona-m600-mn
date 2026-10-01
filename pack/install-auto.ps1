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

#region peaklab-common  (identical in every install script; tools/qa checks it)
# Any error stops here with the message on screen. Without this the window
# closes the instant the script fails and the customer never sees why.
trap {
    Write-Host ''
    Write-Host ('  АЛДАА: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ('  ' + ($_.InvocationInfo.PositionMessage -replace '\s+', ' ')) -ForegroundColor DarkGray
    Write-Host ''
    Read-Host '  Хаахын тулд Enter дарна уу' | Out-Null
    exit 1
}

# Where is the driver installed? Customers install to D: as often as C:, so
# ask Windows first (installers record InstallLocation and their uninstaller),
# then fall back to every fixed drive. $ExeName may contain a wildcard.
function Find-Driver([string]$ExeName) {
    $dirs = @()
    $keys = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($e in @(Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue)) {
        if ($e.InstallLocation) { $dirs += [string]$e.InstallLocation }
        if ($e.UninstallString -and ($e.UninstallString -match '^\s*"?([^"]+?\.exe)')) {
            $dirs += (Split-Path -Parent $Matches[1])
        }
    }
    $hits = @()
    foreach ($d in ($dirs | Where-Object { $_ } | Sort-Object -Unique)) {
        # Some installers (Google Drive) record InstallLocation as the path of
        # an .exe, and Get-ChildItem given a FILE ignores -Filter and returns it.
        if (Test-Path -LiteralPath $d -PathType Leaf) { $d = Split-Path -Parent $d }
        if (Test-Path -LiteralPath $d -PathType Container) {
            $hits += @(Get-ChildItem -LiteralPath $d -Filter $ExeName -File -ErrorAction SilentlyContinue |
                       ForEach-Object { $_.FullName })
        }
    }
    if ($hits.Count -eq 0) {
        $bases = @("$env:LOCALAPPDATA\Programs")
        foreach ($drv in [IO.DriveInfo]::GetDrives()) {
            if ($drv.DriveType -eq 'Fixed' -and $drv.IsReady) {
                foreach ($sub in 'Program Files', 'Program Files (x86)', 'Programs') {
                    $bases += (Join-Path $drv.RootDirectory.FullName $sub)
                }
            }
        }
        foreach ($b in ($bases | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)) {
            $hits += @(Get-ChildItem -LiteralPath $b -Filter $ExeName -Recurse -File -Depth 4 -ErrorAction SilentlyContinue |
                       ForEach-Object { $_.FullName })
        }
    }
    return @($hits | Sort-Object -Unique)
}

# Last resort: let the customer point at the folder themselves.
function Ask-DriverFolder([string]$ExeName) {
    Write-Host ''
    Write-Host '  Драйверыг автоматаар олсонгүй.' -ForegroundColor Yellow
    Write-Host "  $ExeName байгаа хавтсыг энд бичээд Enter дарна уу." -ForegroundColor Gray
    Write-Host '  Жишээ:  D:\Program Files (x86)\AULA\F65' -ForegroundColor DarkGray
    for ($i = 0; $i -lt 3; $i++) {
        $p = ([string](Read-Host '  Зам')).Trim().Trim('"')
        if (-not $p) { return @() }
        if (Test-Path -LiteralPath $p -PathType Container) {
            $f = Get-ChildItem -LiteralPath $p -Filter $ExeName -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($f) { return @($f.FullName) }
        }
        Write-Host "  $ExeName энэ хавтсанд алга. Дахин оролдоно уу." -ForegroundColor Red
    }
    return @()
}
#endregion peaklab-common

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

    # Already installed? Then do not make the customer click through KYSONA's
    # wizard a second time just to add a language.
    $runInstaller = $true
    $already = @(Find-Driver 'Mouse Drive*.exe')
    if ($already.Count -gt 0) {
        Say '  KYSONA драйвер аль хэдийн суусан байна:' Yellow
        Say ('    ' + (Split-Path -Parent $already[0])) DarkGray
        Say ''
        $ans = ([string](Read-Host '  Зөвхөн монгол хэлийг нэмэх үү?   Enter = Тийм,   2 = драйверыг дахин суулгах')).Trim()
        if ($ans -ne '2') { $runInstaller = $false }
        Say ''
    }

    if ($runInstaller) {
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
$exes = @(Find-Driver 'Mouse Drive*.exe')
if ($exes.Count -eq 0) { $exes = @(Ask-DriverFolder 'Mouse Drive*.exe') }
if ($exes.Count -eq 0) {
    Say ''; Say '  Драйвер олдсонгүй.' Red
    Say '  Суулгагчийг дуусгасан эсэхээ шалгаад дахин оролдоно уу.' Yellow
    Read-Host '  Enter'; exit 1
}
$found = @($exes | ForEach-Object { Get-Item -LiteralPath $_ })

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
