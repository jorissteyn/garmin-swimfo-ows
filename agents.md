# Swimfo Agents

## Overview

Swimfo uses a client-server architecture with two main components:

### Watch Agent (Garmin Connect IQ Widget)

The Garmin watch runs a lightweight widget that:
- Fetches pre-aggregated data from the proxy server every 30 minutes via a background service
- Stores the result in `Application.Storage` for offline access
- Renders data across 4 swipeable pages + a glance view in the widget carousel

**Source**: `source/` directory (Monkey C)

| File | Role |
|------|------|
| `SwimfoApp.mc` | App lifecycle, background event registration, data persistence |
| `SwimfoService.mc` | Background service — single GET to proxy server |
| `SwimfoWidgetView.mc` | Multi-page widget renderer with drawn icons |
| `SwimfoWidgetDelegate.mc` | Swipe input handler for page navigation |
| `SwimfoGlanceView.mc` | 2-line glance summary for widget carousel |
| `Locations.mc` | Location definitions (name, coordinates, RWS code) |

### Server Agent (Node.js Proxy)

The proxy server aggregates multiple upstream APIs into a single compact response:

**Source**: `server/` directory (Node.js)

| File | Role |
|------|------|
| `index.js` | HTTP server — routes, upstream fetchers, parsers, caching |
| `debug.js` | CLI tool to inspect cached data (formatted like watch pages) |
| `.env.example` | Default configuration (port, API URLs, cache TTL) |

#### Upstream API calls

| Call | Method | Upstream | Data |
|------|--------|----------|------|
| Weather | GET | Open-Meteo | Air temperature, wind speed |
| Tide | POST | RWS OphalenWaarnemingen | Water levels (astronomical predictions) |
| Water temp | POST | RWS OphalenLaatsteWaarnemingen | Sea surface temperature |

#### Processing pipeline

1. Receive `GET /conditions/{locationCode}` from watch
2. Check disk cache for each upstream call (1h TTL)
3. Fetch any stale/missing data from upstream APIs in parallel
4. Parse RWS responses: extract water level, compute tide direction, find next HW/LW extremum
5. Merge all data into a flat JSON response (~300 bytes)
6. Cache results to disk, log request, return response

#### Response format

```json
{
  "locName": "Vlissingen",
  "airTemp": 15.2,
  "windSpeed": 12.5,
  "waterTemp": 11.0,
  "waterLevel": 1.83,
  "tideRising": true,
  "nextTideLevel": 3.21,
  "nextTideTime": "14:32",
  "nextTideType": "HW"
}
```

## Communication

```
Watch (background, every 30 min)
  │
  │  GET /conditions/vlissingen
  │  (via phone Bluetooth → internet)
  ▼
Proxy Server (:31415)
  │
  ├── GET  api.open-meteo.com/v1/forecast
  ├── POST ddapi20-waterwebservices.rijkswaterstaat.nl/.../OphalenWaarnemingen
  └── POST ddapi20-waterwebservices.rijkswaterstaat.nl/.../OphalenLaatsteWaarnemingen
  │
  ▼
Watch stores result → Application.Storage → Widget reads on each onUpdate()
```
