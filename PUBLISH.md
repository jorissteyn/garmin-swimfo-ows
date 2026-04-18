# Publishing to the Connect IQ Store

## Build the .iq package

```bash
make release
```

Produces `bin/ZeelandOWS.iq` — the single bundle uploaded to the store. It contains compiled code for every device listed in `manifest.xml` (fenix 5+ and newer, epix 2 series, Forerunner 165/265/955/965, Venu 2/3 series, vivoactive 4/5, etc.).

Prerequisites:
- `developer_key.der` in the project root. If you don't have one, run `make keygen` first.
- The SDK at `.sdk/` (see README → Development → Setup).

The release build uses the production server URL (`ows.j0r1s.nl`); it does **not** point at localhost.

## Upload to the store

1. Sign in at [apps.garmin.com/en-US/developer](https://apps.garmin.com/en-US/developer).
2. Open the existing app entry (or create a new one).
3. Under "App package" → "Upload new version", pick `bin/ZeelandOWS.iq`.
4. Bump the version in `manifest.xml` (`<iq:application version="...">`) before each new upload — the store rejects duplicate versions.
5. Paste the store listing below, upload screenshots, submit for review.

Review typically takes a few days. Rejected builds come back with feedback; fix, rebuild, re-upload.

## Store listing (Dutch)

### Titel

Zeeland OWS

### Korte omschrijving

Open water zwemmen in Zeeland: Getij, watertemperatuur en wind direct op je Garmin horloge.

### Volledige beschrijving

Plain text only — geen markdown. Kopjes worden in HOOFDLETTERS weergegeven.

VOOR DE ZEEUWSE OPEN WATER ZWEMMER

Alles wat je nodig hebt voor een duik in de Westerschelde of Oosterschelde, recht op je pols. Geen abonnement, geen reclame, geen account — gewoon aanzetten en zwemmen.

GETIJ OP ELK MOMENT
Zie in één oogopslag of het water opkomt of afgaat, hoe hoog het nu staat, en wanneer het volgende hoogwater of laagwater komt. De app schat het actuele waterpeil continu bij op basis van de getijvoorspelling, zodat het cijfer tussen metingen door vloeiend meebeweegt met het echte tij — ook als je horloge even geen verbinding heeft. Groen pijltje omhoog betekent opkomend water, rood pijltje omlaag betekent afgaand.

GETIJDENTABEL — 7 DAGEN VOORUIT
Tik op de getijpagina voor een volledig weekoverzicht van hoog- en laagwater.

SPRINGTIJ EN DOODTIJ
Springtij (rond nieuwe en volle maan, grootste waterbeweging) en doodtij (rond eerste en laatste kwartier, rustigste tij) worden bij de datum in de tabel getoond en op de hoofdpagina samengevat. Ideaal voor het kiezen van het juiste moment.

WATERTEMPERATUUR
Actuele watertemperatuur van het gekozen meetpunt.

WEER OP ZWEMHOOGTE
Luchttemperatuur en windsnelheid, inclusief windkracht op de schaal van Beaufort.

GLANCE IN JE WIDGET-CARROUSEL
De belangrijkste info — tijrichting, waterhoogte, watertemperatuur, lucht en wind — samengevat op twee regels, zichtbaar zonder de app te openen. Als je de glance in je carrousel zet, werkt de data elke 30 minuten automatisch bij op de achtergrond.

KIES JE LOCATIE
- Westerschelde (Vlissingen)
- Oosterschelde (Oesterdam / meetpunt Marollegat)
- Westerschelde (Ossenisse)
- Westerschelde (Terneuzen) — geen watertemperatuur beschikbaar
- Veerse Meer (meetpunt Oranjeplaat) — geen getij beschikbaar

Standaard staat de app op Vlissingen; via de Garmin Connect app op je telefoon kies je een andere locatie. Het Veerse Meer is sinds de aanleg van de Veerse Gatdam (1961) een afgesloten meer zonder getij — voor die locatie toont de app "N/A" op de getijpagina's; watertemperatuur en weer werken gewoon.

GEGEVENSBRONNEN
- Getij en watertemperatuur: Rijkswaterstaat (waterinfo.rws.nl)
- Luchttemperatuur en wind: Open-Meteo

### Categorie / tags

- Category: Widget
- Tags: open water, swimming, tide, weather, Zeeland, Netherlands, Westerschelde, Oosterschelde, getij

### Screenshots te maken

- Glance in widget carrousel
- Tide page (met pijl + waterhoogte + volgend HW/LW + springtij)
- Getijdentabel (dag header + springtij label + HW/LW rijen)
- Water page
- Weather page
- Sync page
