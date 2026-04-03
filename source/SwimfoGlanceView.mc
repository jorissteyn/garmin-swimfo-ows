using Toybox.Application.Storage;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.WatchUi;

(:glance)
class SwimfoGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var data = Storage.getValue("swimfoData") as Lang.Dictionary?;

        if (data == null) {
            dc.drawText(0, h / 2, Graphics.FONT_GLANCE, "Swimfo",
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Line 1: tide info
        var parts1 = [] as Lang.Array<Lang.String>;
        var rising = data["tideRising"];
        if (rising != null) {
            parts1.add((rising as Lang.Boolean) ? "Opk" : "Afg");
        }
        var level = fmtF(data, "waterLevel", "%.2f");
        if (!level.equals("--")) { parts1.add(level + "m"); }
        var wt = fmtF(data, "waterTemp", "%.0f");
        if (!wt.equals("--")) { parts1.add("w" + wt + "\u00B0"); }

        var line1 = "Swimfo";
        if (parts1.size() > 0) {
            line1 = joinArr(parts1, " ");
        }

        // Line 2: weather
        var parts2 = [] as Lang.Array<Lang.String>;
        var airT = fmtF(data, "airTemp", "%.0f");
        if (!airT.equals("--")) { parts2.add(airT + "\u00B0"); }
        var wind = fmtF(data, "windSpeed", "%.0f");
        if (!wind.equals("--")) { parts2.add(wind + "km/h"); }

        dc.drawText(0, h / 3, Graphics.FONT_GLANCE, line1,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        if (parts2.size() > 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, h * 2 / 3, Graphics.FONT_GLANCE_NUMBER,
                joinArr(parts2, " "),
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    hidden function fmtF(d as Lang.Dictionary, key as Lang.String, fmt as Lang.String) as Lang.String {
        var v = d[key];
        if (v instanceof Lang.Float) { return (v as Lang.Float).format(fmt); }
        if (v instanceof Lang.Number) { return (v as Lang.Number).toFloat().format(fmt); }
        return "--";
    }

    hidden function joinArr(arr as Lang.Array, sep as Lang.String) as Lang.String {
        var r = "";
        for (var i = 0; i < arr.size(); i++) {
            if (i > 0) { r += sep; }
            r += arr[i];
        }
        return r;
    }

}
