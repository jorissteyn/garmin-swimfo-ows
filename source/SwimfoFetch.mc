using Toybox.Lang;

// Shared HTTP helpers for both the background ServiceDelegate and the
// foreground refresh path on SwimfoApp. The two callers diverge in how they
// hand the result back (Background.exit vs Storage + requestUpdate); the
// URL building and key-copying logic is identical and lives here.

(:background)
module SwimfoFetch {

    // serverBase() picks dev (localhost) or prod (ows.j0r1s.nl) based on the
    // jungle annotations. Same convention as the (now-removed) helpers in
    // SwimfoService — see monkey.jungle for the dev/prod toggle.

    (:dev)
    function serverBase() as Lang.String {
        return "http://localhost:31415";
    }

    (:prod)
    function serverBase() as Lang.String {
        return "https://ows.j0r1s.nl";
    }

    function urlFor(loc as Lang.Dictionary) as Lang.String {
        return serverBase() + "/conditions/" + loc["locationSlug"];
    }

    // Copies the small set of JSON keys the watch actually renders into a
    // fresh dict, dropping anything else the server sends. Both code paths
    // call this after parsing the response so they end up with the same
    // Storage shape.
    function pickKeys(d as Lang.Dictionary) as Lang.Dictionary {
        var keys = ["locName", "airTemp", "windSpeed", "windDir", "waterTemp",
                    "weatherTime", "waterTempTime",
                    "tideTable", "tideTableVerwachting",
                    "moonLabel"] as Lang.Array<Lang.String>;
        var result = {} as Lang.Dictionary;
        for (var i = 0; i < keys.size(); i++) {
            var v = d[keys[i]];
            if (v != null) {
                result[keys[i]] = v;
            }
        }
        return result;
    }
}
