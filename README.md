<!-- Banner: save it as assets/banner.png and uncomment the next line
<p align="center"><img src="assets/banner.png" alt="eFootball Region Lock" width="100%"></p>
-->

<h1 align="center">eFootball Region Lock</h1>

<p align="center">
  <b>Blocks far-away eFootball match servers, so your online matches are played on the servers closest to you.</b><br>
  Works anywhere in the world: it measures your own ping and decides for you.
</p>

<p align="center">
  <img alt="Windows 10/11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows&logoColor=white">
  <img alt="PowerShell 5.1+" src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white">
  <img alt="Steam and Xbox app" src="https://img.shields.io/badge/Steam%20%7C%20Xbox%20app-supported-2ea44f">
  <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

<p align="center">
  <b>English</b> · <a href="README.es.md">Español</a>
</p>

> [!NOTE]
> Unofficial community tool. Not affiliated with, endorsed by or supported by Konami. Use at your own risk.

## Contents

- [The problem](#the-problem)
- [How it works](#how-it-works)
- [Step-by-step tutorial](#step-by-step-tutorial)
- [What to expect](#what-to-expect)
- [What is never blocked](#what-is-never-blocked)
- [Command line](#command-line)
- [Things to know](#things-to-know)
- [Uninstall](#uninstall)
- [FAQ](#faq)

## The problem

eFootball chooses one match server for you and your opponent. Sometimes that server is on another continent. You play with 150 ms of delay while your opponent plays with 10 ms, and the match feels heavy and unresponsive.

eFootball's match servers run on **Google Cloud** and **Amazon Web Services**. Both companies publish the official IP ranges of every region, so the far regions can be blocked precisely, without guessing.

## How it works

```text
1. Find the game         Steam and the Xbox app (Microsoft Store) are detected automatically
2. Download IP lists     official lists from Google and Amazon
3. Measure your ping     to every Google Cloud and AWS region (about 85, 1-2 minutes)
4. Keep the closest      e.g. everything under 100 ms, up to 4 regions
5. Block the rest        Windows Firewall, ONLY for eFootball, ONLY outbound UDP
```

The rules affect **only** eFootball and **only** its match traffic (outbound UDP). Login, menus and the store keep working, and every other program on your PC (browser, Discord, Zoom, Steam...) is untouched.

How latency is measured:

| Cloud | Method |
|---|---|
| Google Cloud | HTTP round trip to the per-region test endpoints of [gcping](https://gcping.com), an open-source Google Cloud project |
| Amazon Web Services | TCP connect time to the official regional endpoint `ec2.<region>.amazonaws.com` |

Official IP lists:
[Google Cloud](https://www.gstatic.com/ipranges/cloud.json) ·
[Amazon Web Services](https://ip-ranges.amazonaws.com/ip-ranges.json)

## Step-by-step tutorial

No programming needed. It takes about 3 minutes.

> [!WARNING]
> Do not apply or remove the rules during a match. Close the game or stay in its menus.

### 1. Download

On this page, click the green **Code** button → **Download ZIP**. Extract the ZIP to any folder (for example your Desktop).

### 2. Open the menu

Double-click **`Run.bat`**. Windows asks for administrator permission: click **Yes**. You will see this menu:

```text
  ==========================================
    eFootball Region Lock
  ==========================================

  1. Simulate (measure only, change nothing)  / Simular
  2. Apply (max 100 ms, 4 servers)            / Aplicar
  3. Apply with custom settings               / Aplicar personalizado
  4. Status                                   / Estado
  5. Remove all rules                         / Quitar todo
  6. Exit                                     / Salir
```

> If Windows shows "Windows protected your PC", click **More info** → **Run anyway**. It appears because the file was downloaded from the internet.

### 3. Simulate first (option 1)

Press **1**. The tool finds your game, measures your ping to about 85 server regions (1-2 minutes) and shows a table with what would be **kept** and what would be **blocked**. **Nothing is changed yet.**

Example for a player in Lima, Peru:

```text
Match servers you will keep:
  Amazon  sa-west-1                                 38 ms
  Google  southamerica-west1       Santiago         40 ms
  Amazon  sa-east-1                Sao Paulo        81 ms
  Google  southamerica-east1       Sao Paulo        85 ms

Regions to block: 72  |  IP ranges: 3966
```

### 4. Apply (option 2 or 3)

- **2** keeps the regions under **100 ms**, at most **4**.
- **3** lets you choose, for example **80** ms and **3** servers.

The tool measures again, shows the table and asks for confirmation. Type **Y** (or **S**) and press Enter. When it says **Done**, the far servers are blocked.

### 5. Play and check

Play a few matches. Option **4. Status** shows the active rules at any time.

If you get connection errors or matchmaking takes much longer than usual, open the menu and choose **5. Remove all rules**. Everything goes back to normal immediately.

## What to expect

> [!IMPORTANT]
> **Play on a wired (Ethernet) connection.** It is the single biggest improvement you can make: Wi-Fi adds delay spikes and packet loss that no tool can fix.

**What the tool guarantees:** every Google Cloud and Amazon server region above your ping limit is blocked for eFootball (except the few listed in [What is never blocked](#what-is-never-blocked)). Your matches can no longer be played on a server on another continent, even when your opponent is far away.

**What it cannot control:** who your opponent is and how good their connection is.

**So if a match still lags or disconnects** while you are on cable, nobody at home is downloading or streaming, and the match is on a nearby server, **the cause is very likely your opponent's connection** (bad Wi-Fi, downloads on their network, weak signal).

Quick check of your side before blaming the opponent:

- [ ] Connected by Ethernet cable, not Wi-Fi
- [ ] No downloads, updates or video streaming on your network while playing
- [ ] Browser and launchers closed or idle

## What is never blocked

| What | Why |
|---|---|
| Amazon `ap-northeast-1` (Tokyo), `us-west-2` (Oregon), `eu-west-1` (Ireland) | eFootball's central services (login, matchmaking) run there |
| Amazon Local Zones and Global Accelerator addresses (`166.117.x.x`) | Anycast/edge addresses: their real location cannot be measured |
| Google `global` services | Not tied to a country |
| Any region the tool could not measure | Safety first |
| At least the 2 closest regions | So you can always find matches, even far from every server |

## Command line

Run these from an **administrator** PowerShell in the tool's folder. `DryRun` and `Status` also work without admin rights.

```powershell
# Simulation: measure and show, change nothing
.\eFootball-RegionLock.ps1 -Mode DryRun

# Apply: regions under 80 ms, at most 3
.\eFootball-RegionLock.ps1 -MaxPing 80 -MaxServers 3

# Never block a specific region
.\eFootball-RegionLock.ps1 -AlwaysAllow southamerica-east1

# Game installed somewhere unusual
.\eFootball-RegionLock.ps1 -GamePath "D:\Games\eFootball\eFootball\Binaries\Win64\eFootball.exe"

# Show or remove the rules
.\eFootball-RegionLock.ps1 -Mode Status
.\eFootball-RegionLock.ps1 -Mode Remove
```

| Parameter | Default | Meaning |
|---|---|---|
| `-Mode` | `Apply` | `Apply`, `DryRun`, `Remove` or `Status` |
| `-MaxPing` | `100` | Highest ping (ms) a region may have to stay allowed |
| `-MaxServers` | `4` | Keep at most this many regions. `0` = no limit |
| `-MinServers` | `2` | Always keep at least this many regions |
| `-AlwaysAllow` | none | Region codes that must never be blocked |
| `-GamePath` | auto | Path(s) to `eFootball.exe` |
| `-Lang` | `auto` | Output language: `auto`, `en` or `es` |
| `-Yes` | off | Skip the confirmation prompt |

## Things to know

- **It cannot fix your opponent's connection.** If they play on bad Wi-Fi, the match can still feel bad.
- **Matchmaking may take a little longer**, because opponents who would need a far server are filtered out. When the game cannot connect, it normally shows a connection error before kick-off and searches again.
- **Google values read a bit high.** They are an HTTP round trip and usually show 5-15 ms more than a plain ping. Leave some margin in `-MaxPing`.
- **Re-run it every few weeks.** Google and Amazon add new IP ranges over time. Applying again replaces the previous rules.
- **Microsoft Store / Xbox app version is experimental.** The tool looks for the game in the `XboxGames` folders and also adds a rule bound to the Store package. Feedback is welcome.
- Konami does not document how server selection works, and its terms neither allow nor forbid firewall rules on your own PC.

## Uninstall

Open `Run.bat` → **5. Remove all rules**, or run as administrator:

```powershell
Remove-NetFirewallRule -Group "eFootball Region Lock"
```

Every rule belongs to the firewall group `eFootball Region Lock`, so nothing else is touched.

## FAQ

**Will this get me banned?**
It does not touch the game files, memory or traffic contents. It only adds standard Windows Firewall rules. We are not aware of anyone being sanctioned for this, but Konami's terms do not mention it explicitly.

**I still got a far opponent.**
The tool cannot choose your opponent, only which servers the match can use. The game may still pair you with someone far away and use a server in between.

**Does it work with a VPN?**
The ping is measured from wherever your traffic exits. Run it with the same VPN setup you play with.

## License

[MIT](LICENSE)
