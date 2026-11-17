# eFootball Region Lock

Keep your eFootball online matches on servers that are **close to you**, wherever you live.

The tool measures your latency to every Google Cloud and Amazon Web Services region, keeps the closest ones (for example, everything under 100 ms, up to 4 regions) and blocks the rest in Windows Firewall, **only for eFootball**.

> **[Leer en español](#español)**

> Unofficial community tool. Not affiliated with, endorsed by or supported by Konami. Use at your own risk.

## Why

eFootball picks a match server for you and your opponent. Sometimes it picks one far away from you, and your opponent gets a big latency advantage. eFootball's match servers run on Google Cloud and Amazon Web Services. Both companies publish the official IP ranges of every region, so the far regions can be blocked precisely.

## What it does

1. Finds `eFootball.exe` (Steam and Epic are detected automatically).
2. Downloads the official IP lists:
   - Google: <https://www.gstatic.com/ipranges/cloud.json>
   - Amazon: <https://ip-ranges.amazonaws.com/ip-ranges.json>
3. Measures your latency to each region:
   - Google: HTTP round trip to the per-region test endpoints of [gcping](https://gcping.com) (a Google Cloud open-source project).
   - Amazon: TCP connect time to the official regional endpoint `ec2.<region>.amazonaws.com`.
4. Keeps the closest regions and creates Windows Firewall rules that block the others.

The rules apply **only** to `eFootball.exe` and **only** to outbound **UDP** (match traffic). Login, menus, the store, and every other program on your PC (browser, Discord, Zoom, Steam...) are not affected.

### Never blocked

| What | Why |
|---|---|
| Amazon `ap-northeast-1` (Tokyo), `us-west-2` (Oregon), `eu-west-1` (Ireland) | eFootball's central services (login, matchmaking) run there |
| Amazon Local Zones and Global Accelerator (`166.117.x.x`) | Anycast/edge addresses that cannot be located by ping |
| Google `global` services | Not tied to a country |
| Any region the tool could not measure | Safety first |

## How to use

1. Download this repository (green **Code** button → **Download ZIP**) and extract it.
2. Double-click **`Run.bat`** and accept the administrator prompt.
3. Choose **1. Simulate** first: it shows your latency to every region and what would be blocked, without changing anything.
4. If the result looks right, choose **2. Apply**, or **3** to set your own limits (for example 80 ms and 3 servers).
5. Play a few matches. If you get connection errors or very long matchmaking, choose **5. Remove**.

**Do not apply or remove the rules during a match.** Stay in the menus.

### Command line

```powershell
# Simulation (no admin needed)
.\eFootball-RegionLock.ps1 -Mode DryRun

# Apply: regions under 80 ms, at most 3
.\eFootball-RegionLock.ps1 -MaxPing 80 -MaxServers 3

# Keep a region even if it is slower
.\eFootball-RegionLock.ps1 -AlwaysAllow southamerica-east1

# Custom game path
.\eFootball-RegionLock.ps1 -GamePath "D:\Games\eFootball\eFootball\Binaries\Win64\eFootball.exe"

# Show / remove the rules
.\eFootball-RegionLock.ps1 -Mode Status
.\eFootball-RegionLock.ps1 -Mode Remove
```

| Parameter | Default | Meaning |
|---|---|---|
| `-Mode` | `Apply` | `Apply`, `DryRun`, `Remove` or `Status` |
| `-MaxPing` | `100` | Highest latency (ms) a region may have to stay allowed |
| `-MaxServers` | `4` | Keep at most this many regions. `0` = no limit |
| `-MinServers` | `2` | Always keep at least this many regions, so you can still find matches |
| `-AlwaysAllow` | none | Region codes that must never be blocked |
| `-GamePath` | auto | Path(s) to `eFootball.exe` |
| `-Lang` | `auto` | Output language: `auto`, `en` or `es` |
| `-Yes` | off | Skip the confirmation prompt |

## Things to know

- **It cannot fix your opponent's connection.** If they play on bad Wi-Fi, the match can still feel bad.
- **Matchmaking may take longer**, because opponents who would need a far server are filtered out. If the game cannot connect, you usually get a connection error before kick-off and it searches again.
- **Latency is measured, not guessed.** Google values are an HTTP round trip and usually read 5–15 ms higher than a plain ping, so leave some margin in `-MaxPing`.
- **Re-run it every few weeks.** Google and Amazon add new IP ranges over time. Running Apply again replaces the old rules.
- The Microsoft Store version of the game is not supported (Windows protects its files).
- Konami does not document how server selection works, and its terms neither allow nor forbid firewall rules on your own PC.

## Uninstall

Run `Run.bat` → **5. Remove**, or:

```powershell
Remove-NetFirewallRule -Group "eFootball Region Lock"
```

All rules belong to the firewall group `eFootball Region Lock`, so nothing else is touched.

---

## Español

Mantén tus partidos online de eFootball en servidores **cercanos a ti**, vivas donde vivas.

La herramienta mide tu latencia a cada región de Google Cloud y Amazon Web Services, se queda con las más cercanas (por ejemplo, todo lo que esté por debajo de 100 ms, hasta 4 regiones) y bloquea el resto en el Firewall de Windows, **solo para eFootball**.

> Herramienta de la comunidad, no oficial. Sin relación con Konami. Úsala bajo tu propia responsabilidad.

### Qué hace

1. Encuentra `eFootball.exe` (detecta Steam y Epic automáticamente).
2. Descarga las listas oficiales de IP de Google y Amazon.
3. Mide tu latencia a cada región.
4. Mantiene las regiones más cercanas y bloquea las demás.

Las reglas afectan **solo** a `eFootball.exe` y **solo** al tráfico **UDP** de salida (los partidos). El login, los menús, la tienda y el resto de programas de tu PC (navegador, Discord, Zoom, Steam...) siguen funcionando normal.

**Nunca se bloquea:** Amazon Tokio, Oregón e Irlanda (servicios centrales del juego), las direcciones `166.117.x.x` de Amazon (anycast, no se pueden ubicar), los servicios "global" de Google y cualquier región que no se haya podido medir.

### Cómo usarlo

1. Descarga el repositorio (botón verde **Code** → **Download ZIP**) y descomprímelo.
2. Haz doble clic en **`Run.bat`** y acepta el aviso de administrador.
3. Elige primero **1. Simular**: te muestra tu ping a cada región y qué se bloquearía, sin cambiar nada.
4. Si te parece bien, elige **2. Aplicar**, o **3** para poner tus propios límites (por ejemplo 80 ms y 3 servidores).
5. Juega unos partidos. Si te salen errores de conexión o tarda muchísimo en emparejar, elige **5. Quitar todo**.

**No apliques ni quites las reglas durante un partido.** Hazlo en los menús.

### Ten en cuenta

- **No arregla la conexión de tu rival.** Si juega con mal Wi-Fi, el partido puede ir mal igual.
- **Puede tardar más en encontrar partido**, porque se descartan rivales que necesitarían un servidor lejano.
- Los valores de Google son un tiempo HTTP y suelen salir 5–15 ms más altos que un ping normal. Deja algo de margen en el ping máximo.
- **Vuelve a ejecutarlo cada pocas semanas**: Google y Amazon agregan rangos nuevos. Aplicar de nuevo reemplaza las reglas anteriores.
- La versión de Microsoft Store no es compatible.

### Desinstalar

`Run.bat` → **5. Quitar todo**, o en PowerShell como administrador:

```powershell
Remove-NetFirewallRule -Group "eFootball Region Lock"
```

## License

[MIT](LICENSE)
