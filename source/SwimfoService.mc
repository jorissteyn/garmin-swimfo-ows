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

    hidden var SERVER_BASE as Lang.String = "http://localhost:31415";

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var loc = Locations.getSelected();
        var url = SERVER_BASE + "/conditions/" + loc["rwsCode"];
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
                        "waterLevel", "tideRising",
                        "prevTideLevel", "prevTideEpoch", "prevTideType",
                        "nextTideLevel", "nextTideEpoch", "nextTideTime",
                        "nextTideType", "tideTable",
                        "moonLabel"] as Lang.Array<Lang.String>;
            for (var i = 0; i < keys.size(); i++) {
                var v = d[keys[i]];
                if (v != null) {
                    result[keys[i]] = v;
                }
            }
        } else {
            // On error, preserve location name so the view shows something
            result["locName"] = Locations.getSelected()["name"];
        }

        result["lastUpdate"] = Time.now().value();
        System.println("result=" + result.keys());
        Background.exit(result);
    }

}
