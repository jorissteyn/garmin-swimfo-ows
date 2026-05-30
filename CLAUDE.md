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

### Simulator runs in a container

The `simulator` binary is a native GTK/WebKit program linked against the
`libwebkit2gtk-4.0` / `libjavascriptcoregtk-4.0` / `libsoup-2.4` series, which
rolling distros (e.g. openSUSE Tumbleweed) have dropped in favour of 4.1 —
breaking it with `error while loading shared libraries:
libjavascriptcoregtk-4.0.so.18`. To insulate it from the host distro, the
simulator runs inside an Ubuntu 22.04 container (`docker/simulator/Dockerfile`)
with X11 forwarded to the host.

This is transparent: `make sim-start` builds the image on first use and starts
the container; `make run`/`make test` are unchanged. Only the simulator moved —
`monkeyc`/`monkeydo` stay on the host (pure Java + a generic native transport)
and reach the simulator over loopback. The simulator listens on
`127.0.0.1:1234`; the container uses `--network host` so host-side `monkeydo`
connects with no changes. The SDK and `~/.Garmin` (device + font data) are
bind-mounted, and the container runs as the host user, so the image carries
only runtime libraries and is independent of the SDK version.

```bash
make sim-start    # build image (first run) + start simulator container
make sim-stop     # stop + remove the container
make sim-rebuild  # force a clean rebuild of the image (--no-cache)
```

Requires Docker with the user in the `docker` group, an X11 display, and
`xhost` (sim-start runs `xhost +local:` so the container can reach the display).

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
- `source/Locations.mc` — watch-side (name, lat/lon, locationSlug)
- `server/src/lib.ts` — server-side LOCATIONS map (slug → name, lat, lon, rwsCode)

### Slug vs rwsCode

We maintain our own location ids:

- **Slug** — our id, used as the URL path segment (`GET /conditions/<slug>`)
  and as the `locationSlug` field on the watch. Must match `\w+` (no dots).
  Stable, owned by us.
- **rwsCode** — the value the proxy sends to RWS as `Locatie.Code`. May
  contain dots (e.g. `kats.zandkreeksluis`). Owned by RWS.

For most stations they're the same string (`vlissingen`, `ossenisse`,
`terneuzen`). They diverge when we want a friendlier URL than the real
station id, or when the RWS station that has the data isn't named after
the swimming spot — see Kats, Breskens, Oranjeplaat below. The watch
never sees the rwsCode; only `server/src/lib.ts` knows the mapping.

Current locations (id order matches `Locations.mc`, `settings.xml`, and the
server `LOCATIONS` map):
- Vlissingen (id 0): rwsCode `vlissingen`
- Kats (id 1): rwsCode `kats.zandkreeksluis`, URL slug `kats`. RWS has no plain `kats` station with tide data; the closest is the Zandkreeksluis lock-side station, which carries the Oosterschelde HW/LW.
- Breskens (id 2): rwsCode `breskens.veerhaven`, URL slug `breskens`. Westerschelde, opposite Vlissingen.
- Oesterdam (id 3): rwsCode `marollegat` (Yerseke's temperature sensor has been offline since 1981; Marollegat has a live NKE CT sensor. Watch displays "Oesterdam" since that's the more recognizable landmark; settings label is "Oosterschelde (Oesterdam / Marollegat)". Server `name` matches.)
- Oranjeplaat (id 4): rwsCode `arnemuiden.oranjeplaat`, URL slug `oranjeplaat`. Non-tidal (Veerse Meer is closed off since 1961) — `tide: false` in server LOCATIONS disables the RWS tide fetch + moon info. Watch shows "N/A" on tide pages, water temp/weather work normally.
- Ossenisse (id 5): rwsCode `ossenisse` (Westerschelde; tide + water temp both live)
- Terneuzen (id 6): rwsCode `terneuzen`. No live T/OW sensor — `waterTemp: false` in server LOCATIONS skips the RWS temp fetch; watch shows `--°C` on water page.

Server LOCATIONS keys are URL slugs (must match regex `\w+`); `rwsCode` is sent to RWS as `Locatie.Code` and may contain dots (e.g. `arnemuiden.oranjeplaat`). Watch `locationSlug` (in `Locations.mc`) is the same URL slug, not the RWS code.

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
