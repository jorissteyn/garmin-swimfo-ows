using Toybox.Background;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;

// Fetches pre-aggregated conditions from the Swimfo proxy server.
// The server handles all upstream API calls (Open-Meteo, RWS) and caching.
// Response is a small flat JSON dict — well within default maxLength.

(:background)
class SwimfoService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    (:dev)
    hidden function serverBase() as Lang.String {
        return "http://localhost:31415";
    }

    (:prod)
    hidden function serverBase() as Lang.String {
        return "https://ows.j0r1s.nl";
    }

    function onTemporalEvent() as Void {
        // Pre-register the next sync BEFORE the fetch. Connect IQ kills the
        // background service after a 30s wall clock; if makeWebRequest hangs
        // past that (e.g. BT reconnecting), Background.exit never runs,
        // onBackgroundData never fires, and the re-registration in
        // SwimfoApp.onBackgroundData is skipped — silently breaking the 30-min
        // loop until the user opens the app. Booking the next slot here
        // guarantees the loop survives a killed fetch. On success,
        // SwimfoApp.onBackgroundData overwrites this with a fresh +1800s.
        Background.registerForTemporalEvent(Time.now().add(new Time.Duration(1800)));

        var loc = Locations.getSelected();
        var url = serverBase() + "/conditions/" + loc["locationSlug"];
        System.println("fetch=" + url);

        Communications.makeWebRequest(
            url,
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onData)
        );
    }

    function onData(code as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        System.println("data=" + code);
        var result = {} as Lang.Dictionary;

        if (code == 200 && data instanceof Lang.Dictionary) {
            var d = data as Lang.Dictionary;
            var keys = ["locName", "airTemp", "windSpeed", "waterTemp",
                        "weatherTime", "waterTempTime",
                        "tideTable", "tideTableVerwachting",
                        "moonLabel"] as Lang.Array<Lang.String>;
            for (var i = 0; i < keys.size(); i++) {
                var v = d[keys[i]];
                if (v != null) {
                    result[keys[i]] = v;
                }
            }
            result["lastUpdate"] = Time.now().value();
        } else {
            // On error, preserve location name so the view shows something
            result["locName"] = Locations.getSelected()["name"];
            result["lastError"] = code;
        }
        System.println("result=" + result.keys());
        Background.exit(result);
    }

}
