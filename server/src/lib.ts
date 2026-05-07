// Shared helpers for server/src/index.ts and server/src/debug.ts.

export interface Location {
  name: string;
  lat: number;
  lon: number;
  rwsCode: string;
  // Some locations (e.g. Veerse Meer) are non-tidal lakes — RWS has no
  // astronomical tide prediction for them. Default: true.
  tide?: boolean;
  // Some RWS stations don't have a live T/OW sensor (e.g. Terneuzen).
  // Default: true.
  waterTemp?: boolean;
}

// Order matches the watch-side Locations.mc / settings.xml id ordering, so the
// id ↔ slug mapping is consistent across watch, phone settings, and server.
export const LOCATIONS: Record<string, Location> = {
  vlissingen: {
    name: "Vlissingen",
    lat: 51.4425,
    lon: 3.5964,
    rwsCode: "vlissingen",
  },
  kats: {
    name: "Kats",
    lat: 51.543947,
    lon: 3.865418,
    // RWS publishes Oosterschelde tide extremes under the lock-side station
    // `kats.zandkreeksluis`; there is no plain "kats" station with tide data.
    rwsCode: "kats.zandkreeksluis",
  },
  breskens: {
    name: "Breskens",
    lat: 51.403661,
    lon: 3.550427,
    rwsCode: "breskens.veerhaven",
  },
  marollegat: {
    name: "Oesterdam",
    lat: 51.479747,
    lon: 4.191958,
    rwsCode: "marollegat",
  },
  oranjeplaat: {
    name: "Oranjeplaat",
    lat: 51.51661,
    lon: 3.70014,
    rwsCode: "arnemuiden.oranjeplaat",
    tide: false,
  },
  ossenisse: {
    name: "Ossenisse",
    lat: 51.390833,
    lon: 3.9925,
    rwsCode: "ossenisse",
  },
  terneuzen: {
    name: "Terneuzen",
    lat: 51.336,
    lon: 3.827,
    rwsCode: "terneuzen",
    waterTemp: false,
  },
};

// ── Moon phase ──────────────────────────────────────────────

// Springtij/doodtij peak ~2 days after the triggering lunar phase (RWS).
const PHASE_PEAK_OFFSET_MS = 2 * 86400000;

// Rough cycle index estimate. Each lunar synodic cycle drifts up to ±6h from
// the mean due to elliptical orbit effects, so we use a wide window and let
// Meeus do the precise placement below.
const SYNODIC_MS_APPROX = 29.530588853 * 86400000;
const K_REF_MS = Date.UTC(2000, 0, 6, 18, 14, 0); // ≈ k=0 new moon

// Lunar phase by Meeus, Astronomical Algorithms (2nd ed.) ch. 49. Returns the
// UTC ms epoch of phase `p` (0=new, 1=Q1, 2=full, 3=Q3) for synodic cycle
// index `kInt` (k=0 is the new moon of 2000-01-06). Accurate to ~1 minute,
// which is well below the 12-hour day-rounding tolerance we need for
// "is the peak today or tomorrow?". The earlier linear-mean approximation
// drifted ~6h per cycle and occasionally flipped the calendar day in
// Europe/Amsterdam (e.g. May 2026 SPR labelled May 4 instead of May 3).
//
// TT vs UTC is ignored: the offset is ~70s in the 2020s, far below precision
// we care about.
const J2000_TT_MS = Date.UTC(2000, 0, 1, 12, 0, 0);
const D2R = Math.PI / 180;

