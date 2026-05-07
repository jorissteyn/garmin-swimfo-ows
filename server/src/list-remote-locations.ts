// List every RWS station that has tide-extrema data available, so we can pick
// which ones to add to the watch's location list. Filters the catalog to the
// (WATHTE, GETETBRKD2) combination — the same query the proxy server uses to
// fetch HW/LW extremes — so a hit means "we can show tide for this station".
//
// Usage: `npm run list-remote-locations` (or `make server-list-locations`)

import dotenv from "dotenv";

dotenv.config();

// The catalog lives on METADATASERVICES, not ONLINEWAARNEMINGENSERVICES (where
// the proxy queries observations). Same host, different service collection —
// strip the trailing service segment off RWS_BASE_URL so we share that env var
// with the rest of the server tooling.
const RWS_BASE_URL =
  process.env.RWS_BASE_URL ||
  "https://ddapi20-waterwebservices.rijkswaterstaat.nl/ONLINEWAARNEMINGENSERVICES";
const RWS_HOST = RWS_BASE_URL.replace(/\/[^/]+\/?$/, "");
const CATALOG_URL = `${RWS_HOST}/METADATASERVICES/OphalenCatalogus`;

interface Locatie {
  Locatie_MessageID: number;
  Code: string;
  Naam: string;
}

interface AquoMetadata {
  AquoMetadata_MessageID: number;
  Grootheid?: { Code?: string };
  Groepering?: { Code?: string };
  ProcesType?: string;
}

interface AquoMetadataLocatieLink {
  Locatie_MessageID: number;
  AquoMetaData_MessageID: number;
}

interface CatalogusResponse {
  Succesvol?: boolean;
  Foutmelding?: string;
  LocatieLijst?: Locatie[];
  AquoMetadataLijst?: AquoMetadata[];
  AquoMetadataLocatieLijst?: AquoMetadataLocatieLink[];
}

const TIDE_GROEPERING = "GETETBRKD2";

async function main(): Promise<void> {
  console.log(`POST ${CATALOG_URL} (filtering for Grootheid=WATHTE, Groepering=${TIDE_GROEPERING})\n`);

  const res = await fetch(CATALOG_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({
      CatalogusFilter: {
        Grootheden: true,
        Groeperingen: true,
        Compartimenten: true,
        Hoedanigheden: true,
        Eenheden: true,
        Parameters: true,
      },
    }),
  });

  if (!res.ok) {
    console.error(`HTTP ${res.status} ${res.statusText}`);
    process.exit(1);
  }

  const data = (await res.json()) as CatalogusResponse;
  if (!data.Succesvol) {
    console.error(`API error: ${data.Foutmelding ?? "unknown"}`);
    process.exit(1);
  }

  // Step 1: collect AquoMetadata IDs that match (WATHTE + GETETBRKD2).
  const tideMetaIds = new Set<number>();
  for (const m of data.AquoMetadataLijst ?? []) {
    if (m.Grootheid?.Code !== "WATHTE") continue;
    if (m.Groepering?.Code !== TIDE_GROEPERING) continue;
    tideMetaIds.add(m.AquoMetadata_MessageID);
  }

  // Step 2: cross-reference to find locations linked to any of those.
  const tideLocIds = new Set<number>();
  for (const link of data.AquoMetadataLocatieLijst ?? []) {
    if (tideMetaIds.has(link.AquoMetaData_MessageID)) {
      tideLocIds.add(link.Locatie_MessageID);
    }
  }

  const tideLocs = (data.LocatieLijst ?? [])
    .filter((l) => tideLocIds.has(l.Locatie_MessageID))
    .sort((a, b) => a.Naam.localeCompare(b.Naam, "nl"));

  console.log(`Found ${tideLocs.length} stations with tide-extrema data:\n`);
  console.log(`  ${"Naam".padEnd(40)}  rwsCode`);
  console.log(`  ${"-".repeat(40)}  ${"-".repeat(30)}`);
  for (const l of tideLocs) {
    console.log(`  ${l.Naam.padEnd(40)}  ${l.Code}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
