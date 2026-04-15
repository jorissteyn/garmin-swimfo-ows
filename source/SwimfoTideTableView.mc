using Toybox.Application.Storage;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

class SwimfoTideTableView extends WatchUi.View {

    hidden var _scroll as Lang.Number = 0;
    hidden var _totalRows as Lang.Number = 0;
    hidden var _rowsVisible as Lang.Number = 5;

    function initialize() {
        View.initialize();
    }

    function scroll(delta as Lang.Number) as Void {
        _scroll = _scroll + delta;
        if (_scroll < 0) { _scroll = 0; }
        var max = _totalRows - _rowsVisible;
        if (max < 0) { max = 0; }
        if (_scroll > max) { _scroll = max; }
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
            dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL, "Geen data",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var table = data["tideTable"];
        if (table == null || !(table instanceof Lang.Array)) {
            dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL, "Geen getijdata",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var entries = table as Lang.Array;
        if (entries.size() == 0) {
            dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL, "Geen getijdata",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Build flat row list: date headers + tide entries
        // Each row: { "header": dateStr } or { "entry": entryDict }
        var rows = buildRows(entries);
        _totalRows = rows.size();

        var rowHeight = dc.getFontHeight(Graphics.FONT_TINY) + 4;
        _rowsVisible = ((h - 20) / rowHeight);
        if (_rowsVisible < 1) { _rowsVisible = 1; }

        var nowEpoch = Time.now().value();
        var startY = 10;

        for (var i = 0; i < _rowsVisible && (i + _scroll) < rows.size(); i++) {
            var idx = i + _scroll;
            var row = rows[idx] as Lang.Dictionary;
            var y = startY + i * rowHeight;

            var headerVal = row["header"];
            if (headerVal != null && headerVal instanceof Lang.String) {
                // Date header row
                dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
                dc.drawText(w / 8, y, Graphics.FONT_XTINY, headerVal as Lang.String,
                    Graphics.TEXT_JUSTIFY_LEFT);
                continue;
            }

            var entry = row["entry"];
            if (entry == null || !(entry instanceof Lang.Dictionary)) {
                continue;
            }
            var e = entry as Lang.Dictionary;

            var eType = e["type"];
            var eLevel = e["level"];
            var eEpoch = e["epoch"];

            var typeStr = "  ";
            if (eType != null && eType instanceof Lang.String) {
                typeStr = eType as Lang.String;
            }

            var levelStr = "--";
            if (eLevel instanceof Lang.Float) {
                levelStr = (eLevel as Lang.Float).format("%.2f") + "m";
            } else if (eLevel instanceof Lang.Number) {
                levelStr = (eLevel as Lang.Number).toFloat().format("%.2f") + "m";
            }

            var timeStr = "--:--";
            if (eEpoch instanceof Lang.Number) {
                timeStr = formatTime(eEpoch as Lang.Number);
            }

            var isPast = false;
            if (eEpoch instanceof Lang.Number && (eEpoch as Lang.Number) < nowEpoch) {
                isPast = true;
            }

            var isHW = typeStr.equals("HW");
            var fontH = dc.getFontHeight(Graphics.FONT_TINY);
            var arrowCy = y + fontH / 2;
            var arrowX = w / 10;
            var arrowS = 5;

            // Draw triangle arrow
            if (isPast) {
                dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
            } else if (isHW) {
                dc.setColor(0x00AA00, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(0xDD4400, Graphics.COLOR_TRANSPARENT);
            }
            if (isHW) {
                dc.fillPolygon([[arrowX, arrowCy - arrowS], [arrowX - arrowS, arrowCy + arrowS], [arrowX + arrowS, arrowCy + arrowS]] as Lang.Array);
            } else {
                dc.fillPolygon([[arrowX, arrowCy + arrowS], [arrowX - arrowS, arrowCy - arrowS], [arrowX + arrowS, arrowCy - arrowS]] as Lang.Array);
            }

            // Type label
            dc.drawText(w / 5, y, Graphics.FONT_TINY, typeStr,
                Graphics.TEXT_JUSTIFY_LEFT);

            // Level
            dc.setColor(isPast ? dim : fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y, Graphics.FONT_TINY, levelStr,
                Graphics.TEXT_JUSTIFY_CENTER);

            // Time
            dc.drawText(w * 5 / 6, y, Graphics.FONT_TINY, timeStr,
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Scroll indicators
        if (_scroll > 0) {
            dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[w / 2, 2], [w / 2 - 6, 9], [w / 2 + 6, 9]] as Lang.Array);
        }
        if (_scroll + _rowsVisible < rows.size()) {
            dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[w / 2, h - 2], [w / 2 - 6, h - 9], [w / 2 + 6, h - 9]] as Lang.Array);
        }
    }

    // Build rows with date headers inserted when date changes
    hidden function buildRows(entries as Lang.Array) as Lang.Array {
        var rows = [] as Lang.Array;
        var lastDate = "";

        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i];
            if (entry == null || !(entry instanceof Lang.Dictionary)) {
                continue;
            }
            var e = entry as Lang.Dictionary;
            var epochVal = e["epoch"];
            var dateStr = "";
            if (epochVal instanceof Lang.Number) {
                dateStr = formatDate(epochVal as Lang.Number);
            }

            if (!dateStr.equals(lastDate) && !dateStr.equals("")) {
                rows.add({ "header" => dateStr } as Lang.Dictionary);
                lastDate = dateStr;
            }
            rows.add({ "entry" => e } as Lang.Dictionary);
        }

        return rows;
    }

    hidden function formatTime(epoch as Lang.Number) as Lang.String {
        var g = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_SHORT);
        return pad2(g.hour) + ":" + pad2(g.min);
    }

    hidden function formatDate(epoch as Lang.Number) as Lang.String {
        var g = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_MEDIUM);
        return g.day_of_week + " " + g.day + " " + g.month;
    }

    hidden function pad2(n as Lang.Number) as Lang.String {
        if (n < 10) { return "0" + n; }
        return n.toString();
    }

}