function lunarPhaseMs(kInt: number, p: 0 | 1 | 2 | 3): number {
  const k = kInt + p * 0.25;
  const T = k / 1236.85;
  const T2 = T * T, T3 = T2 * T, T4 = T3 * T;

  const JDE0 = 2451550.09766 + 29.530588861 * k + 0.00015437 * T2
             - 0.000000150 * T3 + 0.00000000073 * T4;
  const M  = D2R * (2.5534   + 29.10535670  * k - 0.0000014 * T2 - 0.00000011 * T3);
  const Mp = D2R * (201.5643 + 385.81693528 * k + 0.0107582 * T2
                + 0.00001238 * T3 - 0.000000058 * T4);
  const F  = D2R * (160.7108 + 390.67050284 * k - 0.0016118 * T2
                - 0.00000227 * T3 + 0.000000011 * T4);
  const Om = D2R * (124.7746 - 1.56375588   * k + 0.0020672 * T2 + 0.00000215 * T3);
  const E  = 1 - 0.002516 * T - 0.0000074 * T2;

  let c = 0;
  if (p === 0 || p === 2) {
    const isNew = p === 0;
    c += (isNew ? -0.40720 : -0.40614) * Math.sin(Mp);
    c += (isNew ?  0.17241 :  0.17302) * E * Math.sin(M);
    c += (isNew ?  0.01608 :  0.01614) * Math.sin(2 * Mp);
    c += (isNew ?  0.01039 :  0.01043) * Math.sin(2 * F);
    c += (isNew ?  0.00739 :  0.00734) * E * Math.sin(Mp - M);
    c += (isNew ? -0.00514 : -0.00515) * E * Math.sin(Mp + M);
    c += (isNew ?  0.00208 :  0.00209) * E * E * Math.sin(2 * M);
    c += -0.00111 * Math.sin(Mp - 2 * F);
    c += -0.00057 * Math.sin(Mp + 2 * F);
    c +=  0.00056 * E * Math.sin(2 * Mp + M);
    c += -0.00042 * Math.sin(3 * Mp);
    c +=  0.00042 * E * Math.sin(M + 2 * F);
    c +=  0.00038 * E * Math.sin(M - 2 * F);
    c += -0.00024 * E * Math.sin(2 * Mp - M);
    c += -0.00017 * Math.sin(Om);
    c += -0.00007 * Math.sin(Mp + 2 * M);
    c +=  0.00004 * Math.sin(2 * Mp - 2 * F);
    c +=  0.00004 * Math.sin(3 * M);
    c +=  0.00003 * Math.sin(Mp + M - 2 * F);
    c +=  0.00003 * Math.sin(2 * Mp + 2 * F);
    c += -0.00003 * Math.sin(Mp + M + 2 * F);
    c +=  0.00003 * Math.sin(Mp - M + 2 * F);
    c += -0.00002 * Math.sin(Mp - M - 2 * F);
    c += -0.00002 * Math.sin(3 * Mp + M);
    c +=  0.00002 * Math.sin(4 * Mp);
  } else {
    c += -0.62801 * Math.sin(Mp);
    c +=  0.17172 * E * Math.sin(M);
    c += -0.01183 * E * Math.sin(Mp + M);
    c +=  0.00862 * Math.sin(2 * Mp);
    c +=  0.00804 * Math.sin(2 * F);
    c +=  0.00454 * E * Math.sin(Mp - M);
    c +=  0.00204 * E * E * Math.sin(2 * M);
    c += -0.00180 * Math.sin(Mp - 2 * F);
    c += -0.00070 * Math.sin(Mp + 2 * F);
    c += -0.00040 * Math.sin(3 * Mp);
    c += -0.00034 * E * Math.sin(2 * Mp - M);
    c +=  0.00032 * E * Math.sin(M + 2 * F);
    c +=  0.00032 * E * Math.sin(M - 2 * F);
    c += -0.00028 * E * E * Math.sin(Mp + 2 * M);
    c +=  0.00027 * E * Math.sin(2 * Mp + M);
    c += -0.00017 * Math.sin(Om);
    c += -0.00005 * Math.sin(Mp - M - 2 * F);
    c +=  0.00004 * Math.sin(2 * Mp + 2 * F);
    c += -0.00004 * Math.sin(Mp + M + 2 * F);
    c +=  0.00004 * Math.sin(Mp - 2 * M);
    c +=  0.00003 * Math.sin(Mp + M - 2 * F);
    c +=  0.00003 * Math.sin(3 * M);
    c +=  0.00002 * Math.sin(2 * Mp - 2 * F);
    c +=  0.00002 * Math.sin(Mp - M + 2 * F);
    c += -0.00002 * Math.sin(3 * Mp + M);
    const W = 0.00306 - 0.00038 * E * Math.cos(M) + 0.00026 * Math.cos(Mp)
            - 0.00002 * Math.cos(Mp - M) + 0.00002 * Math.cos(Mp + M)
            + 0.00002 * Math.cos(2 * F);
    c += p === 1 ? W : -W;
  }

  return J2000_TT_MS + (JDE0 + c - 2451545.0) * 86400000;
}

