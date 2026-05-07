using Toybox.Application;
using Toybox.Lang;

(:background)
module Locations {

    // RWS location codes for ddapi20-waterwebservices.rijkswaterstaat.nl
    // Same codes as used in seaswim PHP app.

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
                "rwsCode" => "kats"
            };
        }
        if (id == 2) {
            return {
                "name" => "Breskens",
                "lat" => 51.403661,
                "lon" => 3.550427,
                "rwsCode" => "breskens"
            };
        }
        if (id == 3) {
            return {
                "name" => "Oesterdam",
                "lat" => 51.479747,
                "lon" => 4.191958,
                "rwsCode" => "marollegat"
            };
        }
        if (id == 4) {
            return {
                "name" => "Oranjeplaat",
                "lat" => 51.51661,
                "lon" => 3.70014,
                "rwsCode" => "oranjeplaat"
            };
        }
        if (id == 5) {
            return {
                "name" => "Ossenisse",
                "lat" => 51.390833,
                "lon" => 3.9925,
                "rwsCode" => "ossenisse"
            };
        }
        if (id == 6) {
            return {
                "name" => "Terneuzen",
                "lat" => 51.336,
                "lon" => 3.827,
                "rwsCode" => "terneuzen"
            };
        }
        return {
            "name" => "Vlissingen",
            "lat" => 51.4425,
            "lon" => 3.5964,
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
