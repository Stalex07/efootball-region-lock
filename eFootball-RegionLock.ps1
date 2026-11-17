#Requires -Version 5.1
<#
.SYNOPSIS
    eFootball Region Lock - keeps eFootball online matches on servers close to you.
    Powered by @mrstalex.

.DESCRIPTION
    Measures your latency to every Google Cloud and Amazon Web Services region,
    keeps the closest ones and blocks the rest in Windows Firewall.

    The rules apply ONLY to eFootball.exe and ONLY to outbound UDP traffic
    (the match traffic). Login, menus, the store and every other program on
    your PC keep working normally.

    It also includes match tools: check which server the current match uses
    (with ping, jitter and packet loss), a live monitor and a local match history.

    It never touches the game: no game files, no memory reading, no injection,
    and it never changes, delays or drops match packets.

    Never blocked:
      - Amazon regions the game talks to for its central services
        (ap-northeast-1 Tokyo, us-west-2 Oregon, eu-west-1 Ireland).
      - Amazon Local Zones / edge servers and Global Accelerator addresses.
      - Google "global" services.
      - Any region whose latency could not be measured.

.PARAMETER Mode
    Apply   : measure, then create the firewall rules (default).
    DryRun  : measure and show what would be blocked. Changes nothing.
    Pick    : measure, then choose by hand which regions to keep.
    Match   : during a match, show which server it uses (ping, jitter, loss).
    Monitor : during a match, live ping / jitter / loss line until a key is pressed.
    History : show the matches saved by Match and Monitor.
    Remove  : delete every rule created by this tool.
    Status  : show the rules currently in place.

.PARAMETER MaxPing
    Highest estimated latency (ms) a region may have to stay allowed. Default 100.

.PARAMETER MaxServers
    Keep at most this many regions (the closest ones). 0 = no limit. Default 4.

.PARAMETER MinServers
    Always keep at least this many regions, even if they exceed MaxPing,
    so you can still find matches. Default 2.

.PARAMETER GamePath
    Path(s) to eFootball.exe. Detected automatically for Steam and the Xbox app (Microsoft Store) if omitted.

.PARAMETER AlwaysAllow
    Region codes that must never be blocked, e.g. southamerica-east1, sa-east-1.

.PARAMETER AskSettings
    Ask for MaxPing and MaxServers interactively (used by Run.bat option 3).
    Only whole numbers inside the allowed range are accepted.

.PARAMETER CaptureSeconds
    Match / Monitor: how many seconds of the game's traffic headers to look at. Default 6.

.PARAMETER ProcessName
    Match / Monitor: process to inspect. Default eFootball. Only change it for testing.

.EXAMPLE
    .\eFootball-RegionLock.ps1 -Mode DryRun

.EXAMPLE
    .\eFootball-RegionLock.ps1 -MaxPing 80 -MaxServers 3

.EXAMPLE
    .\eFootball-RegionLock.ps1 -Mode Match
#>
[CmdletBinding()]
param(
    [ValidateSet('Apply', 'DryRun', 'Pick', 'Match', 'Monitor', 'History', 'Remove', 'Status')]
    [string]$Mode = 'Apply',

    [ValidateRange(10, 500)]
    [int]$MaxPing = 100,

    [ValidateRange(0, 50)]
    [int]$MaxServers = 4,

    [ValidateRange(1, 10)]
    [int]$MinServers = 2,

    [string[]]$GamePath,

    [string[]]$AlwaysAllow = @(),

    [ValidateSet('auto', 'en', 'es')]
    [string]$Lang = 'auto',

    [switch]$AskSettings,

    [ValidateRange(3, 30)]
    [int]$CaptureSeconds = 6,

    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string]$ProcessName = 'eFootball',

    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$ToolVersion  = '1.3.2'
$Credit       = 'Powered by @mrstalex'
$RuleGroup    = 'eFootball Region Lock'
$RuleTag      = 'Created by eFootball Region Lock'   # every rule we create starts its description with this
$ChunkSize    = 400
$ProtectedAws = @('ap-northeast-1', 'us-west-2', 'eu-west-1')

$GcpRangesUrl = 'https://www.gstatic.com/ipranges/cloud.json'
$AwsRangesUrl = 'https://ip-ranges.amazonaws.com/ip-ranges.json'

# Google's official regional endpoints (<service>.<region>.rep.googleapis.com) are served
# inside each region, so the time to connect to them is the latency to that region.
$GcpProbeServices = @('storage', 'compute')

$GcpNames = @{
    'africa-south1' = 'Johannesburg'; 'asia-east1' = 'Taiwan'; 'asia-east2' = 'Hong Kong'; 'asia-northeast1' = 'Tokyo'
    'asia-northeast2' = 'Osaka'; 'asia-northeast3' = 'Seoul'; 'asia-south1' = 'Mumbai'; 'asia-south2' = 'Delhi'
    'asia-southeast1' = 'Singapore'; 'asia-southeast2' = 'Jakarta'; 'asia-southeast3' = 'Bangkok'
    'australia-southeast1' = 'Sydney'; 'australia-southeast2' = 'Melbourne'; 'europe-central2' = 'Warsaw'
    'europe-north1' = 'Finland'; 'europe-north2' = 'Stockholm'; 'europe-southwest1' = 'Madrid'; 'europe-west1' = 'Belgium'
    'europe-west2' = 'London'; 'europe-west3' = 'Frankfurt'; 'europe-west4' = 'Netherlands'; 'europe-west6' = 'Zurich'
    'europe-west8' = 'Milan'; 'europe-west9' = 'Paris'; 'europe-west10' = 'Berlin'; 'europe-west12' = 'Turin'
    'me-central1' = 'Doha'; 'me-central2' = 'Dammam'; 'me-west1' = 'Tel Aviv'; 'northamerica-northeast1' = 'Montreal'
    'northamerica-northeast2' = 'Toronto'; 'northamerica-south1' = 'Queretaro'; 'southamerica-east1' = 'Sao Paulo'
    'southamerica-west1' = 'Santiago'; 'us-central1' = 'Iowa'; 'us-east1' = 'South Carolina'; 'us-east4' = 'N. Virginia'
    'us-east5' = 'Columbus'; 'us-south1' = 'Dallas'; 'us-west1' = 'Oregon'; 'us-west2' = 'Los Angeles'
    'us-west3' = 'Salt Lake City'; 'us-west4' = 'Las Vegas'
}

$DataDir      = Join-Path $env:LOCALAPPDATA 'eFootball Region Lock'
$HistoryFile  = Join-Path $DataDir 'match-history.csv'

$AwsNames = @{
    'us-east-1' = 'N. Virginia'; 'us-east-2' = 'Ohio'; 'us-west-1' = 'N. California'; 'us-west-2' = 'Oregon'
    'ca-central-1' = 'Montreal'; 'ca-west-1' = 'Calgary'; 'mx-central-1' = 'Queretaro'; 'sa-east-1' = 'Sao Paulo'
    'eu-west-1' = 'Ireland'; 'eu-west-2' = 'London'; 'eu-west-3' = 'Paris'; 'eu-central-1' = 'Frankfurt'
    'eu-central-2' = 'Zurich'; 'eu-north-1' = 'Stockholm'; 'eu-south-1' = 'Milan'; 'eu-south-2' = 'Spain'
    'il-central-1' = 'Tel Aviv'; 'me-central-1' = 'UAE'; 'me-south-1' = 'Bahrain'; 'af-south-1' = 'Cape Town'
    'ap-east-1' = 'Hong Kong'; 'ap-east-2' = 'Taipei'; 'ap-south-1' = 'Mumbai'; 'ap-south-2' = 'Hyderabad'
    'ap-southeast-1' = 'Singapore'; 'ap-southeast-2' = 'Sydney'; 'ap-southeast-3' = 'Jakarta'
    'ap-southeast-4' = 'Melbourne'; 'ap-southeast-5' = 'Malaysia'; 'ap-southeast-7' = 'Thailand'
    'ap-northeast-1' = 'Tokyo'; 'ap-northeast-2' = 'Seoul'; 'ap-northeast-3' = 'Osaka'
}