// Calendar-day index in Europe/Amsterdam, so "peak is tomorrow" reads as +1 even
// when the peak epoch is only a few hours away across midnight.
const AMS_DAY_FMT = new Intl.DateTimeFormat("en-CA", {
  timeZone: "Europe/Amsterdam",
  year: "numeric", month: "2-digit", day: "2-digit",
});
function amsDayIndex(ms: number): number {
  const [y, m, d] = AMS_DAY_FMT.format(new Date(ms)).split("-").map(Number);
  return Date.UTC(y, m - 1, d) / 86400000;
}

type PeakType = "springtij" | "doodtij";
interface Peak { type: PeakType; ms: number; }

// q=0 is springtij (after new moon), q=1 doodtij (Q1), q=2 springtij (full),
// q=3 doodtij (Q3). Returns the +2-day peak ms, not the lunar phase itself.
function peakMs(kInt: number, q: 0 | 1 | 2 | 3): number {
  return lunarPhaseMs(kInt, q) + PHASE_PEAK_OFFSET_MS;
}

const PEAK_TYPES: PeakType[] = ["springtij", "doodtij", "springtij", "doodtij"];

export interface MoonInfo {
  moonLabel: string;
}

export function getMoonInfo(): MoonInfo {
  const now = Date.now();
  const k0 = Math.floor((now - K_REF_MS) / SYNODIC_MS_APPROX);

  const peaks: Peak[] = [];
  for (let n = k0 - 1; n <= k0 + 1; n++) {
    for (let q = 0 as 0 | 1 | 2 | 3; q < 4; q++) {
      peaks.push({ type: PEAK_TYPES[q], ms: peakMs(n, q) });
    }
  }

  const today = amsDayIndex(now);
  let nearest = peaks[0];
  let nearestDiff = amsDayIndex(peaks[0].ms) - today;
  for (let i = 1; i < peaks.length; i++) {
    const diff = amsDayIndex(peaks[i].ms) - today;
    if (Math.abs(diff) < Math.abs(nearestDiff)) {
      nearest = peaks[i];
      nearestDiff = diff;
    }
  }

  let label: string;
  if (Math.abs(nearestDiff) <= 2) {
    if (nearestDiff === 0)    label = nearest.type;
    else if (nearestDiff > 0) label = `${nearestDiff}d tot ${nearest.type}`;
    else                      label = `${-nearestDiff}d na ${nearest.type}`;
  } else {
    // Between peak windows — show the next upcoming peak of any type.
    let nextType: PeakType = peaks[0].type;
    let nextDiff = Infinity;
    for (const p of peaks) {
      const diff = amsDayIndex(p.ms) - today;
      if (diff > 0 && diff < nextDiff) { nextDiff = diff; nextType = p.type; }
    }
    label = `${nextDiff}d tot ${nextType}`;
  }

  return { moonLabel: label };
}

export interface LunarEvent {
  type: "SPR" | "DTJ";
  epoch: number;
}

// Lunar tide events (springtij / doodtij) within [startMs, endMs].
// Each event is +2 days after the triggering lunar phase.
export function getLunarEvents(startMs: number, endMs: number): LunarEvent[] {
  const events: LunarEvent[] = [];
  const firstK = Math.floor((startMs - K_REF_MS) / SYNODIC_MS_APPROX) - 1;
  const lastK = Math.ceil((endMs - K_REF_MS) / SYNODIC_MS_APPROX) + 1;
  const tagFor: ("SPR" | "DTJ")[] = ["SPR", "DTJ", "SPR", "DTJ"];

  for (let n = firstK; n <= lastK; n++) {
    for (let q = 0 as 0 | 1 | 2 | 3; q < 4; q++) {
      const ts = peakMs(n, q);
      if (ts >= startMs && ts <= endMs) {
        events.push({ type: tagFor[q], epoch: Math.floor(ts / 1000) });
      }
    }
  }
  return events;
}
