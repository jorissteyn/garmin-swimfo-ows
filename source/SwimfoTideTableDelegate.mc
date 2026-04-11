using Toybox.Lang;
using Toybox.WatchUi;

class SwimfoTideTableDelegate extends WatchUi.BehaviorDelegate {

    hidden var _view as SwimfoTideTableView;

    function initialize(view as SwimfoTideTableView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Lang.Boolean {
        _view.scroll(1);
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Lang.Boolean {
        _view.scroll(-1);
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Lang.Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

}
