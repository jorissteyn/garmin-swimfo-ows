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
            try {
                Background.registerForTemporalEvent(Time.now().add(new Time.Duration(300)));
                _view.setSyncRequested();
                System.println("Sync scheduled in 5 min");
            } catch (e) {
                System.println("Sync not possible: " + e.getErrorMessage());
            }
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

}
