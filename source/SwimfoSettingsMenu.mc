using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.WatchUi;

// On-watch settings menu: mirrors the phone-side properties so users can
// change Locatie + Procestype RWS without opening Connect IQ on their phone.
// Selections write to Application.Properties; the open views read those
// properties on the next redraw, so the change is visible immediately.

module SwimfoSettings {

    function open() as Void {
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource(Rez.Strings.AppName) as Lang.String,
        });
        var locTitle = WatchUi.loadResource(Rez.Strings.settingLocation) as Lang.String;
        var procTitle = WatchUi.loadResource(Rez.Strings.settingProcesType) as Lang.String;
        var swimTitle = WatchUi.loadResource(Rez.Strings.settingShowSwimDirection) as Lang.String;
        var locItem = new WatchUi.MenuItem(locTitle, currentLocationLabel(), :locItem, null);
        var procItem = new WatchUi.MenuItem(procTitle, currentProcesTypeLabel(), :procItem, null);
        var swimItem = new WatchUi.MenuItem(swimTitle, currentSwimDirectionLabel(), :swimItem, null);
        menu.addItem(locItem);
        menu.addItem(procItem);
        menu.addItem(swimItem);
        WatchUi.pushView(menu, new RootDelegate(locItem, procItem, swimItem), WatchUi.SLIDE_LEFT);
    }

    function currentLocationLabel() as Lang.String {
        var raw = Application.Properties.getValue("locationId");
        var id = (raw instanceof Lang.Number) ? (raw as Lang.Number) : 0;
        return WatchUi.loadResource(Locations.settingsLabelRes(id)) as Lang.String;
    }

    function currentProcesTypeLabel() as Lang.String {
        var id = Procestype.getSelectedId();
        if (id == 1) { return WatchUi.loadResource(Rez.Strings.procesTypeVerwachting) as Lang.String; }
        return WatchUi.loadResource(Rez.Strings.procesTypeAstronomisch) as Lang.String;
    }

    function currentSwimDirectionLabel() as Lang.String {
        var on = (Application.Properties.getValue("showSwimDirection") == true);
        var res = on ? Rez.Strings.swimDirToggleOn : Rez.Strings.swimDirToggleOff;
        return WatchUi.loadResource(res) as Lang.String;
    }
}

class SwimfoSettingsRootDelegateBase extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }
}

// Root settings menu delegate. Holds references to the two MenuItems so the
// picker delegates can refresh their subLabels on the way back — without that,
// the root list would still show the previous value after a selection.
class RootDelegate extends SwimfoSettingsRootDelegateBase {

    hidden var _locItem as WatchUi.MenuItem;
    hidden var _procItem as WatchUi.MenuItem;
    hidden var _swimItem as WatchUi.MenuItem;

    function initialize(locItem as WatchUi.MenuItem, procItem as WatchUi.MenuItem,
            swimItem as WatchUi.MenuItem) {
        SwimfoSettingsRootDelegateBase.initialize();
        _locItem = locItem;
        _procItem = procItem;
        _swimItem = swimItem;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :locItem) {
            openLocationPicker();
        } else if (id == :procItem) {
            openProcesTypePicker();
        } else if (id == :swimItem) {
            toggleSwimDirection();
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    hidden function toggleSwimDirection() as Void {
        var on = (Application.Properties.getValue("showSwimDirection") == true);
        Application.Properties.setValue("showSwimDirection", !on);
        var res = (!on) ? Rez.Strings.swimDirToggleOn : Rez.Strings.swimDirToggleOff;
        _swimItem.setSubLabel(WatchUi.loadResource(res) as Lang.String);
        WatchUi.requestUpdate();
    }

    hidden function openLocationPicker() as Void {
        var raw = Application.Properties.getValue("locationId");
        var current = (raw instanceof Lang.Number) ? (raw as Lang.Number) : 0;
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource(Rez.Strings.settingLocation) as Lang.String,
        });
        for (var i = 0; i < Locations.count(); i++) {
            var label = WatchUi.loadResource(Locations.settingsLabelRes(i)) as Lang.String;
            var sub = (i == current) ? "Huidig" : "";
            menu.addItem(new WatchUi.MenuItem(label, sub, i, null));
        }
        menu.setFocus(current);
        WatchUi.pushView(menu, new LocationPickerDelegate(_locItem), WatchUi.SLIDE_LEFT);
    }

    hidden function openProcesTypePicker() as Void {
        var current = Procestype.getSelectedId();
        var menu = new WatchUi.Menu2({
            :title => WatchUi.loadResource(Rez.Strings.settingProcesType) as Lang.String,
        });
        var astroLabel = WatchUi.loadResource(Rez.Strings.procesTypeAstronomisch) as Lang.String;
        var verwLabel = WatchUi.loadResource(Rez.Strings.procesTypeVerwachting) as Lang.String;
        menu.addItem(new WatchUi.MenuItem(astroLabel, (current == 0) ? "Huidig" : "", 0, null));
        menu.addItem(new WatchUi.MenuItem(verwLabel, (current == 1) ? "Huidig" : "", 1, null));
        menu.setFocus(current);
        WatchUi.pushView(menu, new ProcesTypePickerDelegate(_procItem), WatchUi.SLIDE_LEFT);
    }
}

class LocationPickerDelegate extends SwimfoSettingsRootDelegateBase {

    hidden var _rootItem as WatchUi.MenuItem;

    function initialize(rootItem as WatchUi.MenuItem) {
        SwimfoSettingsRootDelegateBase.initialize();
        _rootItem = rootItem;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof Lang.Number) {
            var n = id as Lang.Number;
            Application.Properties.setValue("locationId", n);
            _rootItem.setSubLabel(WatchUi.loadResource(Locations.settingsLabelRes(n)) as Lang.String);

            // Replace Storage with a stub for the new location so the widget
            // doesn't keep showing the previous location's numbers while we
            // wait for the foreground GET to come back. The widget renders
            // this stub as a "Bluetooth sync vereist" banner on data pages.
            var newLoc = Locations.get(n);
            Storage.setValue("swimfoData", {
                "locName" => newLoc["name"],
                "syncRequired" => true,
            });

            // Foreground refresh — no 5-min CIQ floor, so the new location's
            // data lands as fast as BT + the proxy can serve it.
            var app = Application.getApp() as SwimfoApp;
            app.startForegroundRefresh();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            WatchUi.requestUpdate();
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class ProcesTypePickerDelegate extends SwimfoSettingsRootDelegateBase {

    hidden var _rootItem as WatchUi.MenuItem;

    function initialize(rootItem as WatchUi.MenuItem) {
        SwimfoSettingsRootDelegateBase.initialize();
        _rootItem = rootItem;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof Lang.Number) {
            var n = id as Lang.Number;
            Application.Properties.setValue("procesTypeId", n);
            var labelRes = (n == 1) ? Rez.Strings.procesTypeVerwachting : Rez.Strings.procesTypeAstronomisch;
            _rootItem.setSubLabel(WatchUi.loadResource(labelRes) as Lang.String);
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            WatchUi.requestUpdate();
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
