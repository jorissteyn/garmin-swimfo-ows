using Toybox.Application.Storage;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

class SwimfoWidgetView extends WatchUi.View {

    hidden const PAGE_COUNT = 5;
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

        // Error code banner under location name — sync page only so other
        // pages aren't cluttered by a failure on an otherwise-still-valid
        // cached dataset.
        if (_page == 3) {
            var errVal = data["lastError"];
            if (errVal != null && errVal instanceof Lang.Number) {
                dc.setColor(0xDD4400, Graphics.COLOR_TRANSPARENT);
                dc.drawText(w / 2, h / 8 + dc.getFontHeight(Graphics.FONT_XTINY),
                    Graphics.FONT_XTINY,
                    "Fout: " + (errVal as Lang.Number).toString(),
                    Graphics.TEXT_JUSTIFY_CENTER);
            }
        }

        if (_page == 0) {
            drawTidePage(dc, w, h, data, fg, dim);
        } else if (_page == 1) {
            drawWaterPage(dc, w, h, data, fg, dim);
        } else if (_page == 2) {
            drawWeatherPage(dc, w, h, data, fg, dim);
        } else if (_page == 3) {
            drawSyncPage(dc, w, h, data, fg, dim);
        } else {
            drawSettingsPage(dc, w, h, fg, dim);
        }

        drawDots(dc, w, h, dim, fg);
    }

    // ---- Page 0: Tide ----

    hidden function drawTidePage(dc as Graphics.Dc, w as Lang.Number, h as Lang.Number,
            data as Lang.Dictionary, fg as Lang.Number, dim as Lang.Number) as Void {
        var cy = h * 4 / 10;
        var now = Time.now().value();
        var picked = Procestype.pickTable(data);
        var pickedTable = picked[0] as Lang.Array?;
        var pickedLabel = picked[1] as Lang.String?;
        var hasTideData = (pickedTable != null);
        var anchors = (pickedTable != null) ? pickAnchorsFromTable(pickedTable, now) : null;

        var level = "--";
        var isRising = false;
        var hasDirection = false;
        var nextEpochTime = null;
        var nextLevelStr = "--";
        var nextType = null;

        if (anchors != null) {
            var prevEpoch = anchors[0] as Lang.Number;
            var prevLevel = anchors[1] as Lang.Float;
            var nextEpoch = anchors[2] as Lang.Number;
            var nextLevel = anchors[3] as Lang.Float;
            var span = nextEpoch - prevEpoch;
            if (span > 0) {
                var t = (now - prevEpoch).toFloat() / span.toFloat();
                if (t < 0.0) { t = 0.0; }
                if (t > 1.0) { t = 1.0; }
                var cosInterp = (1.0 - Math.cos(t * Math.PI)) / 2.0;
                var lv = prevLevel + (nextLevel - prevLevel) * cosInterp;
                level = lv.format("%.2f");
                isRising = (nextLevel > prevLevel);
                hasDirection = true;
            }
            nextEpochTime = nextEpoch;
            nextLevelStr = nextLevel.format("%.2f");
            nextType = anchors[4] as Lang.String;
        }

        // Non-tidal location (e.g. Veerse Meer): short-circuit with an N/A notice.
        if (!hasTideData && !(data["lastError"] instanceof Lang.Number)) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, cy + 8, Graphics.FONT_MEDIUM, "N/A",
                Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, cy + 8 + dc.getFontHeight(Graphics.FONT_MEDIUM),
                Graphics.FONT_XTINY, "Geen getij", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // ProcesType label above the tide info — reflects which RWS series
        // (astronomisch / verwachting) is actually being shown after fallback.
        if (pickedLabel != null) {
            dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 8 + dc.getFontHeight(Graphics.FONT_XTINY),
                Graphics.FONT_XTINY, pickedLabel as Lang.String,
                Graphics.TEXT_JUSTIFY_CENTER);
        }

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
        if (nextEpochTime != null && nextType != null) {
            var g = Gregorian.info(new Time.Moment(nextEpochTime as Lang.Number), Time.FORMAT_SHORT);
            var nextTime = padNum(g.hour) + ":" + padNum(g.min);
            var nextY = h * 7 / 10;
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            var nextStr = (nextType as Lang.String) + " " + nextLevelStr + "m " + nextTime;
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

    // Pick HW/LW extrema bracketing `now` from the live tideTable forecast.
    // Returns [prevEpoch, prevLevel, nextEpoch, nextLevel, nextType] or null.
    // The server sends the forecast once per sync; the watch reselects anchors
    // on every redraw so the shown direction flips exactly when an extremum
    // passes, not 30 minutes later.
    hidden function pickAnchorsFromTable(table as Lang.Array, now as Lang.Number) as Lang.Array? {
        var entries = table as Lang.Array;
        var prevE = null;
        var prevL = null;
        var nextE = null;
        var nextL = null;
        var nextT = null;
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
                nextT = ts;
                break;
            }
        }
        if (prevE == null || nextE == null) { return null; }
        return [prevE, prevL, nextE, nextL, nextT] as Lang.Array;
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

    // ---- Page 4: Settings ----

    hidden function drawSettingsPage(dc as Graphics.Dc, w as Lang.Number, h as Lang.Number,
            fg as Lang.Number, dim as Lang.Number) as Void {
        // Center the "..." in the gap between the location header (drawn at
        // h/8 by onUpdate) and the "Instellingen" label below.
        var locBottom = h / 8 + dc.getFontHeight(Graphics.FONT_XTINY);
        var instTop = h * 6 / 10;
        var dotsY = (locBottom + instTop) / 2;

        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, dotsY, Graphics.FONT_NUMBER_MEDIUM, "...",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, instTop, Graphics.FONT_TINY, "Instellingen",
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 3 / 4, Graphics.FONT_XTINY, "Tik om te openen",
            Graphics.TEXT_JUSTIFY_CENTER);
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
