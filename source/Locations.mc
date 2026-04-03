using Toybox.Application;
using Toybox.Lang;

(:background)
module Locations {

    // RWS location codes for ddapi20-waterwebservices.rijkswaterstaat.nl
    // Same codes as used in seaswim PHP app.

    function get(id as Lang.Number) as Lang.Dictionary {
        if (id == 1) {
            return {
                "name" => "Kattendijke",
                "lat" => 51.4933,
                "lon" => 3.9600,
                "rwsCode" => "yerseke"
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
