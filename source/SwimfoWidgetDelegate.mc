using Toybox.Background;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

class SwimfoWidgetDelegate extends WatchUi.BehaviorDelegate {

    hidden var _view as SwimfoWidgetView;

    function initialize(view as SwimfoWidgetView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Lang.Boolean {
        _view.changePage(1);
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Lang.Boolean {
        _view.changePage(-1);
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() as Lang.Boolean {
        var page = _view.getPage();
        if (page == 0) {
            // Open tide table
            var tableView = new SwimfoTideTableView();
            WatchUi.pushView(tableView, new SwimfoTideTableDelegate(tableView), WatchUi.SLIDE_LEFT);
            return true;
        }
        if (page == 3) {
            // Try shortest delay first; CIQ enforces >=5 min since last run.
            // If that fails, fall back to the 5-min minimum.
            try {
                Background.registerForTemporalEvent(Time.now().add(new Time.Duration(1)));
                _view.setSyncRequested();
            } catch (e) {
                try {
                    Background.registerForTemporalEvent(Time.now().add(new Time.Duration(300)));
                    _view.setSyncRequested();
                } catch (e2) {
                    System.println("Sync not possible: " + e2.getErrorMessage());
                }
            }
            WatchUi.requestUpdate();
            return true;
        }
        if (page == 4) {
            SwimfoSettings.open();
            return true;
        }
        return false;
    }

    // Hardware menu button shortcut — opens settings from any page so users
    // don't have to swipe to page 4 every time.
    function onMenu() as Lang.Boolean {
        SwimfoSettings.open();
        return true;
    }

}
