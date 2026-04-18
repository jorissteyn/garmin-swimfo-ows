// Shared helpers for server/index.js and server/debug.js.

const LOCATIONS = {
  vlissingen: {
    name: "Vlissingen",
    lat: 51.4425,
    lon: 3.5964,
    rwsCode: "vlissingen",
  },
  yerseke: {
    name: "Yerseke",
    lat: 51.4933,
    lon: 3.96,
    rwsCode: "yerseke",
  },
};

// ── Moon phase ──────────────────────────────────────────────

// Reference new moon: Jan 6, 2000 18:14 UTC
const REF_NEW_MOON_MS = new Date("2000-01-06T18:14:00Z").getTime();
const SYNODIC_DAYS = 29.530588853;
const SYNODIC_MS = SYNODIC_DAYS * 24 * 3600 * 1000;
// Springtij/doodtij peak ~2 days after the triggering lunar phase (RWS).
const PHASE_PEAK_OFFSET_DAYS = 2;
const PHASE_PEAK_OFFSET_MS = PHASE_PEAK_OFFSET_DAYS * 24 * 3600 * 1000;

// Calendar-day index in Europe/Amsterdam, so "peak is tomorrow" reads as +1 even
// when the peak epoch is only a few hours away across midnight.
const AMS_DAY_FMT = new Intl.DateTimeFormat("en-CA", {
  timeZone: "Europe/Amsterdam",
  year: "numeric", month: "2-digit", day: "2-digit",
});
function amsDayIndex(ms) {
  const [y, m, d] = AMS_DAY_FMT.format(new Date(ms)).split("-").map(Number);
  return Date.UTC(y, m - 1, d) / 86400000;
}

function getMoonInfo() {
  const now = Date.now();
  // Enumerate peaks across a few cycles around now; 4 per cycle (SPR, DTJ, SPR, DTJ).
  const cycleStart = Math.floor((now - REF_NEW_MOON_MS) / SYNODIC_MS) - 1;
  const quarterMs = SYNODIC_MS / 4;
  const peakTypes = ["springtij", "doodtij", "springtij", "doodtij"];
  const peaks = [];
  for (let n = cycleStart; n <= cycleStart + 2; n++) {
    const base = REF_NEW_MOON_MS + n * SYNODIC_MS + PHASE_PEAK_OFFSET_MS;
    for (let q = 0; q < 4; q++) {
      peaks.push({ type: peakTypes[q], ms: base + q * quarterMs });
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

  let label;
  if (Math.abs(nearestDiff) <= 2) {
    if (nearestDiff === 0)    label = nearest.type;
    else if (nearestDiff > 0) label = `${nearestDiff}d tot ${nearest.type}`;
    else                      label = `${-nearestDiff}d na ${nearest.type}`;
  } else {
    // Between peak windows — show the next upcoming peak of any type.
    let nextType = peaks[0].type;
    let nextDiff = Infinity;
    for (const p of peaks) {
      const diff = amsDayIndex(p.ms) - today;
      if (diff > 0 && diff < nextDiff) { nextDiff = diff; nextType = p.type; }
    }
    label = `${nextDiff}d tot ${nextType}`;
  }

  return { moonLabel: label };
}

// Lunar tide events (springtij / doodtij) within [startMs, endMs].
// Each event is +2 days after the triggering lunar phase.
function getLunarEvents(startMs, endMs) {
  const quarterMs = SYNODIC_MS / 4;
  const events = [];

  // Sweep a few cycles around the range; each cycle has 2 springs + 2 neaps.
  const firstCycle = Math.floor((startMs - REF_NEW_MOON_MS) / SYNODIC_MS) - 1;
  const lastCycle = Math.ceil((endMs - REF_NEW_MOON_MS) / SYNODIC_MS) + 1;

  for (let n = firstCycle; n <= lastCycle; n++) {
    const cycleStart = REF_NEW_MOON_MS + n * SYNODIC_MS;
    const candidates = [
      { type: "SPR", ts: cycleStart + PHASE_PEAK_OFFSET_MS },
      { type: "DTJ", ts: cycleStart + quarterMs + PHASE_PEAK_OFFSET_MS },
      { type: "SPR", ts: cycleStart + 2 * quarterMs + PHASE_PEAK_OFFSET_MS },
      { type: "DTJ", ts: cycleStart + 3 * quarterMs + PHASE_PEAK_OFFSET_MS },
    ];
    for (const c of candidates) {
      if (c.ts >= startMs && c.ts <= endMs) {
        events.push({ type: c.type, epoch: Math.floor(c.ts / 1000) });
      }
    }
  }
  return events;
}

module.exports = {
  LOCATIONS,
  getMoonInfo,
  getLunarEvents,
};
