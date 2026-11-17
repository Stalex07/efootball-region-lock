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

    Never blocked:
      - Amazon regions that host eFootball's central services
        (ap-northeast-1 Tokyo, us-west-2 Oregon, eu-west-1 Ireland).
      - Amazon Local Zones / edge servers and Global Accelerator addresses
        (they cannot be located by ping).
      - Google "global" services.
      - Any region whose latency could not be measured.

.PARAMETER Mode
    Apply  : measure, then create the firewall rules (default).
    DryRun : measure and show what would be blocked. Changes nothing.
    Remove : delete every rule created by this tool.
    Status : show the rules currently in place.

.PARAMETER MaxPing
    Highest latency (ms) a region may have to stay allowed. Default 100.

.PARAMETER MaxServers
    Keep at most this many regions (the closest ones). 0 = no limit. Default 4.

.PARAMETER MinServers
    Always keep at least this many regions, even if they exceed MaxPing,
    so you can still find matches. Default 2.

.PARAMETER GamePath
    Path(s) to eFootball.exe. Detected automatically for Steam and the Xbox app (Microsoft Store) if omitted.

.PARAMETER AlwaysAllow
    Region codes that must never be blocked, e.g. southamerica-east1, sa-east-1.

.EXAMPLE
    .\eFootball-RegionLock.ps1 -Mode DryRun

.EXAMPLE
    .\eFootball-RegionLock.ps1 -MaxPing 80 -MaxServers 3

.EXAMPLE
    .\eFootball-RegionLock.ps1 -Mode Remove
#>
[CmdletBinding()]
param(
    [ValidateSet('Apply', 'DryRun', 'Remove', 'Status')]
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

    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$ToolVersion  = '1.1.0'
$Credit       = 'Powered by @mrstalex'
$RuleGroup    = 'eFootball Region Lock'
$ChunkSize    = 400
$ProtectedAws = @('ap-northeast-1', 'us-west-2', 'eu-west-1')

$GcpRangesUrl = 'https://www.gstatic.com/ipranges/cloud.json'
$AwsRangesUrl = 'https://ip-ranges.amazonaws.com/ip-ranges.json'
$GcpProbesUrl = 'https://gcping.com/api/endpoints'

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

function Measure-Http([System.Net.Http.HttpClient]$Client, [string]$Url, [int]$Samples = 4) {
    # The first request pays for DNS + TLS, so it is discarded.
    $vals = @()
    for ($i = 0; $i -lt $Samples; $i++) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try {
            $task = $Client.GetAsync($Url)
            $ok = $task.Wait(4000)
            $sw.Stop()
            if ($ok) {
                $task.Result.Dispose()
                if ($i -gt 0) { $vals += $sw.Elapsed.TotalMilliseconds }
            }
        } catch { $sw.Stop() }
    }
    if ($vals.Count -gt 0) { [int][math]::Round(($vals | Measure-Object -Minimum).Minimum) } else { $null }
}

function Measure-Tcp([string]$HostName, [int]$Port = 443, [int]$Samples = 3) {
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
    if ($vals.Count -gt 0) { [int][math]::Round(($vals | Measure-Object -Minimum).Minimum) } else { $null }
}

