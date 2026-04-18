# Swimfo - Development Guide

## What is this?

Garmin Connect IQ widget (Monkey C) for open water swimming conditions in the Netherlands. Displays tide, wind, and temperature data via a multi-page widget with glance support.

## Build

```bash
make keygen    # one-time: generate developer_key.der
make build     # compile for simulator (default: fenix7)
make run       # build + launch in simulator
make clean     # remove bin/
```

Override device: `make DEVICE=venu2 build`

The SDK must be at `.sdk/` (copied from `~/.Garmin/ConnectIQ/Sdks/`). The Makefile sets `_JAVA_OPTIONS` to redirect Java tmpdir into `bin/.tmp` because the system `/tmp` may be read-only.

## Project structure

```
source/
  SwimfoApp.mc              App lifecycle. Registers background temporal events.
  SwimfoWidgetView.mc       Widget rendering (4 swipeable pages with drawn icons).
  SwimfoWidgetDelegate.mc   Swipe input handling for page navigation.
  SwimfoGlanceView.mc       Compact 2-line glance for widget carousel.
  SwimfoService.mc          Background service: single GET to proxy server.
  Locations.mc              Hardcoded location data (RWS station codes + coords).
server/
  index.js                  Node.js proxy server — aggregates Open-Meteo + RWS APIs.
  debug.js                  Prints cached data formatted like watch pages.
  .env.example              Default server configuration.
  package.json              Server dependencies (dotenv only).
resources/
  settings/                 Location picker (properties + settings XML).
  strings/                  String resources.
  drawables/                Launcher icon.
```

## Data flow

Background service runs every 30 min (5s on first launch if no cached data). Makes a single GET request to the proxy server:

```
Watch → GET http://localhost:31415/conditions/{locationCode} → proxy server
Proxy server fans out to:
  1. Open-Meteo (GET) → wind speed, air temp
  2. RWS OphalenWaarnemingen (POST) → water levels, parsed for current level, trend, next HW/LW
  3. RWS OphalenLaatsteWaarnemingen (POST) → water temperature
Proxy returns flat JSON (~300 bytes), cached for 1 hour.
```

Results stored in `Application.Storage` as a flat Dictionary. Widget views read from Storage on each `onUpdate()`.

## Widget pages

- **Page 0 (Tide)**: tide arrow (green up / red down), water level, OPK/AFG, next HW/LW with clock icon
- **Page 1 (Water)**: thermometer icon, water temperature, wave decoration
- **Page 2 (Weather)**: air temp with thermometer icon, wind speed with wind icon
- **Page 3 (Sync)**: refresh icon, last sync time and date
- **Glance**: 2-line summary — tide status + conditions

## Key conventions

- All types must be fully qualified with `Lang.` prefix (e.g., `Lang.Dictionary`, `Lang.String`) -- SDK 8.x requirement.
- Classes used in background context need `(:background)` annotation.
- Glance view class needs `(:glance)` annotation.
- `onStart()` runs in BOTH foreground and background -- never call `Storage` or `Background.registerForTemporalEvent` there.
- Icons are drawn with `Graphics.Dc` primitives (fillPolygon, drawArc, etc.), not bitmap resources.

## API endpoints

All API calls are made by the proxy server (`server/index.js`), not the watch:

- Open-Meteo: `https://api.open-meteo.com/v1/forecast` (free, no key)
- RWS: `https://ddapi20-waterwebservices.rijkswaterstaat.nl/ONLINEWAARNEMINGENSERVICES` (free, no key)

Configured via `server/.env` (copy from `.env.example`).

## Locations

Defined in two places (keep in sync):
- `source/Locations.mc` — watch-side (name, lat/lon, rwsCode)
- `server/index.js` — server-side LOCATIONS map (name, lat, lon, rwsCode)

Current locations:
- Vlissingen: rwsCode `vlissingen`
- Yerseke: rwsCode `yerseke`

To add a location: add to both Locations.mc and server LOCATIONS, add list entry in `resources/settings/settings.xml`, add string in `resources/strings/strings.xml`.

## Server

The Node.js proxy server runs on port 31415 (configurable via `.env`). It:
- Aggregates 3 upstream APIs into a single small JSON response
- Caches responses on disk for 1 hour (configurable via `CACHE_TTL_MS`)
- Logs all requests to `server/logs/server.log`

```bash
make server-run     # foreground
make server-start   # background
make server-stop    # stop background server
make server-debug   # refresh + print cached data (LOCATION=vlissingen)
make server-clean   # remove node_modules, cache, logs
```
