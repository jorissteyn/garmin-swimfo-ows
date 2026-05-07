using Toybox.Application;
using Toybox.Lang;

(:background)
module Locations {

    // The watch never talks to RWS directly — it calls our proxy server at
    // GET /conditions/{locationSlug}, and the proxy maps that slug to RWS's
    // own station code (which can contain dots and other characters that
    // wouldn't fit in a URL path). So `locationSlug` here is OUR id for the
    // location, not RWS's. The authoritative slug-to-rwsCode mapping lives
    // server-side in server/src/lib.ts; the `rwsCode` field below is
    // informational only — the watch never reads it, it's here so dev tools
    // (server/src/list-supported-locations.ts) can show the full picture
    // without cross-referencing two files. When changing it, mirror the
    // change in server/src/lib.ts.
    //
    // Most slugs happen to match the RWS code (vlissingen, ossenisse,
    // terneuzen); a few diverge:
    //   slug "kats"         → RWS "kats.zandkreeksluis"
    //   slug "breskens"     → RWS "breskens.veerhaven"
    //   slug "oranjeplaat"  → RWS "arnemuiden.oranjeplaat"
    // The indirection keeps URLs stable if RWS renames a station.

    // Total number of locations defined here. Picker UIs iterate 0..count()-1
    // so adding a location only requires extending get() + settingsLabelRes()
    // (plus the phone-side settings.xml entry, which is XML and can't share
    // code).
    function count() as Lang.Number {
        return 7;
    }

    function get(id as Lang.Number) as Lang.Dictionary {
        if (id == 1) {
            return {
                "name" => "Kats",
                "lat" => 51.543947,
                "lon" => 3.865418,
                "locationSlug" => "kats",
                "rwsCode" => "kats.zandkreeksluis"
            };
        }
        if (id == 2) {
            return {
                "name" => "Breskens",
                "lat" => 51.403661,
                "lon" => 3.550427,
                "locationSlug" => "breskens",
                "rwsCode" => "breskens.veerhaven"
            };
        }
        if (id == 3) {
            return {
                "name" => "Oesterdam",
                "lat" => 51.479747,
                "lon" => 4.191958,
                "locationSlug" => "marollegat",
                "rwsCode" => "marollegat"
            };
        }
        if (id == 4) {
            return {
                "name" => "Oranjeplaat",
                "lat" => 51.51661,
                "lon" => 3.70014,
                "locationSlug" => "oranjeplaat",
                "rwsCode" => "arnemuiden.oranjeplaat"
            };
        }
        if (id == 5) {
            return {
                "name" => "Ossenisse",
                "lat" => 51.390833,
                "lon" => 3.9925,
                "locationSlug" => "ossenisse",
                "rwsCode" => "ossenisse"
            };
        }
        if (id == 6) {
            return {
                "name" => "Terneuzen",
                "lat" => 51.336,
                "lon" => 3.827,
                "locationSlug" => "terneuzen",
                "rwsCode" => "terneuzen"
            };
        }
        return {
            "name" => "Vlissingen",
            "lat" => 51.4425,
            "lon" => 3.5964,
            "locationSlug" => "vlissingen",
            "rwsCode" => "vlissingen"
        };
    }

    // Resource id for the descriptive setting label (e.g. "Westerschelde
    // (Vlissingen)"), used by both the phone-side settings.xml and the
    // on-watch picker.
    function settingsLabelRes(id as Lang.Number) as Lang.ResourceId {
        if (id == 1) { return Rez.Strings.locKats; }
        if (id == 2) { return Rez.Strings.locBreskens; }
        if (id == 3) { return Rez.Strings.locMarollegat; }
        if (id == 4) { return Rez.Strings.locOranjeplaat; }
        if (id == 5) { return Rez.Strings.locOssenisse; }
        if (id == 6) { return Rez.Strings.locTerneuzen; }
        return Rez.Strings.locVlissingen;
    }

    function getSelected() as Lang.Dictionary {
        var id = Application.Properties.getValue("locationId");
        if (id == null || !(id instanceof Lang.Number)) {
            id = 0;
        }
        return get(id as Lang.Number);
    }

}
