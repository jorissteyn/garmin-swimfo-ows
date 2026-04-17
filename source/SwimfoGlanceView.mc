using Toybox.Application.Storage;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.Time;
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

        // The system draws the launcher icon on the left; we only render text
        // in the dc (which covers the content area to the right of it).
        var textX = 0;

        var data = Storage.getValue("swimfoData") as Lang.Dictionary?;

        if (data == null) {
            dc.drawText(textX, h / 2, Graphics.FONT_GLANCE, "Zeeland OWS",
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Line 1: tide info (interpolated from live tideTable)
        var parts1 = [] as Lang.Array<Lang.String>;
        var now = Time.now().value();
        var tide = currentTide(data, now);
        var level = tide[0] as Lang.String;
        var risingKnown = tide[1] as Lang.Boolean;
        var isRising = tide[2] as Lang.Boolean;
        if (risingKnown) {
            parts1.add(isRising ? "Opk" : "Afg");
        }
        if (!level.equals("--")) { parts1.add(level + "m"); }
        var wt = fmtF(data, "waterTemp", "%.0f");
        if (!wt.equals("--")) { parts1.add("w" + wt + "\u00B0"); }

        var line1 = "Zeeland OWS";
        if (parts1.size() > 0) {
            line1 = joinArr(parts1, " ");
        }

        // Line 2: weather
        var parts2 = [] as Lang.Array<Lang.String>;
        var airT = fmtF(data, "airTemp", "%.0f");
        if (!airT.equals("--")) { parts2.add(airT + "\u00B0"); }
        var wind = fmtF(data, "windSpeed", "%.0f");
        if (!wind.equals("--")) { parts2.add(wind + "km/h"); }

        var line1X = textX;
        var line1Y = h / 3;
        if (risingKnown) {
            dc.setColor(isRising ? 0x00AA00 : 0xDD4400, Graphics.COLOR_TRANSPARENT);
            drawArrow(dc, textX + 6, line1Y, isRising);
            line1X = textX + 16;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(line1X, line1Y, Graphics.FONT_GLANCE, line1,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        if (parts2.size() > 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(textX, h * 2 / 3, Graphics.FONT_GLANCE_NUMBER,
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

    // Returns [levelStr, risingKnown, isRising]. Picks HW/LW anchors from the
    // live tideTable so we stay accurate when an extremum crosses between syncs.
    // Falls back to server-snapshotted prev/next fields, then raw waterLevel.
    hidden function currentTide(d as Lang.Dictionary, now as Lang.Number) as Lang.Array {
        var anchors = pickAnchors(d, now);
        if (anchors != null) {
            var prevE = anchors[0] as Lang.Number;
            var prevL = anchors[1] as Lang.Float;
            var nextE = anchors[2] as Lang.Number;
            var nextL = anchors[3] as Lang.Float;
            var span = nextE - prevE;
            if (span > 0) {
                var t = (now - prevE).toFloat() / span.toFloat();
                if (t < 0.0) { t = 0.0; }
                if (t > 1.0) { t = 1.0; }
                var v = prevL + (nextL - prevL) * (1.0 - Math.cos(t * Math.PI)) / 2.0;
                return [v.format("%.2f"), true, nextL > prevL] as Lang.Array;
            }
        }
        // Fallback: server snapshot
        var sr = d["tideRising"];
        var hasDir = (sr != null);
        var isRising = (hasDir && (sr as Lang.Boolean));
        return [fmtF(d, "waterLevel", "%.2f"), hasDir, isRising] as Lang.Array;
    }

    hidden function pickAnchors(d as Lang.Dictionary, now as Lang.Number) as Lang.Array? {
        var table = d["tideTable"];
        if (table == null || !(table instanceof Lang.Array)) { return null; }
        var entries = table as Lang.Array;
        var prevE = null;
        var prevL = null;
        var nextE = null;
        var nextL = null;
        for (var i = 0; i < entries.size(); i++) {
            var e = entries[i];
            if (e == null || !(e instanceof Lang.Dictionary)) { continue; }
            var rec = e as Lang.Dictionary;
            var tv = rec["type"];
            if (!(tv instanceof Lang.String)) { continue; }
            var ts = tv as Lang.String;
            if (!ts.equals("HW") && !ts.equals("LW")) { continue; }
            var ep = rec["epoch"];
            if (!(ep instanceof Lang.Number)) { continue; }
            var lv = rec["level"];
            var lvF = 0.0;
            if (lv instanceof Lang.Float) {
                lvF = lv as Lang.Float;
            } else if (lv instanceof Lang.Number) {
                lvF = (lv as Lang.Number).toFloat();
            } else {
                continue;
            }
            var epN = ep as Lang.Number;
            if (epN <= now) {
                prevE = epN;
                prevL = lvF;
            } else {
                nextE = epN;
                nextL = lvF;
                break;
            }
        }
        if (prevE == null || nextE == null) { return null; }
        return [prevE, prevL, nextE, nextL] as Lang.Array;
    }

    hidden function drawArrow(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number,
            up as Lang.Boolean) as Void {
        var s = 5;
        if (up) {
            dc.fillPolygon([[cx, cy - s], [cx - s, cy + s], [cx + s, cy + s]] as Lang.Array);
        } else {
            dc.fillPolygon([[cx, cy + s], [cx - s, cy - s], [cx + s, cy - s]] as Lang.Array);
        }
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
