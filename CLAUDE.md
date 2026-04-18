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
  src/index.ts              Node.js proxy server — aggregates Open-Meteo + RWS APIs.
  src/lib.ts                Shared helpers (LOCATIONS, moon phase, lunar events).
  src/debug.ts              Prints cached data formatted like watch pages.
  src/debug-tide.ts         Standalone raw-RWS dump inspector.
  src/check-response.ts     Curl helper for the /conditions endpoint.
  tsconfig.json             TypeScript build config (compiles src/ → dist/).
  .env.example              Default server configuration.
  package.json              Server dependencies + scripts.
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

All API calls are made by the proxy server (`server/src/index.ts`), not the watch:

- Open-Meteo: `https://api.open-meteo.com/v1/forecast` (free, no key)
- RWS: `https://ddapi20-waterwebservices.rijkswaterstaat.nl/ONLINEWAARNEMINGENSERVICES` (free, no key)

Configured via `server/.env` (copy from `.env.example`).

## Locations

Defined in two places (keep in sync):
- `source/Locations.mc` — watch-side (name, lat/lon, rwsCode)
- `server/src/lib.ts` — server-side LOCATIONS map (name, lat, lon, rwsCode)

Current locations:
- Vlissingen: rwsCode `vlissingen`
- Oesterdam: rwsCode `marollegat` (Yerseke's temperature sensor has been offline since 1981; Marollegat has a live NKE CT sensor. Watch displays "Oesterdam" since that's the more recognizable landmark; settings label is "Oosterschelde (Oesterdam / Marollegat)".)
- Ossenisse: rwsCode `ossenisse` (Westerschelde; tide + water temp both live)
- Terneuzen: rwsCode `terneuzen`. No live T/OW sensor — `waterTemp: false` in server LOCATIONS skips the RWS temp fetch; watch shows `--°C` on water page.
- Oranjeplaat: rwsCode `arnemuiden.oranjeplaat`, URL slug `oranjeplaat`. Non-tidal (Veerse Meer is closed off since 1961) — `tide: false` in server LOCATIONS disables the RWS tide fetch + moon info. Watch shows "N/A" on tide pages, water temp/weather work normally.

Server LOCATIONS keys are URL slugs (must match regex `\w+`); `rwsCode` is sent to RWS as `Locatie.Code` and may contain dots (e.g. `arnemuiden.oranjeplaat`). Watch `rwsCode` must equal the server URL slug (not the RWS code) since it's embedded in the request path.

To add a location: add to both Locations.mc and server LOCATIONS, add list entry in `resources/settings/settings.xml`, add string in `resources/strings/strings.xml`.

## Server

The proxy server is written in TypeScript (sources in `server/src/`, compiled to `server/dist/` by `tsc`). It runs on port 31415 (configurable via `.env`) and:
- Aggregates 3 upstream APIs into a single small JSON response
- Caches responses on disk for 1 hour (configurable via `CACHE_TTL_MS`)
- Logs all requests to `server/logs/server.log`

```bash
make server-run     # build + foreground
make server-start   # build + background
make server-stop    # stop background server
make server-debug   # refresh + print cached data (LOCATION=vlissingen)
make server-clean   # remove node_modules, dist, cache, logs
```

The Makefile `server-build` target runs `npm install && npm run build` (= `tsc`). All server targets depend on `server-build`, so a fresh `make server-run` recompiles before launching.
