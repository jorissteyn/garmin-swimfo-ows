# Swimfo

Garmin Connect IQ widget for open water swimming conditions in the Netherlands. Shows real-time tide, wind, and temperature data on your watch.

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

## Supported locations

| Location     | RWS station | Body of water  |
|-------------|-------------|----------------|
| Vlissingen  | vlissingen  | Westerschelde  |
| Kattendijke | yerseke     | Oosterschelde  |

## Supported devices

fenix 7 / 7S / 7X, Venu 2 / 2S, Forerunner 955 / 965, epix 2

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