# City codes used in Amazon Local Zone names (e.g. us-east-1-lim-1 = Lima)
$AwsZoneCities = @{
    'lim' = 'Lima'; 'bue' = 'Buenos Aires'; 'scl' = 'Santiago'; 'bog' = 'Bogota'; 'qro' = 'Queretaro'
    'mia' = 'Miami'; 'atl' = 'Atlanta'; 'bos' = 'Boston'; 'chi' = 'Chicago'; 'dfw' = 'Dallas'; 'hou' = 'Houston'
    'iah' = 'Houston'; 'kc' = 'Kansas City'; 'den' = 'Denver'; 'msp' = 'Minneapolis'; 'nyc' = 'New York'
    'phl' = 'Philadelphia'; 'lax' = 'Los Angeles'; 'las' = 'Las Vegas'; 'phx' = 'Phoenix'; 'pdx' = 'Portland'
    'sea' = 'Seattle'; 'los' = 'Lagos'; 'ham' = 'Hamburg'; 'waw' = 'Warsaw'; 'ath' = 'Athens'; 'ist' = 'Istanbul'
    'mct' = 'Muscat'; 'ccu' = 'Kolkata'; 'del' = 'Delhi'; 'bkk' = 'Bangkok'; 'tpe' = 'Taipei'; 'mnl' = 'Manila'
    'per' = 'Perth'; 'akl' = 'Auckland'; 'hel' = 'Helsinki'; 'cph' = 'Copenhagen'; 'mad' = 'Madrid'
}

# ---------------------------------------------------------------- helpers

if ($Lang -eq 'auto') {
    $UseEs = ((Get-UICulture).TwoLetterISOLanguageName -eq 'es') -or ((Get-Culture).TwoLetterISOLanguageName -eq 'es')
} else {
    $UseEs = ($Lang -eq 'es')
}

function T([string]$En, [string]$Es) { if ($script:UseEs) { $Es } else { $En } }

