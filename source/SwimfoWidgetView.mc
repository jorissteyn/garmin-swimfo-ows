using Toybox.Application.Storage;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

class SwimfoWidgetView extends WatchUi.View {

    hidden const PAGE_COUNT = 4;
    hidden var _page as Lang.Number = 0;
    hidden var _syncRequestedAt as Lang.Number = 0;

    function initialize() {
        View.initialize();
    }

    function changePage(delta as Lang.Number) as Void {
        _page = (_page + delta + PAGE_COUNT) % PAGE_COUNT;
    }

    function getPage() as Lang.Number {
        return _page;
    }

    function setSyncRequested() as Void {
        _syncRequestedAt = Time.now().value();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var bg = Graphics.COLOR_BLACK;
        var fg = Graphics.COLOR_WHITE;
        var dim = Graphics.COLOR_LT_GRAY;

        dc.setColor(fg, bg);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var data = Storage.getValue("swimfoData") as Lang.Dictionary?;

        if (data == null) {
            dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL,
                "Laden...", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            drawDots(dc, w, h, dim, fg);
            return;
        }

        // Location name at top
        var locName = "---";
        var locVal = data["locName"];
        if (locVal != null && locVal instanceof Lang.String) {
            locName = (locVal as Lang.String).toUpper();
        }
        dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 8, Graphics.FONT_XTINY, locName,
            Graphics.TEXT_JUSTIFY_CENTER);

        if (_page == 0) {
            drawTidePage(dc, w, h, data, fg, dim);
        } else if (_page == 1) {
            drawWaterPage(dc, w, h, data, fg, dim);
        } else if (_page == 2) {
            drawWeatherPage(dc, w, h, data, fg, dim);
        } else {
            drawSyncPage(dc, w, h, data, fg, dim);
        }

