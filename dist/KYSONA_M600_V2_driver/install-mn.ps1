# KYSONA M600 драйверт монгол хэл нэмэх
#
# Драйверын программыг ӨӨРЧЛӨХГҮЙ. Зөвхөн app\Language хавтас руу
# нэг XML файл хуулна. Драйвер өөрөө тэр хавтсыг уншиж хэлний
# жагсаалтаа үүсгэдэг тул шинэ хэл автоматаар гарч ирнэ.
#
# Ажиллуулах: install-mn.bat дээр хоёр товшино уу

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
$exes = @(Find-Driver 'Mouse Drive*.exe')
if ($exes.Count -eq 0) { $exes = @(Ask-DriverFolder 'Mouse Drive*.exe') }
if ($exes.Count -eq 0) {
    Say ''
    Say '  Драйвер олдсонгүй.' Red
    Say '  Эхлээд KYSONA-гийн жинхэнэ драйверыг суулгана уу:' Yellow
    Say '    https://shop.kysona.com/pages/downloads' Yellow
    Read-Host '  Enter'; exit 1
}
$found = @($exes | ForEach-Object { Get-Item -LiteralPath $_ })

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