function Say([string]$En, [string]$Es, [string]$Color = 'Gray') {
    Write-Host (T $En $Es) -ForegroundColor $Color
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-GameExe {
    $found = New-Object System.Collections.Generic.List[string]
    $rel = 'steamapps\common\eFootball\eFootball\Binaries\Win64\eFootball.exe'

    # Steam: main install + every library folder
    $roots = @()
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $v = Get-ItemProperty -Path $key -ErrorAction Stop
            foreach ($name in 'SteamPath', 'InstallPath') {
                if ($v.PSObject.Properties[$name] -and $v.$name) { $roots += ($v.$name -replace '/', '\') }
            }
        } catch { }
    }
    $libs = @()
    foreach ($r in ($roots | Sort-Object -Unique)) {
        $libs += $r
        $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            $text = Get-Content -LiteralPath $vdf -Raw
            foreach ($m in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
                $libs += ($m.Groups[1].Value -replace '\\\\', '\')
            }
        }
    }
    foreach ($lib in ($libs | Sort-Object -Unique)) {
        $p = Join-Path $lib $rel
        if (Test-Path -LiteralPath $p) { $found.Add((Get-Item -LiteralPath $p).FullName) }
    }

    # Xbox app / Microsoft Store: the default "XboxGames" folder on every local drive,
    # plus the package install folder when Windows lets us read it.
    $storeDirs = @()
    foreach ($drive in [IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -ne 'Fixed' -or -not $drive.IsReady) { continue }
        $xg = Join-Path $drive.RootDirectory.FullName 'XboxGames'
        if (Test-Path -LiteralPath $xg) {
            $storeDirs += @(Get-ChildItem -LiteralPath $xg -Directory -Filter '*eFootball*' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        }
    }
    foreach ($pkg in @(Get-AppxPackage -Name '*eFootball*' -ErrorAction SilentlyContinue)) {
        if ($pkg.InstallLocation) { $storeDirs += $pkg.InstallLocation }
    }
    foreach ($dir in ($storeDirs | Sort-Object -Unique)) {
        $exe = Get-ChildItem -LiteralPath $dir -Recurse -Filter 'eFootball*.exe' -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 50MB } | Select-Object -First 1
        if ($exe) { $found.Add($exe.FullName) }
    }

    @($found | Sort-Object -Unique)
}

function Get-AppContainerSid([string]$FamilyName) {
    if (-not ('RegionLock.UserEnv' -as [type])) {
        Add-Type -Namespace RegionLock -Name UserEnv -MemberDefinition @'
[DllImport("userenv.dll", CharSet = CharSet.Unicode)]
public static extern int DeriveAppContainerSidFromAppContainerName(string name, out IntPtr sid);
[DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool ConvertSidToStringSid(IntPtr sid, out string sidString);
[DllImport("advapi32.dll")]
public static extern IntPtr FreeSid(IntPtr sid);
'@
    }
    $ptr = [IntPtr]::Zero
    if ([RegionLock.UserEnv]::DeriveAppContainerSidFromAppContainerName($FamilyName, [ref]$ptr) -ne 0) { return $null }
    try {
        $sidString = $null
        if ([RegionLock.UserEnv]::ConvertSidToStringSid($ptr, [ref]$sidString)) { $sidString } else { $null }
    } finally {
        [void][RegionLock.UserEnv]::FreeSid($ptr)
    }
}

function Find-GamePackages {
    # Microsoft Store packages get an extra rule bound to the package identity,
    # which matches the game even when its install folder cannot be read.
    $list = @()
    foreach ($pkg in @(Get-AppxPackage -Name '*eFootball*' -ErrorAction SilentlyContinue)) {
        $sid = Get-AppContainerSid $pkg.PackageFamilyName
        if ($sid) { $list += [pscustomobject]@{ Name = $pkg.PackageFamilyName; Sid = $sid } }
    }
    $list
}

function Read-IntSetting([string]$En, [string]$Es, [int]$Default, [int]$Min, [int]$Max) {
    # Only whole numbers inside [Min, Max] are accepted; anything else is asked again.
    while ($true) {
        $raw = Read-Host ("{0} [{1}]" -f (T $En $Es), $Default)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        $raw = $raw.Trim()
        if ($raw -match '^\d{1,3}$') {
            $n = [int]$raw
            if ($n -ge $Min -and $n -le $Max) { return $n }
        }
        Say ("Please type a whole number between {0} and {1}." -f $Min, $Max) ("Escribe un numero entero entre {0} y {1}." -f $Min, $Max) 'Yellow'
    }
}

function Test-Cidr([string]$Cidr) {
    if ([string]::IsNullOrWhiteSpace($Cidr)) { return $false }
    $parts = $Cidr.Split('/')
    if ($parts.Count -ne 2) { return $false }
    $addr = $null
    if (-not [Net.IPAddress]::TryParse($parts[0], [ref]$addr)) { return $false }
    $len = 0
    if (-not [int]::TryParse($parts[1], [ref]$len)) { return $false }
    $max = 32
    if ($addr.AddressFamily -eq 'InterNetworkV6') { $max = 128 }
    ($len -ge 0 -and $len -le $max)
}

function Get-Stats([double[]]$Values) {
    # Median = typical latency. Jitter = average change between consecutive samples.
    if ($Values.Count -lt 3) { return $null }
    $sorted = @($Values | Sort-Object)
    $mid = [int][math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) { $median = $sorted[$mid] } else { $median = ($sorted[$mid - 1] + $sorted[$mid]) / 2 }
    $diff = 0.0
    for ($i = 1; $i -lt $Values.Count; $i++) { $diff += [math]::Abs($Values[$i] - $Values[$i - 1]) }
    [pscustomobject]@{
        Median = [int][math]::Round($median)
        Jitter = [int][math]::Round($diff / ($Values.Count - 1))
    }
}

function Measure-Tcp([string]$HostName, [int]$Port = 443, [int]$Samples = 5) {
    try {
        $ip = [Net.Dns]::GetHostAddresses($HostName) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
    } catch { return $null }
    if (-not $ip) { return $null }
    $vals = @()
    for ($i = 0; $i -lt $Samples; $i++) {
        $tc = New-Object Net.Sockets.TcpClient
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try {
            $ok = $tc.ConnectAsync($ip, $Port).Wait(3000)
            $sw.Stop()
            if ($ok -and $tc.Connected) { $vals += $sw.Elapsed.TotalMilliseconds }
        } catch { $sw.Stop() } finally { $tc.Close() }
    }
    Get-Stats $vals
}

function Get-Stability($Jitter) {
    if ($null -eq $Jitter) { return '-' }
    if ($Jitter -le 10) { return (T 'High' 'Alta') }
    if ($Jitter -le 30) { return (T 'Medium' 'Media') }
    T 'Low' 'Baja'
}

function Get-ToolRules {
    # Only rules this tool created: right group, right name AND our description tag.
    # A rule someone else puts in the same group is never touched.
    @(Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "$RuleGroup #*" -and $_.Description -like "$RuleTag*" })
}

function Remove-ToolRules {
    $rules = Get-ToolRules
    if ($rules.Count -gt 0) { $rules | Remove-NetFirewallRule }
    $rules.Count
}

function Show-Status {
    $rules = Get-ToolRules
    if ($rules.Count -eq 0) {
        Say 'No eFootball Region Lock rules are active.' 'No hay reglas de eFootball Region Lock activas.' 'Yellow'
    } else {
        $programs = @($rules | Get-NetFirewallApplicationFilter | Select-Object -ExpandProperty Program | Sort-Object -Unique)
        $addresses = 0
        foreach ($af in ($rules | Get-NetFirewallAddressFilter)) { $addresses += @($af.RemoteAddress).Count }
        Say ("Active rules: {0}  |  Blocked IP ranges: {1}" -f $rules.Count, $addresses) ("Reglas activas: {0}  |  Rangos de IP bloqueados: {1}" -f $rules.Count, $addresses) 'Green'
        Say 'Applies only to:' 'Solo se aplica a:'
        $programs | ForEach-Object { Write-Host "  $_" }
        $desc = ($rules | Select-Object -First 1).Description
        if ($desc) { Write-Host ''; Write-Host $desc }
    }

    $others = @(Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*eFootball*' -and $_.Group -ne $RuleGroup -and $_.Action -eq 'Block' })
    if ($others.Count -gt 0) {
        Write-Host ''
        Say 'Other eFootball firewall rules found (NOT created by this tool):' 'Otras reglas de firewall de eFootball (NO creadas por esta herramienta):' 'Yellow'
        $others | ForEach-Object { Write-Host ("  - {0}  [{1}, {2}]" -f $_.DisplayName, $_.Direction, $_.Action) }
    }
}

function Show-Banner {
    $lines = @(
        @{ Art = '         _...----..._';        Text = '';                                   Color = 'Cyan' },
        @{ Art = "       .'  \  __  /  '.";      Text = ')  )  )';                            Color = 'Cyan' },
        @{ Art = '      /  ---\/  \/---  \';     Text = '';                                   Color = 'Cyan' },
        @{ Art = '     |      |    |      |';    Text = "eFootball Region Lock  v$ToolVersion"; Color = 'White' },
        @{ Art = '      \  ---/\__/\---  /';     Text = (T 'Play on servers close to you' 'Juega en servidores cercanos a ti'); Color = 'Gray' },
        @{ Art = "       '._ /      \ _.'";      Text = '';                                   Color = 'Cyan' },
        @{ Art = "          '--....--'";         Text = $Credit;                              Color = 'Green' }
    )
    Write-Host ''
    foreach ($l in $lines) {
        Write-Host ($l.Art.PadRight(29)) -ForegroundColor Cyan -NoNewline
        Write-Host $l.Text -ForegroundColor $l.Color
    }
    Write-Host ('  ' + ('-' * 63)) -ForegroundColor DarkGray
    Write-Host ''
}

function Show-Footer {
    Write-Host ''
    Write-Host "  $Credit" -ForegroundColor Green
    Write-Host ''
}

function Get-CloudLists {
    # Official IP lists from Google and Amazon. Returns $null on failure.
    try {
        $g = Invoke-RestMethod -Uri $GcpRangesUrl -TimeoutSec 60
        $a = Invoke-RestMethod -Uri $AwsRangesUrl -TimeoutSec 60
    } catch {
        Say "Download failed: $($_.Exception.Message)" "Fallo la descarga: $($_.Exception.Message)" 'Red'
        return $null
    }
    $gc = @($g.prefixes).Count; $ac = @($a.prefixes).Count
    if ($gc -lt 100 -or $ac -lt 500) {
        Say ("The downloaded lists look incomplete (Google: {0}, Amazon: {1})." -f $gc, $ac) `
            ("Las listas descargadas parecen incompletas (Google: {0}, Amazon: {1})." -f $gc, $ac) 'Red'
        return $null
    }
    [pscustomobject]@{ Gcp = $g; Aws = $a }
}

function Measure-GcpRegion([string]$Region) {
    # Tries each official regional endpoint until one resolves and answers.
    foreach ($svc in $GcpProbeServices) {
        $stats = Measure-Tcp "$svc.$Region.rep.googleapis.com"
        if ($stats) { return $stats }
    }
    $null
}

# ---------------------------------------------------------------- IPv4 + cloud lookup

function ConvertTo-IPv4Number([string]$Ip) {
    $addr = $null
    if (-not [Net.IPAddress]::TryParse($Ip, [ref]$addr)) { return $null }
    if ($addr.AddressFamily -ne 'InterNetwork') { return $null }
    $b = $addr.GetAddressBytes()
    [int64]$b[0] * 16777216 + [int64]$b[1] * 65536 + [int64]$b[2] * 256 + [int64]$b[3]
}

function Test-PublicIPv4([string]$Ip) {
    $n = ConvertTo-IPv4Number $Ip
    if ($null -eq $n) { return $false }
    $private = @(
        @('10.0.0.0', 8), @('172.16.0.0', 12), @('192.168.0.0', 16), @('100.64.0.0', 10),
        @('127.0.0.0', 8), @('169.254.0.0', 16), @('0.0.0.0', 8), @('224.0.0.0', 3)
    )
    foreach ($r in $private) {
        $mask = (4294967295 -shl (32 - $r[1])) -band 4294967295
        if (($n -band $mask) -eq ((ConvertTo-IPv4Number $r[0]) -band $mask)) { return $false }
    }
    $true
}

function New-CloudTable($Lists) {
    # Flat list of IPv4 networks with their cloud, region and city, for fast lookups.
    $rows = New-Object System.Collections.Generic.List[object]
    function Add-Net($Cidr, $Cloud, $Region, $Location, $Kind) {
        if (-not (Test-Cidr $Cidr)) { return }
        $parts = $Cidr.Split('/')
        $net = ConvertTo-IPv4Number $parts[0]
        if ($null -eq $net) { return }
        $len = [int]$parts[1]
        $mask = 0
        if ($len -gt 0) { $mask = (4294967295 -shl (32 - $len)) -band 4294967295 }
        $rows.Add([pscustomobject]@{ Net = ($net -band $mask); Mask = $mask; Len = $len; Cloud = $Cloud; Region = $Region; Location = $Location; Kind = $Kind })
    }
    foreach ($p in $Lists.Gcp.prefixes) {
        if (-not $p.PSObject.Properties['ipv4Prefix']) { continue }
        $loc = ''
        if ($GcpNames.ContainsKey($p.scope)) { $loc = $GcpNames[$p.scope] }
        Add-Net $p.ipv4Prefix 'Google Cloud' $p.scope $loc 'region'
    }
    foreach ($p in $Lists.Aws.prefixes) {
        if ($p.service -ne 'EC2' -and $p.service -ne 'GLOBALACCELERATOR') { continue }
        $region = $p.network_border_group
        $loc = ''
        $kind = 'region'
        if ($p.service -eq 'GLOBALACCELERATOR') {
            $kind = 'edge'
        } elseif ($p.network_border_group -ne $p.region) {
            $kind = 'zone'
            if ($p.network_border_group -match '-([a-z]{2,3})-\d+$' -and $AwsZoneCities.ContainsKey($Matches[1])) { $loc = $AwsZoneCities[$Matches[1]] }
        } elseif ($AwsNames.ContainsKey($p.region)) {
            $loc = $AwsNames[$p.region]
        }
        Add-Net $p.ip_prefix 'Amazon AWS' $region $loc $kind
    }
    $rows
}

function Find-Cloud([string]$Ip, $Table) {
    # Most specific match wins.
    $n = ConvertTo-IPv4Number $Ip
    if ($null -eq $n) { return $null }
    $best = $null
    foreach ($r in $Table) {
        if (($n -band $r.Mask) -eq $r.Net) {
            if ($null -eq $best -or $r.Len -gt $best.Len) { $best = $r }
        }
    }
    $best
}

# ---------------------------------------------------------------- match detection (pktmon)

function Get-GamePorts([int]$ProcessId) {
    @(Get-NetUDPEndpoint -OwningProcess $ProcessId -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -gt 0 } | Select-Object -ExpandProperty LocalPort | Sort-Object -Unique)
}

function Invoke-Pktmon([string[]]$Arguments) {
    # pktmon writes normal messages (e.g. "packet monitoring is not running") to stderr.
    # Windows PowerShell 5.1 would turn them into terminating errors, so stderr is discarded
    # here and only the exit code is used to decide whether a step failed.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & pktmon.exe @Arguments 2>$null | Out-Null
        $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Invoke-PktmonCapture([int[]]$Ports, [int]$Seconds) {
    # Captures only packet HEADERS (first 128 bytes) of UDP traffic on the game's ports,
    # using pktmon, the packet monitor built into Windows. Nothing is changed or delayed.
    $work = Join-Path $env:TEMP ("efrl-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $etl = Join-Path $work 'capture.etl'
    $txt = Join-Path $work 'capture.txt'
    try {
        [void](Invoke-Pktmon @('stop'))              # fine if nothing was running
        [void](Invoke-Pktmon @('filter', 'remove'))
        $i = 0
        foreach ($port in ($Ports | Select-Object -First 16)) {
            $i++
            $code = Invoke-Pktmon @('filter', 'add', ("efrl" + $i), '-t', 'UDP', '-p', [string]$port)
            if ($code -ne 0) { throw "pktmon filter add failed (code $code)" }
        }
        $code = Invoke-Pktmon @('start', '--capture', '--comp', 'nics', '--pkt-size', '128', '--file-name', $etl)
        if ($code -ne 0) { throw "pktmon start failed (code $code)" }
        Start-Sleep -Seconds $Seconds
        [void](Invoke-Pktmon @('stop'))
        [void](Invoke-Pktmon @('etl2txt', $etl, '--out', $txt))
        if (-not (Test-Path -LiteralPath $txt)) { throw 'pktmon etl2txt produced no output' }
        Get-Content -LiteralPath $txt
    } finally {
        [void](Invoke-Pktmon @('stop'))
        [void](Invoke-Pktmon @('filter', 'remove'))
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-RemoteCounts([string[]]$Lines, [int[]]$Ports) {
    # Reads "a.b.c.d.port > e.f.g.h.port:" pairs and counts packets per public remote address.
    $counts = @{}
    $rx = [regex]'(\d{1,3}(?:\.\d{1,3}){3})\.(\d{1,5}) > (\d{1,3}(?:\.\d{1,3}){3})\.(\d{1,5}):'
    foreach ($line in $Lines) {
        $m = $rx.Match($line)
        if (-not $m.Success) { continue }
        $src = $m.Groups[1].Value; $sport = [int]$m.Groups[2].Value
        $dst = $m.Groups[3].Value; $dport = [int]$m.Groups[4].Value
        $remote = $null
        if ($Ports -contains $sport) { $remote = $dst } elseif ($Ports -contains $dport) { $remote = $src }
        if (-not $remote -or -not (Test-PublicIPv4 $remote)) { continue }
        if ($counts.ContainsKey($remote)) { $counts[$remote]++ } else { $counts[$remote] = 1 }
    }
    $counts
}

function Find-MatchPeer {
    # Returns @{ Ip; Packets; ProcessId } for the busiest public UDP peer of the game, or $null.
    $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) {
        Say "$ProcessName is not running. Open the game and start (or join) a match first." `
            "$ProcessName no esta abierto. Abre el juego y entra en un partido primero." 'Yellow'
        return $null
    }
    $ports = Get-GamePorts $proc.Id
    if ($ports.Count -eq 0) {
        Say 'The game has no network ports open right now. Try again once the match starts.' `
            'El juego no tiene puertos de red abiertos ahora mismo. Vuelve a intentarlo cuando empiece el partido.' 'Yellow'
        return $null
    }
    Say ("Looking at {0} seconds of the game's traffic (headers only, nothing is changed)..." -f $CaptureSeconds) `
        ("Observando {0} segundos del trafico del juego (solo cabeceras, no se cambia nada)..." -f $CaptureSeconds)
    try {
        $lines = Invoke-PktmonCapture $ports $CaptureSeconds
    } catch {
        Say "Packet capture failed: $($_.Exception.Message)" "Fallo la captura: $($_.Exception.Message)" 'Red'
        return $null
    }
    $counts = Get-RemoteCounts $lines $ports
    if ($counts.Count -eq 0) { return [pscustomobject]@{ Ip = $null; Packets = 0; ProcessId = $proc.Id } }
    $top = $counts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
    [pscustomobject]@{ Ip = $top.Key; Packets = [int]$top.Value; ProcessId = $proc.Id }
}

function Measure-Icmp([string]$Ip, [int]$Count = 10, [int]$IntervalMs = 300) {
    $ping = New-Object Net.NetworkInformation.Ping
    $vals = @()
    $lost = 0
    for ($i = 0; $i -lt $Count; $i++) {
        try {
            $r = $ping.Send($Ip, 1000)
            if ($r.Status -eq 'Success') { $vals += [double]$r.RoundtripTime } else { $lost++ }
        } catch { $lost++ }
        Start-Sleep -Milliseconds $IntervalMs
    }
    $ping.Dispose()
    $stats = Get-Stats $vals
    [pscustomobject]@{
        Ping   = $(if ($stats) { $stats.Median } else { $null })
        Jitter = $(if ($stats) { $stats.Jitter } else { $null })
        Loss   = [int][math]::Round(100 * $lost / $Count)
    }
}

function Get-Quality($Ping, $Jitter, $Loss) {
    if ($null -eq $Ping) { return (T 'Unknown' 'Desconocida') }
    if ($Ping -le 60 -and $Jitter -le 10 -and $Loss -eq 0) { return (T 'Good' 'Buena') }
    if ($Ping -le 100 -and $Jitter -le 25 -and $Loss -le 2) { return (T 'Fair' 'Regular') }
    T 'Poor' 'Mala'
}

function Get-MatchInfo($Peer, $Table) {
    $cloud = Find-Cloud $Peer.Ip $Table
    if ($cloud) {
        $where = $cloud.Region
        if ($cloud.Location) { $where = "$($cloud.Region) ($($cloud.Location))" }
        $type = T 'Game server' 'Servidor de juego'
        if ($cloud.Kind -eq 'edge') {
            $type = T 'Game server (Amazon edge network)' 'Servidor de juego (red edge de Amazon)'
            $where = T 'Amazon edge address (exact city cannot be identified)' 'Direccion edge de Amazon (no se puede saber la ciudad exacta)'
        }
        [pscustomobject]@{ Type = 'Server'; TypeText = $type; Cloud = $cloud.Cloud; Region = $cloud.Region; Location = $cloud.Location; Where = $where }
    } else {
        [pscustomobject]@{ Type = 'P2P'; TypeText = (T 'Peer-to-peer (directly with the other player)' 'Peer-to-peer (directo con el otro jugador)');
                           Cloud = '-'; Region = '-'; Location = '-'; Where = '-' }
    }
}

function Save-History($Info, $Stats, [string]$Source) {
    # Saved only on this PC. The opponent's IP address is never saved.
    try {
        if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
        [pscustomobject]@{
            Date     = (Get-Date -Format 'yyyy-MM-dd HH:mm')
            Source   = $Source
            Type     = $Info.Type
            Cloud    = $Info.Cloud
            Region   = $Info.Region
            Location = $Info.Location
            PingMs   = $Stats.Ping
            JitterMs = $Stats.Jitter
            LossPct  = $Stats.Loss
            Quality  = (Get-Quality $Stats.Ping $Stats.Jitter $Stats.Loss)
        } | Export-Csv -LiteralPath $HistoryFile -Append -NoTypeInformation -Encoding UTF8
        return $true
    } catch {
        Say "Could not save the match history: $($_.Exception.Message)" "No se pudo guardar el historial: $($_.Exception.Message)" 'Yellow'
        return $false
    }
}

function Show-MatchCard($Info, $Stats, [int]$Packets) {
    $color = 'Green'
    $q = Get-Quality $Stats.Ping $Stats.Jitter $Stats.Loss
    if ($q -eq (T 'Fair' 'Regular')) { $color = 'Yellow' } elseif ($q -ne (T 'Good' 'Buena')) { $color = 'Red' }
    Write-Host ''
    Say '  Current match' '  Partido actual' 'Cyan'
    Write-Host ('  ' + ('-' * 40)) -ForegroundColor DarkGray
    Write-Host ("  {0,-11}: {1}" -f (T 'Type' 'Tipo'), $Info.TypeText)
    if ($Info.Type -eq 'Server') {
        Write-Host ("  {0,-11}: {1}" -f (T 'Cloud' 'Nube'), $Info.Cloud)
        Write-Host ("  {0,-11}: {1}" -f (T 'Region' 'Region'), $Info.Where)
    }
    if ($null -eq $Stats.Ping) {
        Write-Host ("  {0,-11}: {1}" -f 'Ping', (T 'no reply (this server ignores ping)' 'sin respuesta (este servidor ignora el ping)')) -ForegroundColor Yellow
    } else {
        Write-Host ("  {0,-11}: {1} ms   Jitter: {2} ms   {3}: {4}%" -f 'Ping', $Stats.Ping, $Stats.Jitter, (T 'Loss' 'Perdida'), $Stats.Loss) -ForegroundColor $color
    }
    Write-Host ("  {0,-11}: {1}" -f (T 'Quality' 'Calidad'), $q) -ForegroundColor $color
    Write-Host ("  {0,-11}: {1} {2}" -f (T 'Traffic' 'Trafico'), $Packets, (T "packets in $CaptureSeconds s" "paquetes en $CaptureSeconds s")) -ForegroundColor DarkGray
    if ($Info.Type -eq 'P2P') {
        Write-Host ''
        Say '  This match goes directly between players, so the firewall rules of this tool do not affect it.' `
            '  Este partido va directo entre jugadores, asi que las reglas de esta herramienta no lo afectan.' 'Yellow'
    }
}

function Show-History {
    if (-not (Test-Path -LiteralPath $HistoryFile)) {
        Say 'No matches saved yet. Use "Check current match" or "Live monitor" during a match.' `
            'Todavia no hay partidos guardados. Usa "Revisar partido actual" o "Monitor en vivo" durante un partido.' 'Yellow'
        return
    }
    $rows = @(Import-Csv -LiteralPath $HistoryFile)
    Say ("Last matches (saved in {0}):" -f $HistoryFile) ("Ultimos partidos (guardados en {0}):" -f $HistoryFile) 'Cyan'
    $rows | Select-Object -Last 20 |
        Format-Table @{ Label = (T 'Date' 'Fecha'); Expression = { $_.Date } },
                     @{ Label = (T 'Type' 'Tipo'); Expression = { $_.Type } },
                     @{ Label = (T 'Cloud' 'Nube'); Expression = { $_.Cloud } },
                     @{ Label = (T 'Region' 'Region'); Expression = { $_.Region } },
                     @{ Label = (T 'City' 'Ciudad'); Expression = { $_.Location } },
                     @{ Label = 'Ping'; Expression = { $_.PingMs }; Align = 'Right' },
                     @{ Label = 'Jitter'; Expression = { $_.JitterMs }; Align = 'Right' },
                     @{ Label = (T 'Loss %' 'Perdida %'); Expression = { $_.LossPct }; Align = 'Right' },
                     @{ Label = (T 'Quality' 'Calidad'); Expression = { $_.Quality } } -AutoSize | Out-Host
    Say 'Summary by server:' 'Resumen por servidor:' 'Cyan'
    $rows | Group-Object { if ($_.Type -eq 'P2P') { 'Peer-to-peer' } else { "$($_.Cloud) $($_.Region) $($_.Location)".Trim() } } | ForEach-Object {
        $pings = @($_.Group | Where-Object { $_.PingMs -match '^\d+$' } | ForEach-Object { [int]$_.PingMs })
        $avg = '-'
        if ($pings.Count -gt 0) { $avg = [int][math]::Round(($pings | Measure-Object -Average).Average) }
        [pscustomobject]@{ Server = $_.Name; Matches = $_.Count; AvgPing = $avg }
    } | Sort-Object Matches -Descending |
        Format-Table @{ Label = (T 'Server' 'Servidor'); Expression = { $_.Server } },
                     @{ Label = (T 'Matches' 'Partidos'); Expression = { $_.Matches }; Align = 'Right' },
                     @{ Label = (T 'Avg ping' 'Ping medio'); Expression = { $_.AvgPing }; Align = 'Right' } -AutoSize | Out-Host
}

function Start-LiveMonitor([string]$Ip, [int]$ProcessId) {
    $ping = New-Object Net.NetworkInformation.Ping
    $window = New-Object System.Collections.Generic.List[object]
    $all = New-Object System.Collections.Generic.List[double]
    $sent = 0; $lostTotal = 0; $failStreak = 0
    # Throw away keys pressed before the monitor started (menu choice, Alt+Tab...),
    # otherwise they would stop the monitor on its very first second.
    try { while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) } } catch { }
    Say 'Live monitor running. Press any key to stop.' 'Monitor en vivo activo. Pulsa cualquier tecla para parar.' 'Cyan'
    Write-Host ''
    while ($true) {
        $tick = [Diagnostics.Stopwatch]::StartNew()
        $stop = $false
        # Ignore keys during the first 2 seconds, in case a key was still on its way.
        try { if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); if ($sent -ge 2) { $stop = $true } } } catch { }
        if ($stop) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { break }

        $rtt = $null
        try { $r = $ping.Send($Ip, 1000); if ($r.Status -eq 'Success') { $rtt = [double]$r.RoundtripTime } } catch { }
        $sent++
        if ($null -eq $rtt) { $lostTotal++; $failStreak++ } else { $failStreak = 0; $all.Add($rtt) }
        $window.Add($rtt)
        if ($window.Count -gt 30) { $window.RemoveAt(0) }

        $ok = @($window | Where-Object { $null -ne $_ })
        $s = $null
        if ($ok.Count -ge 3) { $s = Get-Stats ([double[]]$ok) }
        $loss = [int][math]::Round(100 * ($window.Count - $ok.Count) / $window.Count)
        $now = '---'; if ($null -ne $rtt) { $now = "$rtt ms" }
        $med = '-'; $jit = '-'
        if ($s) { $med = "$($s.Median) ms"; $jit = "$($s.Jitter) ms" }
        $q = '-'; if ($s) { $q = Get-Quality $s.Median $s.Jitter $loss }
        $line = "  Ping {0,-7} | {1} {2,-7} | Jitter {3,-6} | {4} {5,3}% | {6}" -f $now, (T 'median' 'mediana'), $med, $jit, (T 'loss' 'perdida'), $loss, $q
        Write-Host ("`r" + $line.PadRight(95)) -NoNewline

        if ($failStreak -ge 10) {
            Write-Host ''
            Say 'No replies for 10 seconds: the match probably ended or the server ignores ping.' `
                'Sin respuesta durante 10 segundos: probablemente termino el partido o el servidor ignora el ping.' 'Yellow'
            break
        }
        $wait = 1000 - [int]$tick.ElapsedMilliseconds
        if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
    }
    Write-Host ''
    $ping.Dispose()
    $stats = Get-Stats ([double[]]$all.ToArray())
    [pscustomobject]@{
        Ping   = $(if ($stats) { $stats.Median } else { $null })
        Jitter = $(if ($stats) { $stats.Jitter } else { $null })
        Loss   = $(if ($sent -gt 0) { [int][math]::Round(100 * $lostTotal / $sent) } else { 0 })
        Sent   = $sent
    }
}

# ---------------------------------------------------------------- manual region picker

function Invoke-ManualPick($Results, $AllowedKeys) {
    # Lets the user switch regions on/off. Protected regions, regions without data and
    # AlwaysAllow regions can never be blocked, so they are shown as locked.
    $list = @($Results | Sort-Object @{ Expression = { if ($null -eq $_.Ping) { 99999 } else { $_.Ping } } })
    $keep = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($k in $AllowedKeys) { [void]$keep.Add($k) }
    while ($true) {
        Write-Host ''
        Say '  #   Keep  Cloud   Region                   City              Latency' '  #   Usar  Nube    Region                   Ciudad            Latencia' 'Cyan'
        for ($i = 0; $i -lt $list.Count; $i++) {
            $r = $list[$i]
            $key = "$($r.Provider)/$($r.Region)"
            $locked = ($null -eq $r.Ping) -or ($AlwaysAllow -contains $r.Region) -or ($r.Provider -eq 'Amazon' -and $ProtectedAws -contains $r.Region)
            if ($locked) { $mark = ' * ' } elseif ($keep.Contains($key)) { $mark = '[x]' } else { $mark = '[ ]' }
            $lat = '-'; if ($null -ne $r.Ping) { $lat = "$($r.Ping) ms" }
            $color = 'DarkGray'
            if ($locked) { $color = 'DarkCyan' } elseif ($keep.Contains($key)) { $color = 'Green' }
            Write-Host ("  {0,3} {1}  {2,-7} {3,-24} {4,-17} {5,8}" -f ($i + 1), $mark, $r.Provider, $r.Region, $r.Location, $lat) -ForegroundColor $color
        }
        Write-Host ''
        Say '  [x] kept   [ ] blocked   * always open (game services, no data or your list)' '  [x] se usa   [ ] bloqueada   * siempre abierta (servicios del juego, sin datos o tu lista)' 'DarkGray'
        $kept = @($list | Where-Object { $keep.Contains("$($_.Provider)/$($_.Region)") })
        Say ("  Regions kept: {0}" -f $kept.Count) ("  Regiones que se usan: {0}" -f $kept.Count) 'Green'
        $raw = Read-Host (T 'Numbers to switch on/off (e.g. 3 7 12), Enter = done, Q = cancel' 'Numeros para activar/desactivar (ej. 3 7 12), Enter = listo, Q = cancelar')
        if ($null -eq $raw) { $raw = '' }
        $raw = $raw.Trim()
        if ($raw -match '^(q|Q)$') { return $null }
        if ($raw -eq '') {
            if ($kept.Count -eq 0) {
                Say 'Keep at least one region, or you will not find matches.' 'Deja al menos una region, o no encontraras partidos.' 'Yellow'
                continue
            }
            return ,$keep
        }
        foreach ($tok in ($raw -split '[\s,]+')) {
            if ($tok -notmatch '^\d{1,3}$') { Say "  Ignored: $tok" "  Ignorado: $tok" 'Yellow'; continue }
            $idx = [int]$tok - 1
            if ($idx -lt 0 -or $idx -ge $list.Count) { Say "  Out of range: $tok" "  Fuera de rango: $tok" 'Yellow'; continue }
            $r = $list[$idx]
            $key = "$($r.Provider)/$($r.Region)"
            $locked = ($null -eq $r.Ping) -or ($AlwaysAllow -contains $r.Region) -or ($r.Provider -eq 'Amazon' -and $ProtectedAws -contains $r.Region)
            if ($locked) { Say "  $($r.Region) is always open." "  $($r.Region) siempre esta abierta." 'Yellow'; continue }
            if ($keep.Contains($key)) { [void]$keep.Remove($key) } else { [void]$keep.Add($key) }
        }
    }
}

# ---------------------------------------------------------------- main

Show-Banner

$needsAdmin = @('Apply', 'Pick', 'Match', 'Monitor', 'Remove')
if ($needsAdmin -contains $Mode -and -not (Test-Admin)) {
    Say 'This option needs administrator rights. Right-click Run.bat and choose "Run as administrator".' `
        'Esta opcion necesita permisos de administrador. Haz clic derecho en Run.bat y elige "Ejecutar como administrador".' 'Red'
    exit 1
}

if ($Mode -eq 'Status') { Show-Status; Show-Footer; exit 0 }

if ($Mode -eq 'History') { Show-History; Show-Footer; exit 0 }

if ($Mode -eq 'Remove') {
    $n = Remove-ToolRules
    Say ("Removed {0} rule(s). eFootball can use every server again." -f $n) ("Se quitaron {0} regla(s). eFootball vuelve a poder usar todos los servidores." -f $n) 'Green'
    Show-Footer
    exit 0
}

if ($Mode -eq 'Match' -or $Mode -eq 'Monitor') {
    if (-not (Get-Command pktmon.exe -ErrorAction SilentlyContinue) -or [Environment]::OSVersion.Version.Build -lt 19041) {
        Say 'This option needs Windows 10 version 2004 or newer (pktmon).' 'Esta opcion necesita Windows 10 version 2004 o superior (pktmon).' 'Red'
        exit 1
    }
    $peer = Find-MatchPeer
    if (-not $peer) { Show-Footer; exit 1 }
    $minPackets = 10 * $CaptureSeconds
    if (-not $peer.Ip -or $peer.Packets -lt $minPackets) {
        Say 'No match traffic found. Run this while a match is being played (not in the menus).' `
            'No se encontro trafico de partido. Usalo mientras se juega un partido (no en los menus).' 'Yellow'
        Show-Footer
        exit 1
    }
    Say 'Identifying the server with the official Google and Amazon IP lists...' 'Identificando el servidor con las listas oficiales de IP de Google y Amazon...'
    $lists = Get-CloudLists
    if (-not $lists) { Show-Footer; exit 1 }
    $info = Get-MatchInfo $peer (New-CloudTable $lists)

    $saved = $false
    if ($Mode -eq 'Match') {
        Say 'Measuring ping, jitter and packet loss (10 pings)...' 'Midiendo ping, jitter y perdida de paquetes (10 pings)...'
        $stats = Measure-Icmp $peer.Ip 10 300
        Show-MatchCard $info $stats $peer.Packets
        $saved = Save-History $info $stats 'Check'
    } else {
        Write-Host ''
        Write-Host ("  {0}: {1}   {2}" -f (T 'Server' 'Servidor'), $info.Where, $info.TypeText) -ForegroundColor Cyan
        $stats = Start-LiveMonitor $peer.Ip $peer.ProcessId
        if ($stats.Sent -ge 3) {
            Show-MatchCard $info $stats $peer.Packets
            $saved = Save-History $info $stats 'Monitor'
        } else {
            Say 'The monitor stopped before it could measure anything, so nothing was saved.' `
                'El monitor se detuvo antes de poder medir, asi que no se guardo nada.' 'Yellow'
        }
    }
    Write-Host ''
    if ($saved) {
        Say 'Saved in your match history (only on this PC, without the opponent''s IP).' 'Guardado en tu historial (solo en este PC, sin la IP del rival).' 'DarkGray'
    }
    Show-Footer
    exit 0
}

# --- Apply / DryRun / Pick from here on

# --- interactive settings (Run.bat option 3): validated here, never passed through CMD
if ($AskSettings) {
    $MaxPing    = Read-IntSetting 'Max latency in ms (10-500)' 'Latencia maxima en ms (10-500)' $MaxPing 10 500
    $MaxServers = Read-IntSetting 'Max servers to keep, 0 = no limit (0-50)' 'Maximo de servidores, 0 = sin limite (0-50)' $MaxServers 0 50
    Write-Host ''
}

# --- game executable
if ($GamePath) {
    $exes = @()
    foreach ($p in $GamePath) {
        if (Test-Path -LiteralPath $p) { $exes += (Get-Item -LiteralPath $p).FullName }
        else { Say "File not found: $p" "No se encontro el archivo: $p" 'Red'; exit 1 }
    }
} else {
    $exes = @(Find-GameExe)
}
$packages = @()
if (-not $GamePath) { $packages = @(Find-GamePackages) }

if ($exes.Count -eq 0 -and $packages.Count -eq 0) {
    Say 'eFootball was not found automatically (Steam / Xbox app).' 'No se encontro eFootball automaticamente (Steam / app de Xbox).' 'Yellow'
    Say 'Run again with: -GamePath "C:\path\to\eFootball.exe"' 'Vuelve a ejecutarlo con: -GamePath "C:\ruta\a\eFootball.exe"' 'Yellow'
    if ($Mode -ne 'DryRun') { exit 1 }
} else {
    Say 'Game found:' 'Juego encontrado:'
    $exes | ForEach-Object { Write-Host "  $_" -ForegroundColor Green }
    $packages | ForEach-Object { Write-Host ("  Microsoft Store: {0}" -f $_.Name) -ForegroundColor Green }
}

$targets = @()
$targets += @($exes | ForEach-Object { @{ Program = $_ } })
$targets += @($packages | ForEach-Object { @{ Package = $_.Sid } })
Write-Host ''

# --- official IP lists (validated)
Say 'Downloading official IP lists from Google and Amazon...' 'Descargando las listas oficiales de IP de Google y Amazon...'
$lists = Get-CloudLists
if (-not $lists) { Say 'Nothing was changed.' 'No se cambio nada.' 'Red'; exit 1 }
$gcp = $lists.Gcp; $aws = $lists.Aws

# --- regions to measure (only well-formed region codes)
$regionPattern = '^[a-z0-9-]+$'
$gcpRegions = @($gcp.prefixes | ForEach-Object { $_.scope } |
    Where-Object { $_ -and $_ -ne 'global' -and $_ -cmatch $regionPattern } | Sort-Object -Unique)
$awsRegions = @($aws.prefixes |
    Where-Object { $_.service -eq 'EC2' -and $_.region -eq $_.network_border_group -and $_.region -cmatch $regionPattern -and $_.region -notlike 'cn-*' -and $_.region -notlike 'us-gov-*' } |
    ForEach-Object { $_.region } | Sort-Object -Unique)

$results = New-Object System.Collections.Generic.List[object]
$total = $gcpRegions.Count + $awsRegions.Count
$done = 0
Say ("Measuring latency to {0} regions, 5 samples each (about 2-3 minutes)..." -f $total) ("Midiendo la latencia a {0} regiones, 5 muestras cada una (2-3 minutos aprox.)..." -f $total)

function New-Result($Provider, $Region, $Location, $Stats) {
    $ping = $null; $jit = $null
    if ($Stats) { $ping = $Stats.Median; $jit = $Stats.Jitter }
    [pscustomobject]@{ Provider = $Provider; Region = $Region; Location = $Location; Ping = $ping; Jitter = $jit; Decision = ''; Blocked = $false }
}

foreach ($r in $gcpRegions) {
    $done++
    Write-Progress -Activity 'eFootball Region Lock' -Status "Google Cloud: $r" -PercentComplete ([int](100 * $done / $total))
    $loc = ''
    if ($GcpNames.ContainsKey($r)) { $loc = $GcpNames[$r] }
    $results.Add((New-Result 'Google' $r $loc (Measure-GcpRegion $r)))
}
foreach ($r in $awsRegions) {
    $done++
    Write-Progress -Activity 'eFootball Region Lock' -Status "Amazon: $r" -PercentComplete ([int](100 * $done / $total))
    $loc = ''
    if ($AwsNames.ContainsKey($r)) { $loc = $AwsNames[$r] }
    $results.Add((New-Result 'Amazon' $r $loc (Measure-Tcp "ec2.$r.amazonaws.com")))
}
Write-Progress -Activity 'eFootball Region Lock' -Completed

# --- decide (automatic)
$allowedKeys = New-Object 'System.Collections.Generic.HashSet[string]'
$count = 0
foreach ($row in ($results | Where-Object { $null -ne $_.Ping } | Sort-Object Ping)) {
    $underLimit = ($MaxServers -le 0) -or ($count -lt $MaxServers)
    if (($count -lt $MinServers) -or (($row.Ping -le $MaxPing) -and $underLimit)) {
        [void]$allowedKeys.Add("$($row.Provider)/$($row.Region)")
        $count++
    }
}

# --- manual choice (Pick)
$keptLabel = T 'ALLOWED (close)' 'PERMITIDO (cerca)'
if ($Mode -eq 'Pick') {
    Write-Host ''
    Say 'Automatic suggestion is pre-selected. Switch regions on or off by number.' 'La sugerencia automatica viene marcada. Activa o desactiva regiones por numero.' 'Cyan'
    $picked = Invoke-ManualPick $results $allowedKeys
    if ($null -eq $picked) { Say 'Cancelled. Nothing was changed.' 'Cancelado. No se cambio nada.' 'Yellow'; exit 0 }
    $allowedKeys = $picked
    $keptLabel = T 'ALLOWED (your choice)' 'PERMITIDO (tu eleccion)'
}

$blockedLabel = T 'BLOCKED' 'BLOQUEADO'
foreach ($row in $results) {
    $key = "$($row.Provider)/$($row.Region)"
    if ($allowedKeys.Contains($key)) {
        $row.Decision = $keptLabel
    } elseif ($AlwaysAllow -contains $row.Region) {
        $row.Decision = T 'ALLOWED (your list)' 'PERMITIDO (tu lista)'
    } elseif ($row.Provider -eq 'Amazon' -and $ProtectedAws -contains $row.Region) {
        $row.Decision = T 'ALLOWED (game services)' 'PERMITIDO (servicios del juego)'
    } elseif ($null -eq $row.Ping) {
        $row.Decision = T 'ALLOWED (no data)' 'PERMITIDO (sin datos)'
    } else {
        $row.Decision = $blockedLabel
    }
    $row.Blocked = ($row.Decision -eq $blockedLabel)
}

Write-Host ''
$results | Sort-Object @{ Expression = { if ($null -eq $_.Ping) { 99999 } else { $_.Ping } } } |
    Format-Table @{ Label = (T 'Cloud' 'Nube'); Expression = { $_.Provider } },
                 @{ Label = (T 'Region' 'Region'); Expression = { $_.Region } },
                 @{ Label = (T 'Location' 'Ubicacion'); Expression = { $_.Location } },
                 @{ Label = (T 'Latency est. (ms)' 'Latencia est. (ms)'); Expression = { if ($null -eq $_.Ping) { '-' } else { $_.Ping } }; Align = 'Right' },
                 @{ Label = 'Jitter (ms)'; Expression = { if ($null -eq $_.Jitter) { '-' } else { $_.Jitter } }; Align = 'Right' },
                 @{ Label = (T 'Stability' 'Estabilidad'); Expression = { Get-Stability $_.Jitter } },
                 @{ Label = (T 'Decision' 'Decision'); Expression = { $_.Decision } } -AutoSize | Out-Host
Say 'Latency is the median of 5 samples to each region''s test endpoint: an estimate, not the exact ping of a match.' `
    'La latencia es la mediana de 5 muestras al punto de prueba de cada region: una estimacion, no el ping exacto de un partido.' 'DarkGray'
Write-Host ''

$close = @($results | Where-Object { $allowedKeys.Contains("$($_.Provider)/$($_.Region)") } | Sort-Object Ping)
Say 'Match servers you will keep:' 'Servidores de partido que se mantienen:' 'Green'
$close | ForEach-Object { Write-Host ("  {0,-7} {1,-24} {2,-16} {3} ms" -f $_.Provider, $_.Region, $_.Location, $_.Ping) -ForegroundColor Green }

# --- build the block list
$blockedGcp = @($results | Where-Object { $_.Blocked -and $_.Provider -eq 'Google' } | ForEach-Object { $_.Region })
$blockedAws = @($results | Where-Object { $_.Blocked -and $_.Provider -eq 'Amazon' } | ForEach-Object { $_.Region })

$ranges = New-Object 'System.Collections.Generic.HashSet[string]'
$invalid = 0
function Add-Range([string]$Cidr) {
    if (Test-Cidr $Cidr) { [void]$script:ranges.Add($Cidr) } else { $script:invalid++ }
}
foreach ($p in $gcp.prefixes) {
    if ($blockedGcp -contains $p.scope) {
        if ($p.PSObject.Properties['ipv4Prefix']) { Add-Range $p.ipv4Prefix }
        if ($p.PSObject.Properties['ipv6Prefix']) { Add-Range $p.ipv6Prefix }
    }
}
foreach ($p in $aws.prefixes) {
    if ($p.service -eq 'EC2' -and $p.region -eq $p.network_border_group -and $blockedAws -contains $p.region) { Add-Range $p.ip_prefix }
}
foreach ($p in $aws.ipv6_prefixes) {
    if ($p.service -eq 'EC2' -and $p.region -eq $p.network_border_group -and $blockedAws -contains $p.region) { Add-Range $p.ipv6_prefix }
}
$rangeList = @($ranges | Sort-Object)
if ($invalid -gt 0) {
    Say ("Skipped {0} malformed IP range(s) from the downloaded lists." -f $invalid) ("Se ignoraron {0} rango(s) de IP mal formados en las listas descargadas." -f $invalid) 'Yellow'
}

Write-Host ''
Say ("Regions to block: {0}  |  IP ranges: {1}" -f ($blockedGcp.Count + $blockedAws.Count), $rangeList.Count) `
    ("Regiones a bloquear: {0}  |  Rangos de IP: {1}" -f ($blockedGcp.Count + $blockedAws.Count), $rangeList.Count) 'Cyan'

if ($Mode -eq 'DryRun') {
    Write-Host ''
    Say 'Simulation only: nothing was changed.' 'Solo simulacion: no se cambio nada.' 'Yellow'
    Show-Footer
    exit 0
}

if ($rangeList.Count -eq 0) {
    Say 'Nothing to block with these settings.' 'No hay nada que bloquear con estos ajustes.' 'Yellow'
    exit 0
}

# --- confirm
if (Get-Process -Name 'eFootball' -ErrorAction SilentlyContinue) {
    Say 'eFootball is running. Do NOT apply this during a match: stay in the menus.' `
        'eFootball esta abierto. NO lo apliques durante un partido: quedate en los menus.' 'Yellow'
}
if (-not $Yes) {
    $answer = Read-Host (T 'Apply these firewall rules? (Y/N)' 'Aplicar estas reglas de firewall? (S/N)')
    if ($answer -notmatch '^(y|yes|s|si)$') {
        Say 'Cancelled. Nothing was changed.' 'Cancelado. No se cambio nada.' 'Yellow'
        exit 0
    }
}

# --- apply: create the new rules first, and only then remove the old ones.
# If anything fails half-way, the new rules are rolled back and the old ones stay in place.
$oldRules = Get-ToolRules

$keepText = ($close | ForEach-Object { "$($_.Provider) $($_.Region) ($($_.Location), $($_.Ping) ms)" }) -join '; '
$description = "$RuleTag v$ToolVersion on $(Get-Date -Format 'yyyy-MM-dd HH:mm'). " +
               "Mode=$Mode MaxPing=$MaxPing MaxServers=$MaxServers MinServers=$MinServers. Kept: $keepText"

$newNames = New-Object System.Collections.Generic.List[string]
try {
    foreach ($target in $targets) {
        $part = 0
        for ($i = 0; $i -lt $rangeList.Count; $i += $ChunkSize) {
            $part++
            $chunk = $rangeList[$i..([Math]::Min($i + $ChunkSize - 1, $rangeList.Count - 1))]
            $rule = New-NetFirewallRule -DisplayName "$RuleGroup #$part" -Group $RuleGroup -Description $description `
                -Direction Outbound -Action Block -Protocol UDP -RemoteAddress $chunk @target
            $newNames.Add($rule.Name)
        }
    }
} catch {
    Say "Could not create the firewall rules: $($_.Exception.Message)" "No se pudieron crear las reglas de firewall: $($_.Exception.Message)" 'Red'
    foreach ($n in $newNames) { Remove-NetFirewallRule -Name $n -ErrorAction SilentlyContinue }
    Say 'The partial changes were undone. Your previous rules (if any) were kept.' 'Se deshicieron los cambios a medias. Tus reglas anteriores (si las habia) se mantienen.' 'Yellow'
    exit 1
}
if ($oldRules.Count -gt 0) {
    $oldRules | Remove-NetFirewallRule
    Say ("Replaced {0} previous rule(s)." -f $oldRules.Count) ("Se reemplazaron {0} regla(s) anteriores." -f $oldRules.Count)
}
$created = $newNames.Count

Write-Host ''
Say ("Done: {0} rule(s) created, only for eFootball and only for UDP." -f $created) `
    ("Listo: {0} regla(s) creadas, solo para eFootball y solo para UDP." -f $created) 'Green'
Say 'To undo everything, run Run.bat and choose "Remove".' 'Para deshacerlo todo, abre Run.bat y elige "Quitar".' 'Green'
Say 'Re-run it every few weeks: Google and Amazon add new IP ranges.' 'Vuelve a ejecutarlo cada pocas semanas: Google y Amazon agregan rangos nuevos.' 'Gray'
Show-Footer