        drawDots(dc, w, h, dim, fg);
    }

    // ---- Page 0: Tide ----

    hidden function drawTidePage(dc as Graphics.Dc, w as Lang.Number, h as Lang.Number,
            data as Lang.Dictionary, fg as Lang.Number, dim as Lang.Number) as Void {
        var cy = h * 4 / 10;

        // Interpolate current water level from prev/next extrema
        var interpResult = interpolateTide(data);
        var level = interpResult[0] as Lang.String;
        var isRising = interpResult[1] as Lang.Boolean;
        var hasDirection = interpResult[2] as Lang.Boolean;

        // Tide arrow icon
        var arrowX = w / 2;
        var arrowY = cy - 12;
        dc.setColor(isRising ? 0x00AA00 : 0xDD4400, Graphics.COLOR_TRANSPARENT);
        if (hasDirection) {
            drawTideArrow(dc, arrowX, arrowY, isRising);
        }

        // Water level
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        var label = "---";
        if (hasDirection) {
            label = isRising ? "Opkomend" : "Afgaand";
        }
        dc.drawText(w / 2, cy + 8, Graphics.FONT_MEDIUM,
            level + "m", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, cy + 8 + dc.getFontHeight(Graphics.FONT_MEDIUM), Graphics.FONT_XTINY,
            label, Graphics.TEXT_JUSTIFY_CENTER);

        // Next tide
        var nextLevel = fmtFloat(data, "nextTideLevel", "%.2f");
        var nextTime = strVal(data, "nextTideTime");
        var nextType = strVal(data, "nextTideType");
        if (nextTime != null && nextType != null) {
            var nextY = h * 7 / 10;
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            var nextStr = nextType + " " + nextLevel + "m " + nextTime;
            dc.drawText(w / 2, nextY, Graphics.FONT_TINY, nextStr,
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Spring/neap tide indicator
        var moonLabelVal = strVal(data, "moonLabel");
        if (moonLabelVal != null) {
            dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
            var moonY = h * 7 / 10 + dc.getFontHeight(Graphics.FONT_TINY) + 2;
            dc.drawText(w / 2, moonY, Graphics.FONT_XTINY, moonLabelVal,
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Cosine interpolation between previous and next tide extrema.
    // Returns [levelString, isRising, hasDirection].
    hidden function interpolateTide(data as Lang.Dictionary) as Lang.Array {
        var prevEpoch = numVal(data, "prevTideEpoch");
        var nextEpoch = numVal(data, "nextTideEpoch");
        var prevLevel = floatVal(data, "prevTideLevel");
        var nextLevel = floatVal(data, "nextTideLevel");

        if (prevEpoch != null && nextEpoch != null && prevLevel != null && nextLevel != null) {
            var now = Time.now().value();
            var span = nextEpoch - prevEpoch;
            if (span > 0) {
                var t = (now - prevEpoch).toFloat() / span.toFloat();
                if (t < 0.0) { t = 0.0; }
                if (t > 1.0) { t = 1.0; }
                // Cosine interpolation: smooth sinusoidal curve between extrema
                var cosInterp = (1.0 - Math.cos(t * Math.PI)) / 2.0;
                var level = prevLevel + (nextLevel - prevLevel) * cosInterp;
                var rising = (nextLevel > prevLevel);
                return [level.format("%.2f"), rising, true] as Lang.Array;
            }
        }

        // Fallback to server-computed value
        var rising = data["tideRising"];
        var hasDir = (rising != null);
        var isRising = (hasDir && (rising as Lang.Boolean));
        return [fmtFloat(data, "waterLevel", "%.2f"), isRising, hasDir] as Lang.Array;
    }

    hidden function drawTideArrow(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number,
            up as Lang.Boolean) as Void {
        var s = 14;
        if (up) {
            dc.fillPolygon([[x, y - s], [x - s, y + s / 2], [x + s, y + s / 2]] as Lang.Array);
        } else {
            dc.fillPolygon([[x, y + s], [x - s, y - s / 2], [x + s, y - s / 2]] as Lang.Array);
        }
    }

    // ---- Page 1: Water temperature ----

    hidden function drawWaterPage(dc as Graphics.Dc, w as Lang.Number, h as Lang.Number,
            data as Lang.Dictionary, fg as Lang.Number, dim as Lang.Number) as Void {
        var cy = h / 2 - 10;

        // Thermometer icon
        dc.setColor(0x4488FF, Graphics.COLOR_TRANSPARENT);
        drawThermometer(dc, w / 2, cy - 30, 20);

        // Temperature value
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        var temp = fmtFloat(data, "waterTemp", "%.1f");
        dc.drawText(w / 2, cy + 8, Graphics.FONT_LARGE,
            temp + "\u00B0C", Graphics.TEXT_JUSTIFY_CENTER);

        // Label
        dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, cy + 8 + dc.getFontHeight(Graphics.FONT_LARGE), Graphics.FONT_XTINY,
            "Water", Graphics.TEXT_JUSTIFY_CENTER);

        // Wave decoration
        dc.setColor(0x4488FF, Graphics.COLOR_TRANSPARENT);
        drawWave(dc, w / 2, h * 3 / 4, w / 2);
    }

    hidden function drawThermometer(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number,
            size as Lang.Number) as Void {
        var bw = size / 4;
        var bh = size;
        dc.fillRoundedRectangle(x - bw, y - bh / 2, bw * 2, bh, bw);
        dc.fillCircle(x, y + bh / 2, bw + 2);
    }

    hidden function drawWave(dc as Graphics.Dc, cx as Lang.Number, y as Lang.Number,
            width as Lang.Number) as Void {
        var hw = width / 2;
        var amp = 4;
        var prev = y;
        for (var i = -hw; i < hw; i += 2) {
            var ny = y + (amp * Math.sin(i.toFloat() * 0.15)).toNumber();
            dc.drawLine(cx + i, prev, cx + i + 2, ny);
            prev = ny;
        }
    }

    // ---- Page 2: Weather ----

    hidden function drawWeatherPage(dc as Graphics.Dc, w as Lang.Number, h as Lang.Number,
            data as Lang.Dictionary, fg as Lang.Number, dim as Lang.Number) as Void {
        var row1 = h * 35 / 100;
        var row2 = h * 55 / 100;

        // Air temperature
        dc.setColor(0xFF8800, Graphics.COLOR_TRANSPARENT);
        drawThermometer(dc, w / 3 - 10, row1 + 4, 16);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        var airT = fmtFloat(data, "airTemp", "%.1f");
        dc.drawText(w / 2 + 10, row1 - 8, Graphics.FONT_MEDIUM,
            airT + "\u00B0C", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2 + 10, row1 + dc.getFontHeight(Graphics.FONT_MEDIUM) - 8, Graphics.FONT_XTINY,
            "Air", Graphics.TEXT_JUSTIFY_CENTER);

        // Wind speed + Beaufort
        dc.setColor(0x88BBDD, Graphics.COLOR_TRANSPARENT);
        drawWindIcon(dc, w / 3 - 10, row2 + 4, 14);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        var wind = fmtFloat(data, "windSpeed", "%.0f");
        var bft = toBeaufort(data);
        dc.drawText(w / 2 + 10, row2 - 8, Graphics.FONT_MEDIUM,
            wind + " km/h", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2 + 10, row2 + dc.getFontHeight(Graphics.FONT_MEDIUM) - 8, Graphics.FONT_XTINY,
            "Wind  Bft " + bft, Graphics.TEXT_JUSTIFY_CENTER);
    }

    hidden function drawWindIcon(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number,
            size as Lang.Number) as Void {
        var s = size / 2;
        dc.setPenWidth(2);
        dc.drawLine(x - s, y - 2, x + s, y - 2);
        dc.drawLine(x - s + 3, y + 4, x + s - 2, y + 4);
        dc.drawLine(x + s, y - 2, x + s - 3, y - 5);
        dc.drawLine(x + s - 2, y + 4, x + s - 5, y + 1);
        dc.setPenWidth(1);
    }

    // ---- Page 3: Sync ----

    hidden function drawSyncPage(dc as Graphics.Dc, w as Lang.Number, h as Lang.Number,
            data as Lang.Dictionary, fg as Lang.Number, dim as Lang.Number) as Void {
        var cy = h / 2 - 10;

        dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, cy - dc.getFontHeight(Graphics.FONT_TINY), Graphics.FONT_TINY,
            "Laatste sync", Graphics.TEXT_JUSTIFY_CENTER);

        var lastUpdate = data["lastUpdate"];
        if (lastUpdate != null && lastUpdate instanceof Lang.Number) {
            var moment = new Time.Moment(lastUpdate as Lang.Number);
            var g = Gregorian.info(moment, Time.FORMAT_MEDIUM);
            var timeStr = padNum(g.hour) + ":" + padNum(g.min);
            var dateStr = g.day + " " + g.month + " " + g.year;

            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, cy + 4, Graphics.FONT_MEDIUM, timeStr,
                Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, cy + 4 + dc.getFontHeight(Graphics.FONT_MEDIUM), Graphics.FONT_TINY,
                dateStr, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, cy + 4, Graphics.FONT_SMALL, "Nooit",
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Hint / status — show "Sync gepland..." until data arrives
        var syncPending = false;
        if (_syncRequestedAt > 0) {
            var lu = data["lastUpdate"];
            if (lu != null && lu instanceof Lang.Number && (lu as Lang.Number) > _syncRequestedAt) {
                _syncRequestedAt = 0;
            } else {
                syncPending = true;
            }
        }
        dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
        var hint = syncPending ? "Sync gepland..." : "Tik om te verversen";
        dc.drawText(w / 2, h * 3 / 4, Graphics.FONT_XTINY,
            hint, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ---- Page dots ----

    hidden function drawDots(dc as Graphics.Dc, w as Lang.Number, h as Lang.Number,
            dim as Lang.Number, fg as Lang.Number) as Void {
        var dotR = 4;
        var gap = 14;
        var totalW = PAGE_COUNT * gap;
        var startX = (w - totalW) / 2 + gap / 2;
        var y = h - 18;

        for (var i = 0; i < PAGE_COUNT; i++) {
            var x = startX + i * gap;
            if (i == _page) {
                dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, dotR);
            } else {
                dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, 2);
            }
        }
    }

    // ---- Beaufort ----

    hidden function toBeaufort(d as Lang.Dictionary) as Lang.String {
        var v = d["windSpeed"];
        var kmh = 0.0f;
        if (v instanceof Lang.Float) { kmh = v as Lang.Float; }
        else if (v instanceof Lang.Number) { kmh = (v as Lang.Number).toFloat(); }
        else { return "--"; }

        // Beaufort thresholds in km/h
        if (kmh < 1)    { return "0"; }
        if (kmh < 6)    { return "1"; }
        if (kmh < 12)   { return "2"; }
        if (kmh < 20)   { return "3"; }
        if (kmh < 29)   { return "4"; }
        if (kmh < 39)   { return "5"; }
        if (kmh < 50)   { return "6"; }
        if (kmh < 62)   { return "7"; }
        if (kmh < 75)   { return "8"; }
        if (kmh < 89)   { return "9"; }
        if (kmh < 103)  { return "10"; }
        if (kmh < 118)  { return "11"; }
        return "12";
    }

    // ---- Value helpers ----

    hidden function fmtFloat(d as Lang.Dictionary, key as Lang.String, fmt as Lang.String) as Lang.String {
        var v = d[key];
        if (v instanceof Lang.Float) {
            return (v as Lang.Float).format(fmt);
        }
        if (v instanceof Lang.Number) {
            return (v as Lang.Number).toFloat().format(fmt);
        }
        return "--";
    }

    hidden function strVal(d as Lang.Dictionary, key as Lang.String) as Lang.String? {
        var v = d[key];
        if (v != null && v instanceof Lang.String) {
            return v as Lang.String;
        }
        return null;
    }

    hidden function numVal(d as Lang.Dictionary, key as Lang.String) as Lang.Number? {
        var v = d[key];
        if (v instanceof Lang.Number) { return v as Lang.Number; }
        if (v instanceof Lang.Float) { return (v as Lang.Float).toNumber(); }
        return null;
    }

    hidden function floatVal(d as Lang.Dictionary, key as Lang.String) as Lang.Float? {
        var v = d[key];
        if (v instanceof Lang.Float) { return v as Lang.Float; }
        if (v instanceof Lang.Number) { return (v as Lang.Number).toFloat(); }
        return null;
    }

    hidden function padNum(n as Lang.Number) as Lang.String {
        if (n < 10) { return "0" + n; }
        return n.toString();
    }

}
