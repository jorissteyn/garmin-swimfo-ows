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
    hidden var _dayStarts as Lang.Array = [] as Lang.Array;

    function initialize() {
        View.initialize();
    }

    function scroll(delta as Lang.Number) as Void {
        if (_dayStarts.size() == 0) {
            return;
        }
        var currentDay = 0;
        for (var i = 0; i < _dayStarts.size(); i++) {
            if ((_dayStarts[i] as Lang.Number) <= _scroll) {
                currentDay = i;
            } else {
                break;
            }
        }
        var targetDay = currentDay + delta;
        if (targetDay < 0) { targetDay = 0; }
        if (targetDay >= _dayStarts.size()) { targetDay = _dayStarts.size() - 1; }
        _scroll = _dayStarts[targetDay] as Lang.Number;
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

        var picked = Procestype.pickTable(data);
        var table = picked[0];
        var pickedLabel = picked[1] as Lang.String?;
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

        var rows = buildRows(entries);
        _totalRows = rows.size();
        if (_scroll > _totalRows - 1 && _totalRows > 0) {
            _scroll = _totalRows - 1;
        }

        // ProcesType header above the table. Hidden when the user has scrolled
        // past the top so the up-arrow indicator can take its slot.
        var headerY = 4;
        var headerH = dc.getFontHeight(Graphics.FONT_XTINY);
        if (pickedLabel != null && _scroll == 0) {
            dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, headerY, Graphics.FONT_XTINY, pickedLabel as Lang.String,
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        var rowHeight = dc.getFontHeight(Graphics.FONT_TINY) + 4;
        var topPadding = headerH + 8;
        _rowsVisible = ((h - topPadding - 10) / rowHeight);
        if (_rowsVisible < 1) { _rowsVisible = 1; }

        var nowEpoch = Time.now().value();
        var startY = topPadding;

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

            // Small HW/LW label (inherits arrow color)
            dc.drawText(arrowX + arrowS + 3, arrowCy, Graphics.FONT_XTINY, typeStr,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            // Level
            dc.setColor(isPast ? dim : fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w * 2 / 5, y, Graphics.FONT_TINY, levelStr,
                Graphics.TEXT_JUSTIFY_CENTER);

            // Time
            dc.drawText(w * 3 / 4, y, Graphics.FONT_TINY, timeStr,
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

    // Build rows: date header (with optional lunar label appended), then HW/LW
    // entries. SPR/DTJ entries are folded into the date header text.
    // Also populates _dayStarts with row indexes of each date header.
    hidden function buildRows(entries as Lang.Array) as Lang.Array {
        var rows = [] as Lang.Array;
        var dayStarts = [] as Lang.Array;
        var lastDate = "";

        var lunarByDate = {} as Lang.Dictionary;
        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i];
            if (entry == null || !(entry instanceof Lang.Dictionary)) { continue; }
            var e = entry as Lang.Dictionary;
            var tv = e["type"];
            if (tv == null || !(tv instanceof Lang.String)) { continue; }
            var t = tv as Lang.String;
            if (!t.equals("SPR") && !t.equals("DTJ")) { continue; }
            var ev = e["epoch"];
            if (!(ev instanceof Lang.Number)) { continue; }
            lunarByDate[formatDate(ev as Lang.Number)] =
                t.equals("SPR") ? "springtij" : "doodtij";
        }

        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i];
            if (entry == null || !(entry instanceof Lang.Dictionary)) { continue; }
            var e = entry as Lang.Dictionary;
            var tv = e["type"];
            var t = (tv != null && tv instanceof Lang.String) ? (tv as Lang.String) : "";
            var isLunar = t.equals("SPR") || t.equals("DTJ");

            var ev = e["epoch"];
            var dateStr = (ev instanceof Lang.Number)
                ? formatDate(ev as Lang.Number) : "";

            if (!dateStr.equals(lastDate) && !dateStr.equals("")) {
                var headerText = dateStr;
                var lunar = lunarByDate[dateStr];
                if (lunar != null && lunar instanceof Lang.String) {
                    headerText = headerText + "  " + (lunar as Lang.String);
                }
                dayStarts.add(rows.size());
                rows.add({ "header" => headerText } as Lang.Dictionary);
                lastDate = dateStr;
            }
            if (!isLunar) {
                rows.add({ "entry" => e } as Lang.Dictionary);
            }
        }
        _dayStarts = dayStarts;
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
