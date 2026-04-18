# Swimfo

Garmin Connect IQ widget for open water swimming conditions in Zeeland. Shows real-time tide, wind, and temperature data on your watch.

**→ [Install from the Garmin Connect IQ Store](https://apps.garmin.com/apps/67cd6568-03f6-4d2a-a55c-1fa3c381a655)**

## Features

- **Glance view** -- compact summary in the widget carousel: tide direction, water level, water temp, air temp, wind
- **Tide page** -- rising (Opkomend) or falling (Afgaand) with cosine-interpolated water level in meters (NAP), next high water (HW) or low water (LW) with level and time, springtij/doodtij indicator and moon phase
- **Tide table** -- tap the tide page to see a scrollable table of all upcoming HW/LW times grouped by date
- **Water page** -- current sea surface temperature in °C
- **Weather page** -- air temperature and wind speed with Beaufort scale
- **Sync page** -- last data sync time, tap to trigger manual refresh
- **Location selection** -- configurable from the watch or Garmin Connect app

### Widget pages

```
┌─ Glance ─────────────┐
│ OPK 1.83m w11°       │
│ 15° 15km/h           │
└──────────────────────┘

Page 1: Tide       Page 2: Water
  VLISSINGEN         VLISSINGEN
    ▲ 1.83m            10.8°C
      OPK              Water
  HW 3.21m 14:32       ~~~~~
    ● ○ ○ ○            ○ ● ○ ○

Page 3: Weather    Page 4: Sync
  VLISSINGEN         VLISSINGEN
    15.2°C               ↻
      Air              22:57
    15 km/h          10 Apr 2026
      Wind           Laatste sync
    ○ ○ ● ○            ○ ○ ○ ●
```

### Screenshots

Simulator captures:

- [Tide](screens/page-1.png) — direction, interpolated level, next HW/LW, springtij/doodtij
- [Tide table](screens/page-1-table.png) — scrollable 7-day HW/LW grouped by date
- [Water](screens/page-2.png) — current sea surface temperature
- [Weather](screens/page-3.png) — air temperature, wind speed, Beaufort
- [Sync](screens/page-4.png) — last sync time, manual refresh
- [Store cover](screens/cover.jpg) — listing artwork

## Supported locations

| Display name  | RWS station            | Body of water              | Notes                        |
|---------------|------------------------|----------------------------|------------------------------|
| Vlissingen    | vlissingen             | Westerschelde              |                              |
| Oesterdam     | marollegat             | Oosterschelde              | temp sensor at Marollegat    |
| Ossenisse     | ossenisse              | Westerschelde              |                              |
| Terneuzen     | terneuzen              | Westerschelde              | no water temp sensor (`--°C`)|
| Oranjeplaat   | arnemuiden.oranjeplaat | Veerse Meer (non-tidal)    | no tide (shows N/A)          |

The Oosterschelde temperature sensor at Yerseke (the obvious-sounding choice) has been offline since 1981 — RWS still happily returns 1.0 °C from a mercury thermometer from that year. Marollegat is the nearest site with a live NKE CT sensor reporting every ~10 minutes; the watch labels that location "Oesterdam" since that's the nearest landmark most swimmers know.

The Veerse Meer has been a closed, non-tidal lake since the Veerse Gatdam was built in 1961 (water level is now managed via the Katse Heule). RWS publishes no astronomical tide predictions for Oranjeplaat, so the tide pages show "N/A" — water temp and weather work as usual.

Terneuzen has live tide predictions but no water-temperature sensor (the ones that exist are for lock-chamber water, not the estuary), so the water page shows `--°C`.

## Supported devices

Swimfo targets every Connect IQ device that supports widgets with background HTTP — roughly any Garmin watch from ~2018 onward. Tested on fenix 7, built for the full current line-up including Forerunner (165, 255, 265, 570, 955, 965, 970), fenix (5 Plus → 8), epix 2 series, Venu 2 / 3 / X1, vivoactive 4 / 5 / 6, Instinct 2 / 3, Enduro 2 / 3, Descent Mk2 / Mk3, MARQ Gen 1 / Gen 2, and Approach S60 / S62 / S70.

See `manifest.xml` for the exact product list.

## Installation

After installing the app on your watch, add the glance to your widget carousel (long-press on the watch face → Glances → Add). This enables automatic background data updates every 30 minutes. Without the glance in the carousel, data only refreshes while the widget is actively open.

## Architecture

The watch app fetches all data from a local proxy server that aggregates upstream APIs:

```
┌─────────────────────────────────────────────────┐
│  Garmin Watch                                   │
│                                                 │
│  SwimfoGlanceView  SwimfoWidgetView (4 pages)  │
│         ▲                  ▲                    │
│         └──── Application.Storage ◄─────┐      │
│                                         │      │
│  Background process (every 30 min)      │      │
│  ┌──────────────────────────────────────┘      │
│  │ SwimfoService                               │
│  │ GET /conditions/{locationCode}              │
│  └───────────────┬─────────────────────────────┘
│                  │ via phone Bluetooth
├──────────────────┼─────────────────────────────┤
│  Phone           ▼                             │
│              Internet                           │
│                  │                              │
│  ┌───────────────▼──────────────────┐          │
│  │ Swimfo Server (Node.js)          │          │
│  │ Aggregates + caches (1h TTL):    │          │
│  │  • Open-Meteo → wind, air temp   │          │
│  │  • RWS tide predictions          │          │
│  │  • RWS water temperature         │          │
│  │ Returns flat JSON (~300 bytes)    │          │
│  └──────────────────────────────────┘          │
└─────────────────────────────────────────────────┘
```

## Data sources

Swimfo uses two free public APIs -- no API keys required:

| Data                  | Source                        |
|----------------------|-------------------------------|
| Wind speed, air temp | [Open-Meteo](https://open-meteo.com/) |
| Water level (tide)   | [Rijkswaterstaat DDL](https://rijkswaterstaat.github.io/wm-ws-dl/) |
| Water temperature    | [Rijkswaterstaat DDL](https://rijkswaterstaat.github.io/wm-ws-dl/) |
| Moon phase / spring tide | Calculated from lunar synodic cycle (no API) |

More information about Dutch tides: [Rijkswaterstaat - Getij](https://www.rijkswaterstaat.nl/water/waterdata/getij#ritme-van-eb-en-vloed)

### Water level between measurements

RWS delivers predicted extrema (HW/LW) plus coarse samples in between. The server packs a multi-day HW/LW forecast into the sync payload; on each redraw the watch picks the extrema bracketing the current clock time from that forecast and interpolates between them using a raised-cosine curve:

```
t         = (now - prevEpoch) / (nextEpoch - prevEpoch)    // 0..1
cosInterp = (1 - cos(t · π)) / 2                           // eased 0..1
level     = prevLevel + (nextLevel - prevLevel) · cosInterp
```

The curve is flat near HW and LW and steepest midway — a good match for the near-sinusoidal shape of a tidal cycle, and closer to reality than linear interpolation (which would overstate change near the turn and understate it mid-cycle). Because the anchors are reselected from the forecast on every redraw, the shown direction (Opk/Afg) flips at the exact moment a predicted extremum passes — no 30-minute lag waiting for the next sync. The server only sends the forecast table; prev/next are not snapshotted on the watch.

### Springtij and doodtij

The tidal range follows the ~29.5-day lunar synodic cycle. Around new and full moon the sun and moon pull in line and the range peaks (*springtij* — spring tide). Around first and last quarter they pull at right angles and the range is smallest (*doodtij* — neap tide). In Zeeland the actual peak lags the lunar phase by roughly two days, so Swimfo offsets by that amount when labelling days.

No astronomy API is needed — the server computes the phase from a reference new moon (2000-01-06 18:14 UTC) plus the synodic period. Four peaks per cycle (SPR, DTJ, SPR, DTJ) are enumerated around "now"; the nearest peak — measured in Europe/Amsterdam calendar days — drives the label:

- Within 2 days of a peak: `springtij` / `doodtij` on the day itself, or `2d tot springtij` / `1d na doodtij` for neighbours.
- Otherwise: `Xd tot springtij` / `Xd tot doodtij` counting down to the next peak of any type.

The label appears below the current tide level on the main tide page, and per day in the full tide table — so you can pick swim days with the strongest (springtij) or mildest (doodtij) currents at a glance.

## Development

### Prerequisites

- [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) 8.x ([API docs](https://developer.garmin.com/connect-iq/api-docs/), [programmer's guide](https://developer.garmin.com/connect-iq/connect-iq-basics/))
- Node.js 18+
- OpenSSL (for key generation)
- Make

### Setup

```bash
# Copy SDK to project (needed for writable access)
cp -a ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-*latest*/ .sdk/
chmod -R u+w .sdk/

# Generate developer signing key
make keygen

# Install server dependencies
make server-build
```

### Build and run

```bash
make help           # show all targets
make build          # compile debug build (default device: fenix7)
make run            # build + launch in simulator
make release        # build .iq package for all devices
make clean          # remove build artifacts

# Server
make server-run     # run API proxy in foreground (port 31415)
make server-start   # start API proxy in background
make server-stop    # stop API proxy
make server-debug   # fetch fresh data and print cache
make server-clean   # remove server artifacts

# Target a different device
make DEVICE=venu2 build
```

### Sideloading alongside the store build

`manifest.xml` carries the production UUID (`871b853b-…`) published to the Connect IQ store. Garmin identifies apps by that UUID, so a sideloaded debug build with the same UUID collides with the store-installed copy — the watch refuses the second install, or the store auto-update reverts your dev changes.

When developing against a watch that already has the store build, temporarily swap the UUID to the previous dev value so both can coexist:

```bash
# before sideloading a dev build
sed -i 's/871b853b-bf14-48a4-95ad-6dcc2c6ae471/4296c8ec-ce06-4e75-becf-e30dda703700/' manifest.xml

# do your thing: make build, push .prg to the watch, test

# restore before committing or before `make release`
sed -i 's/4296c8ec-ce06-4e75-becf-e30dda703700/871b853b-bf14-48a4-95ad-6dcc2c6ae471/' manifest.xml
```

Never commit the dev UUID and never upload a `.iq` built with it to the store — the store ties ratings, installs, and update delivery to the production UUID.

### SDK reference

Useful local paths when digging into Connect IQ behavior:

- SDK install root: `~/.Garmin/ConnectIQ/`
- Installed SDKs: `~/.Garmin/ConnectIQ/Sdks/` (project uses `connectiq-sdk-lin-8.3.0-2025-09-22-5813687a0` copied into `.sdk/`)
- **SDK samples** (reference implementations): `~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-8.3.0-2025-09-22-5813687a0/samples`
- Per-device specs (`compiler.json` — icon sizes, memory limits, display dims): `~/.Garmin/ConnectIQ/Devices/<device>/compiler.json`
- Per-device system icons (SVGs): `~/.Garmin/ConnectIQ/Devices/<device>/system_icon_*.svg`
- API symbol DB: `.sdk/bin/api.debug.xml` (grep for class/method docs faster than the online API)

### Sync error codes

When the background fetch fails, the Sync page shows `Fout: <code>`. The code is either an HTTP status from the server (≥ 400) or a negative Connect IQ error constant. Common values:

| Code   | Symbol                                  | Meaning |
|--------|-----------------------------------------|---------|
| -2     | `NETWORK_REQUEST_TIMED_OUT`             | Phone or upstream took too long |
| -101   | `BLE_CONNECTION_UNAVAILABLE`            | Phone not connected, Bluetooth off, or Garmin Connect not running |
| -102   | `BLE_HOST_TIMEOUT`                      | Bluetooth handoff timeout |
| -103   | `BLE_SERVER_TIMEOUT`                    | Phone-side request timeout |
| -104   | `BLE_NO_DATA`                           | Phone returned no payload |
| -300   | `NETWORK_RESPONSE_OUT_OF_MEMORY`        | Response too large for the watch to parse — trim payload server-side |
| -400   | `INVALID_HTTP_BODY_IN_NETWORK_RESPONSE` | Body wasn't valid for the declared content type |
| -401   | `INVALID_HTTP_HEADER_FIELDS_IN_RESPONSE`| Malformed response headers |
| -403   | `NETWORK_RESPONSE_TOO_LARGE`            | Body exceeded the per-request size limit |
| -1001  | `UNABLE_TO_CONNECT_TO_SERVER`           | Hostname/SSL/cert issue, or server down |
| 4xx    | (HTTP)                                  | Server reachable but returned a client error |
| 5xx    | (HTTP)                                  | Server reachable but returned a server error |

Full reference: [Toybox.Communications constants](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html).

### Location configuration

#### Adding a new location

1. Find the RWS station code at [waterinfo.rws.nl](https://waterinfo.rws.nl/)
2. Add the station to `source/Locations.mc` and `server/index.js` (LOCATIONS map)
3. Add the list entry in `resources/settings/settings.xml`
4. Add the string in `resources/strings/strings.xml`
