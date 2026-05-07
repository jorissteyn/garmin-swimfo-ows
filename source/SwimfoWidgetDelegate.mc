using Toybox.Application;
using Toybox.Lang;
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
            // Foreground refresh — bypasses CIQ's 5-min background-event
            // floor so the user sees fresh data within seconds instead of
            // up to 5 minutes from now.
            var app = Application.getApp() as SwimfoApp;
            app.startForegroundRefresh();
            _view.setSyncRequested();
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
