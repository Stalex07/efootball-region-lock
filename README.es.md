<p align="center"><img src="assets/banner.jpg" alt="eFootball Region Lock - Play on servers close to you" width="100%"></p>

<h1 align="center">eFootball Region Lock</h1>

<p align="center">
  <b>Bloquea los servidores de partido de eFootball que están lejos de ti, para que tus partidos online se jueguen en los servidores más cercanos.</b><br>
  Funciona en cualquier país: mide tu propio ping y decide por ti.
</p>

<p align="center">
  <img alt="Windows 10/11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows&logoColor=white">
  <img alt="PowerShell 5.1+" src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white">
  <img alt="Steam y app de Xbox" src="https://img.shields.io/badge/Steam%20%7C%20app%20de%20Xbox-compatible-2ea44f">
  <img alt="Licencia MIT" src="https://img.shields.io/badge/licencia-MIT-blue">
</p>

<p align="center">
  <a href="README.md">English</a> · <b>Español</b>
</p>

<p align="center">
  Powered by <a href="https://www.instagram.com/mrstalex/"><b>@mrstalex</b></a>
</p>

> [!NOTE]
> Herramienta de la comunidad, no oficial. Sin relación con Konami. Úsala bajo tu propia responsabilidad.

## Contenido

- [Por qué existe este proyecto](#por-qué-existe-este-proyecto)
- [El problema](#el-problema)
- [Cómo funciona](#cómo-funciona)
- [Tutorial paso a paso](#tutorial-paso-a-paso)
- [Qué esperar](#qué-esperar)
- [Qué nunca se bloquea](#qué-nunca-se-bloquea)
- [Línea de comandos](#línea-de-comandos)
- [Ten en cuenta](#ten-en-cuenta)
- [Desinstalar](#desinstalar)
- [Preguntas frecuentes](#preguntas-frecuentes)

## Por qué existe este proyecto

Juego eFootball desde **Lima, Perú**. Sudamérica tiene pocas regiones de servidores, y los partidos a menudo terminaban jugándose lejos de casa.

Para entender qué pasaba, usé el Monitor de recursos de Windows y revisé a qué servidor se conectaba el juego en cada partido. Los resultados lo dejaron claro:

- Tres partidos se jugaron en **Santiago de Chile** (~55 ms). Dos fueron bien. Uno fue muy malo, y como el servidor era el mismo, el problema era la conexión del rival.
- Un partido se jugó en **Estados Unidos**, a **139 ms**. Con solo 2 barras de conexión, el partido era prácticamente injugable, mientras mi rival seguramente jugaba con una fracción de ese retraso.

Descubrí que los servidores de partido de eFootball funcionan en **Google Cloud y Amazon Web Services**, y que ambas empresas publican los rangos de IP oficiales de cada región. Primero bloqueé a mano los servidores lejanos en el Firewall de Windows y comprobé que el juego seguía funcionando con normalidad. Después lo convertí en esta herramienta, para que cualquier jugador, en cualquier país, pueda hacer lo mismo en un clic: mide **su propio** ping y decide qué servidores son cercanos para él.

— [@mrstalex](https://www.instagram.com/mrstalex/)

## El problema

eFootball elige un servidor de partido para ti y tu rival. A veces ese servidor está en otro continente. Tú juegas con 150 ms de retraso y tu rival con 10 ms, y el partido se siente pesado y lento.

Los servidores de partido de eFootball funcionan en **Google Cloud** y **Amazon Web Services**. Ambas empresas publican los rangos de IP oficiales de cada región, así que las regiones lejanas se pueden bloquear con precisión, sin adivinar.

## Cómo funciona

```text
1. Busca el juego          detecta Steam y la app de Xbox (Microsoft Store) automáticamente
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

## Tutorial paso a paso

No necesitas saber programar. Tarda unos 3 minutos.

> [!WARNING]
> No apliques ni quites las reglas durante un partido. Cierra el juego o quédate en los menús.

### 1. Descargar

En esta página, haz clic en el botón verde **Code** → **Download ZIP**. Descomprime el ZIP en cualquier carpeta (por ejemplo, el Escritorio).

### 2. Abrir el menú

Haz doble clic en **`Run.bat`**. Windows te pide permiso de administrador: pulsa **Sí**. Verás este menú:

```text
         _...----..._
       .'  \  __  /  '.      )  )  )
      /  ---\/  \/---  \
     |      |    |      |    eFootball Region Lock
      \  ---/\__/\---  /     Play on servers close to you
       '._ /      \ _.'
          '--....--'         Powered by @mrstalex
  ---------------------------------------------------------------

  1. Simulate (measure only, change nothing)  / Simular
  2. Apply (max 100 ms, 4 servers)            / Aplicar
  3. Apply with custom settings               / Aplicar personalizado
  4. Status                                   / Estado
  5. Remove all rules                         / Quitar todo
  6. Exit                                     / Salir
```

> Si Windows muestra "Windows protegió su PC", haz clic en **Más información** → **Ejecutar de todas formas**. Aparece porque el archivo se descargó de internet.

### 3. Primero simula (opción 1)

Pulsa **1**. La herramienta encuentra tu juego, mide tu ping a unas 85 regiones de servidores (1-2 minutos) y muestra una tabla con lo que se **mantiene** y lo que se **bloquearía**. **Todavía no cambia nada.**

Ejemplo para un jugador en Lima, Perú:

```text
Servidores de partido que se mantienen:
  Amazon  sa-west-1                                 38 ms
  Google  southamerica-west1       Santiago         40 ms
  Amazon  sa-east-1                Sao Paulo        81 ms
  Google  southamerica-east1       Sao Paulo        85 ms

Regiones a bloquear: 72  |  Rangos de IP: 3966
```

### 4. Aplicar (opción 2 o 3)

- **2** mantiene las regiones con menos de **100 ms**, máximo **4**.
- **3** te deja elegir, por ejemplo **80** ms y **3** servidores.

La herramienta vuelve a medir, muestra la tabla y pide confirmación. Escribe **S** y pulsa Enter. Cuando diga **Listo**, los servidores lejanos quedan bloqueados.

### 5. Jugar y comprobar

Juega unos partidos. La opción **4. Estado** te muestra las reglas activas en cualquier momento.

Si te salen errores de conexión o tarda mucho más de lo normal en emparejar, abre el menú y elige **5. Quitar todo**. Todo vuelve a la normalidad al instante.

## Qué esperar

> [!IMPORTANT]
> **Juega con conexión por cable (Ethernet).** Es la mejora más grande que puedes hacer: el Wi-Fi añade picos de retraso y pérdida de paquetes que ninguna herramienta puede arreglar.

**Lo que la herramienta garantiza:** todas las regiones de servidores de Google Cloud y Amazon que superan tu límite de ping quedan bloqueadas para eFootball (salvo las pocas que aparecen en [Qué nunca se bloquea](#qué-nunca-se-bloquea)). Tus partidos ya no se pueden jugar en un servidor de otro continente, aunque tu rival esté lejos.

**Lo que no puede controlar:** quién es tu rival y qué tan buena es su conexión.

**Por eso, si un partido sigue con lag o se desconecta** estando tú por cable, sin nadie en casa descargando o viendo streaming, y en un servidor cercano, **lo más probable es que la causa sea la conexión de tu rival** (Wi-Fi malo, descargas en su red, mala señal).

Revisa tu lado antes de culpar al rival:

- [ ] Conectado por cable Ethernet, no por Wi-Fi
- [ ] Sin descargas, actualizaciones ni streaming de video en tu red mientras juegas
- [ ] Navegador y launchers cerrados o sin actividad

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
