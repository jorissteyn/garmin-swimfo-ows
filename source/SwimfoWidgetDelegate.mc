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

}