function Get-ToolRules {
    @(Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue)
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

# ---------------------------------------------------------------- main

Show-Banner

if (($Mode -eq 'Apply' -or $Mode -eq 'Remove') -and -not (Test-Admin)) {
    Say 'This mode needs administrator rights. Right-click Run.bat and choose "Run as administrator".' `
        'Este modo necesita permisos de administrador. Haz clic derecho en Run.bat y elige "Ejecutar como administrador".' 'Red'
    exit 1
}

if ($Mode -eq 'Status') { Show-Status; Show-Footer; exit 0 }

if ($Mode -eq 'Remove') {
    $n = Remove-ToolRules
    Say ("Removed {0} rule(s). eFootball can use every server again." -f $n) ("Se quitaron {0} regla(s). eFootball vuelve a poder usar todos los servidores." -f $n) 'Green'
    Show-Footer
    exit 0
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
    if ($Mode -eq 'Apply') { exit 1 }
} else {
    Say 'Game found:' 'Juego encontrado:'
    $exes | ForEach-Object { Write-Host "  $_" -ForegroundColor Green }
    $packages | ForEach-Object { Write-Host ("  Microsoft Store: {0}" -f $_.Name) -ForegroundColor Green }
}

$targets = @()
$targets += @($exes | ForEach-Object { @{ Program = $_ } })
$targets += @($packages | ForEach-Object { @{ Package = $_.Sid } })
Write-Host ''

# --- official IP lists + probe list
Say 'Downloading official IP lists from Google and Amazon...' 'Descargando las listas oficiales de IP de Google y Amazon...'
try {
    $gcp = Invoke-RestMethod -Uri $GcpRangesUrl -TimeoutSec 60
    $aws = Invoke-RestMethod -Uri $AwsRangesUrl -TimeoutSec 60
    $wc = New-Object Net.WebClient
    $wc.Encoding = [Text.Encoding]::UTF8
    $gcpProbes = $wc.DownloadString($GcpProbesUrl) | ConvertFrom-Json
    $wc.Dispose()
} catch {
    Say "Download failed: $($_.Exception.Message)" "Fallo la descarga: $($_.Exception.Message)" 'Red'
    Say 'Nothing was changed.' 'No se cambio nada.' 'Red'
    exit 1
}

# --- regions to measure
$gcpRegions = @($gcp.prefixes | ForEach-Object { $_.scope } | Where-Object { $_ -and $_ -ne 'global' } | Sort-Object -Unique)
$awsRegions = @($aws.prefixes |
    Where-Object { $_.service -eq 'EC2' -and $_.region -eq $_.network_border_group -and $_.region -ne 'GLOBAL' -and $_.region -notlike 'cn-*' -and $_.region -notlike 'us-gov-*' } |
    ForEach-Object { $_.region } | Sort-Object -Unique)

Add-Type -AssemblyName System.Net.Http
$http = New-Object System.Net.Http.HttpClient
$http.Timeout = [TimeSpan]::FromSeconds(5)

$results = New-Object System.Collections.Generic.List[object]
$total = $gcpRegions.Count + $awsRegions.Count
$done = 0
Say ("Measuring latency to {0} regions (about 1-2 minutes)..." -f $total) ("Midiendo la latencia a {0} regiones (1-2 minutos aprox.)..." -f $total)

foreach ($r in $gcpRegions) {
    $done++
    Write-Progress -Activity 'eFootball Region Lock' -Status "Google Cloud: $r" -PercentComplete ([int](100 * $done / $total))
    $probe = $gcpProbes.PSObject.Properties[$r]
    $ping = $null; $loc = ''
    if ($probe) {
        $loc = $probe.Value.RegionName
        $ping = Measure-Http $http ($probe.Value.URL + '/api/ping')
    }
    $results.Add([pscustomobject]@{ Provider = 'Google'; Region = $r; Location = $loc; Ping = $ping })
}
foreach ($r in $awsRegions) {
    $done++
    Write-Progress -Activity 'eFootball Region Lock' -Status "Amazon: $r" -PercentComplete ([int](100 * $done / $total))
    $loc = ''
    if ($AwsNames.ContainsKey($r)) { $loc = $AwsNames[$r] }
    $ping = Measure-Tcp "ec2.$r.amazonaws.com"
    $results.Add([pscustomobject]@{ Provider = 'Amazon'; Region = $r; Location = $loc; Ping = $ping })
}
Write-Progress -Activity 'eFootball Region Lock' -Completed
$http.Dispose()

# --- decide
$allowedKeys = New-Object 'System.Collections.Generic.HashSet[string]'
$count = 0
foreach ($row in ($results | Where-Object { $null -ne $_.Ping } | Sort-Object Ping)) {
    $underLimit = ($MaxServers -le 0) -or ($count -lt $MaxServers)
    if (($count -lt $MinServers) -or (($row.Ping -le $MaxPing) -and $underLimit)) {
        [void]$allowedKeys.Add("$($row.Provider)/$($row.Region)")
        $count++
    }
}

foreach ($row in $results) {
    $key = "$($row.Provider)/$($row.Region)"
    if ($allowedKeys.Contains($key)) {
        $decision = T 'ALLOWED (close)' 'PERMITIDO (cerca)'
    } elseif ($AlwaysAllow -contains $row.Region) {
        $decision = T 'ALLOWED (your list)' 'PERMITIDO (tu lista)'
    } elseif ($row.Provider -eq 'Amazon' -and $ProtectedAws -contains $row.Region) {
        $decision = T 'ALLOWED (game services)' 'PERMITIDO (servicios del juego)'
    } elseif ($null -eq $row.Ping) {
        $decision = T 'ALLOWED (no data)' 'PERMITIDO (sin datos)'
    } else {
        $decision = T 'BLOCKED' 'BLOQUEADO'
    }
    $row | Add-Member -NotePropertyName Decision -NotePropertyValue $decision
    $row | Add-Member -NotePropertyName Blocked -NotePropertyValue ($decision -eq (T 'BLOCKED' 'BLOQUEADO'))
}

Write-Host ''
$results | Sort-Object @{ Expression = { if ($null -eq $_.Ping) { 99999 } else { $_.Ping } } } |
    Format-Table @{ Label = (T 'Cloud' 'Nube'); Expression = { $_.Provider } },
                 @{ Label = (T 'Region' 'Region'); Expression = { $_.Region } },
                 @{ Label = (T 'Location' 'Ubicacion'); Expression = { $_.Location } },
                 @{ Label = 'Ping (ms)'; Expression = { if ($null -eq $_.Ping) { '-' } else { $_.Ping } }; Align = 'Right' },
                 @{ Label = (T 'Decision' 'Decision'); Expression = { $_.Decision } } -AutoSize | Out-Host

$close = @($results | Where-Object { $allowedKeys.Contains("$($_.Provider)/$($_.Region)") } | Sort-Object Ping)
Say 'Match servers you will keep:' 'Servidores de partido que se mantienen:' 'Green'
$close | ForEach-Object { Write-Host ("  {0,-7} {1,-24} {2,-16} {3} ms" -f $_.Provider, $_.Region, $_.Location, $_.Ping) -ForegroundColor Green }

# --- build the block list
$blockedGcp = @($results | Where-Object { $_.Blocked -and $_.Provider -eq 'Google' } | ForEach-Object { $_.Region })
$blockedAws = @($results | Where-Object { $_.Blocked -and $_.Provider -eq 'Amazon' } | ForEach-Object { $_.Region })

$ranges = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($p in $gcp.prefixes) {
    if ($blockedGcp -contains $p.scope) {
        if ($p.PSObject.Properties['ipv4Prefix']) { [void]$ranges.Add($p.ipv4Prefix) }
        if ($p.PSObject.Properties['ipv6Prefix']) { [void]$ranges.Add($p.ipv6Prefix) }
    }
}
foreach ($p in $aws.prefixes) {
    if ($p.service -eq 'EC2' -and $p.region -eq $p.network_border_group -and $blockedAws -contains $p.region) { [void]$ranges.Add($p.ip_prefix) }
}
foreach ($p in $aws.ipv6_prefixes) {
    if ($p.service -eq 'EC2' -and $p.region -eq $p.network_border_group -and $blockedAws -contains $p.region) { [void]$ranges.Add($p.ipv6_prefix) }
}
$rangeList = @($ranges | Sort-Object)

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

# --- apply
$old = Remove-ToolRules
if ($old -gt 0) { Say ("Replaced {0} previous rule(s)." -f $old) ("Se reemplazaron {0} regla(s) anteriores." -f $old) }

$keepText = ($close | ForEach-Object { "$($_.Provider) $($_.Region) ($($_.Location), $($_.Ping) ms)" }) -join '; '
$description = "Created by eFootball Region Lock v$ToolVersion on $(Get-Date -Format 'yyyy-MM-dd HH:mm'). " +
               "MaxPing=$MaxPing MaxServers=$MaxServers MinServers=$MinServers. Kept: $keepText"

$created = 0
foreach ($target in $targets) {
    $part = 0
    for ($i = 0; $i -lt $rangeList.Count; $i += $ChunkSize) {
        $part++
        $chunk = $rangeList[$i..([Math]::Min($i + $ChunkSize - 1, $rangeList.Count - 1))]
        New-NetFirewallRule -DisplayName "$RuleGroup #$part" -Group $RuleGroup -Description $description `
            -Direction Outbound -Action Block -Protocol UDP -RemoteAddress $chunk @target | Out-Null
        $created++
    }
}

Write-Host ''
Say ("Done: {0} rule(s) created, only for eFootball and only for UDP." -f $created) `
    ("Listo: {0} regla(s) creadas, solo para eFootball y solo para UDP." -f $created) 'Green'
Say 'To undo everything, run Run.bat and choose "Remove".' 'Para deshacerlo todo, abre Run.bat y elige "Quitar".' 'Green'
Say 'Re-run it every few weeks: Google and Amazon add new IP ranges.' 'Vuelve a ejecutarlo cada pocas semanas: Google y Amazon agregan rangos nuevos.' 'Gray'
Show-Footer
