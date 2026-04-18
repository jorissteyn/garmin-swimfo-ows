using Toybox.Application;
using Toybox.Lang;

(:background)
module Locations {

    // RWS location codes for ddapi20-waterwebservices.rijkswaterstaat.nl
    // Same codes as used in seaswim PHP app.

    function get(id as Lang.Number) as Lang.Dictionary {
        if (id == 1) {
            return {
                "name" => "Oesterdam",
                "lat" => 51.479747,
                "lon" => 4.191958,
                "rwsCode" => "marollegat"
            };
        }
        if (id == 2) {
            return {
                "name" => "Oranjeplaat",
                "lat" => 51.51661,
                "lon" => 3.70014,
                "rwsCode" => "oranjeplaat"
            };
        }
        if (id == 3) {
            return {
                "name" => "Ossenisse",
                "lat" => 51.390833,
                "lon" => 3.9925,
                "rwsCode" => "ossenisse"
            };
        }
        if (id == 4) {
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

    function getSelected() as Lang.Dictionary {
        var id = Application.Properties.getValue("locationId");
        if (id == null || !(id instanceof Lang.Number)) {
            id = 0;
        }
        return get(id as Lang.Number);
    }

}
