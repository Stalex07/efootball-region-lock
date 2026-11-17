<!-- Banner: guárdalo como assets/banner.png y descomenta la siguiente línea
<p align="center"><img src="assets/banner.png" alt="eFootball Region Lock" width="100%"></p>
-->

<h1 align="center">eFootball Region Lock</h1>

<p align="center">
  <b>Juega tus partidos online de eFootball en servidores cercanos a ti, vivas donde vivas.</b>
</p>

<p align="center">
  <img alt="Windows 10/11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows&logoColor=white">
  <img alt="PowerShell 5.1+" src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white">
  <img alt="Steam, Epic, Microsoft Store" src="https://img.shields.io/badge/Steam%20%7C%20Epic%20%7C%20MS%20Store-compatible-2ea44f">
  <img alt="Licencia MIT" src="https://img.shields.io/badge/licencia-MIT-blue">
</p>

<p align="center">
  <a href="README.md">English</a> · <b>Español</b>
</p>

> [!NOTE]
> Herramienta de la comunidad, no oficial. Sin relación con Konami. Úsala bajo tu propia responsabilidad.

## Contenido

- [El problema](#el-problema)
- [Cómo funciona](#cómo-funciona)
- [Uso rápido](#uso-rápido)
- [Qué nunca se bloquea](#qué-nunca-se-bloquea)
- [Línea de comandos](#línea-de-comandos)
- [Ten en cuenta](#ten-en-cuenta)
- [Desinstalar](#desinstalar)
- [Preguntas frecuentes](#preguntas-frecuentes)

## El problema

eFootball elige un servidor de partido para ti y tu rival. A veces ese servidor está en otro continente. Tú juegas con 150 ms de retraso y tu rival con 10 ms, y el partido se siente pesado y lento.

Los servidores de partido de eFootball funcionan en **Google Cloud** y **Amazon Web Services**. Ambas empresas publican los rangos de IP oficiales de cada región, así que las regiones lejanas se pueden bloquear con precisión, sin adivinar.

## Cómo funciona

```text
1. Busca el juego          detecta Steam, Epic y Microsoft Store automáticamente
2. Descarga las listas     listas oficiales de IP de Google y Amazon
3. Mide tu ping            a cada región de Google Cloud y AWS (unas 85, 1-2 minutos)
4. Mantiene las cercanas   p. ej. todo lo que esté por debajo de 100 ms, hasta 4 regiones
5. Bloquea el resto        Firewall de Windows, SOLO para eFootball, SOLO UDP de salida
```

Las reglas afectan **solo** a eFootball y **solo** a su tráfico de partido (UDP de salida). El login, los menús y la tienda siguen funcionando, y el resto de programas de tu PC (navegador, Discord, Zoom, Steam...) no se tocan.

Cómo se mide la latencia:

| Nube | Método |
|---|---|
| Google Cloud | Tiempo de respuesta HTTP a los puntos de prueba de cada región de [gcping](https://gcping.com), un proyecto de código abierto de Google Cloud |
| Amazon Web Services | Tiempo de conexión TCP al servidor oficial de cada región, `ec2.<región>.amazonaws.com` |

Listas oficiales de IP:
[Google Cloud](https://www.gstatic.com/ipranges/cloud.json) ·
[Amazon Web Services](https://ip-ranges.amazonaws.com/ip-ranges.json)

## Uso rápido

1. Descarga la última versión: botón verde **Code** → **Download ZIP**, y descomprímelo.
2. Haz doble clic en **`Run.bat`** y acepta el aviso de administrador.
3. Elige **1. Simular**. Te muestra tu ping a cada región y qué se bloquearía, **sin cambiar nada**.
4. Si te parece bien, elige **2. Aplicar**, o **3** para poner tus propios límites (por ejemplo 80 ms y 3 servidores).
5. Juega unos partidos. Si te salen errores de conexión o tarda muchísimo en emparejar, elige **5. Quitar todo**.

> [!WARNING]
> No apliques ni quites las reglas durante un partido. Hazlo desde los menús del juego.

Ejemplo de resultado para un jugador en Lima, Perú:

```text
Servidores de partido que se mantienen:
  Amazon  sa-west-1                                 38 ms
  Google  southamerica-west1       Santiago         40 ms
  Amazon  sa-east-1                Sao Paulo        81 ms
  Google  southamerica-east1       Sao Paulo        85 ms

Regiones a bloquear: 72  |  Rangos de IP: 3966
```

## Qué nunca se bloquea

| Qué | Por qué |
|---|---|
| Amazon `ap-northeast-1` (Tokio), `us-west-2` (Oregón), `eu-west-1` (Irlanda) | Ahí están los servicios centrales de eFootball (login, emparejamiento) |
| Amazon Local Zones y direcciones Global Accelerator (`166.117.x.x`) | Son direcciones anycast/edge: no se puede medir dónde están de verdad |
| Servicios "global" de Google | No están en un país concreto |
| Cualquier región que no se haya podido medir | Por seguridad |
| Al menos las 2 regiones más cercanas | Para que siempre puedas encontrar partido, aunque vivas lejos de todos los servidores |

## Línea de comandos

Ejecútalos en PowerShell **como administrador**, dentro de la carpeta de la herramienta. `DryRun` y `Status` también funcionan sin permisos de administrador.

```powershell
# Simulación: mide y muestra, no cambia nada
.\eFootball-RegionLock.ps1 -Mode DryRun

# Aplicar: regiones con menos de 80 ms, máximo 3
.\eFootball-RegionLock.ps1 -MaxPing 80 -MaxServers 3

# No bloquear nunca una región concreta
.\eFootball-RegionLock.ps1 -AlwaysAllow southamerica-east1

# Juego instalado en otra ruta
.\eFootball-RegionLock.ps1 -GamePath "D:\Juegos\eFootball\eFootball\Binaries\Win64\eFootball.exe"

# Ver o quitar las reglas
.\eFootball-RegionLock.ps1 -Mode Status
.\eFootball-RegionLock.ps1 -Mode Remove
```

| Parámetro | Por defecto | Qué hace |
|---|---|---|
| `-Mode` | `Apply` | `Apply`, `DryRun`, `Remove` o `Status` |
| `-MaxPing` | `100` | Ping máximo (ms) que puede tener una región para seguir permitida |
| `-MaxServers` | `4` | Mantener como máximo estas regiones. `0` = sin límite |
| `-MinServers` | `2` | Mantener siempre al menos estas regiones |
| `-AlwaysAllow` | ninguna | Códigos de región que nunca se bloquean |
| `-GamePath` | automático | Ruta(s) a `eFootball.exe` |
| `-Lang` | `auto` | Idioma: `auto`, `en` o `es` |
| `-Yes` | no | No pedir confirmación |

## Ten en cuenta

- **No arregla la conexión de tu rival.** Si juega con mal Wi-Fi, el partido puede ir mal igual.
- **Puede tardar un poco más en encontrar partido**, porque se descartan rivales que necesitarían un servidor lejano. Si el juego no logra conectar, normalmente muestra un error antes de empezar y vuelve a buscar.
- **Los valores de Google salen algo más altos.** Son un tiempo HTTP y suelen marcar 5-15 ms más que un ping normal. Deja algo de margen en `-MaxPing`.
- **Vuelve a ejecutarlo cada pocas semanas.** Google y Amazon agregan rangos de IP nuevos. Aplicar otra vez reemplaza las reglas anteriores.
- **La versión de Microsoft Store / app de Xbox es experimental.** La herramienta busca el juego en las carpetas `XboxGames` y además crea una regla ligada al paquete de la Store. Se agradecen los comentarios.
- Konami no explica cómo elige los servidores, y sus términos ni permiten ni prohíben reglas de firewall en tu propio PC.

## Desinstalar

Abre `Run.bat` → **5. Quitar todo**, o ejecuta como administrador:

```powershell
Remove-NetFirewallRule -Group "eFootball Region Lock"
```

Todas las reglas están en el grupo de firewall `eFootball Region Lock`, así que no se toca nada más.

## Preguntas frecuentes

**¿Me pueden banear por esto?**
No toca los archivos del juego, ni su memoria, ni el contenido de su tráfico. Solo añade reglas normales del Firewall de Windows. No conocemos ningún caso de sanción por esto, pero los términos de Konami no lo mencionan de forma explícita.

**Igual me tocó un rival lejano.**
La herramienta no puede elegir a tu rival, solo qué servidores puede usar el partido. El juego puede emparejarte con alguien lejos y usar un servidor intermedio.

**¿Funciona con VPN?**
El ping se mide desde donde sale tu tráfico. Ejecútalo con la misma configuración de VPN con la que juegas.

## Licencia

[MIT](LICENSE)
