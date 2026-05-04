using Toybox.Application;
using Toybox.Lang;

(:glance)
module Procestype {

    // Selected procesType id from settings: 0 = astronomisch, 1 = verwachting.
    function getSelectedId() as Lang.Number {
        var id = Application.Properties.getValue("procesTypeId");
        if (id == null || !(id instanceof Lang.Number)) {
            return 0;
        }
        return id as Lang.Number;
    }

    function labelForId(id as Lang.Number) as Lang.String {
        if (id == 1) { return "verwachting"; }
        return "astronomisch";
    }

    function tableKeyForId(id as Lang.Number) as Lang.String {
        if (id == 1) { return "tideTableVerwachting"; }
        return "tideTable";
    }

    // Returns [tableArray, label] for the table the watch should render.
    // Falls back to the other procesType when the selected one is missing or
    // empty (e.g. RWS verwachting briefly unavailable) so the watch keeps
    // showing tide data; the returned label tracks what is actually shown.
    function pickTable(d as Lang.Dictionary) as Lang.Array {
        var id = getSelectedId();
        var preferred = tableKeyForId(id);
        var t = d[preferred];
        if (t instanceof Lang.Array && (t as Lang.Array).size() > 0) {
            return [t, labelForId(id)] as Lang.Array;
        }
        var altId = (id == 1) ? 0 : 1;
        var altKey = tableKeyForId(altId);
        var altT = d[altKey];
        if (altT instanceof Lang.Array && (altT as Lang.Array).size() > 0) {
            return [altT, labelForId(altId)] as Lang.Array;
        }
        return [null, null] as Lang.Array;
    }

}
