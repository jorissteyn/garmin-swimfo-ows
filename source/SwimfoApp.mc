using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Background;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

(:background)
class SwimfoApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Lang.Dictionary?) as Void {
    }

    (:background_method)
    function getServiceDelegate() as Lang.Array {
        return [new SwimfoService()];
    }

    function onBackgroundData(data as Application.PersistableType) as Void {
        System.println("onBackgroundData received");
        if (data instanceof Lang.Dictionary) {
            Storage.setValue("swimfoData", data as Lang.Dictionary);
            System.println("Data stored OK");
        } else {
            System.println("Background returned non-dict: " + data);
        }
        WatchUi.requestUpdate();
        Background.registerForTemporalEvent(Time.now().add(new Time.Duration(1800)));
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var data = Storage.getValue("swimfoData");
        if (data == null) {
            Background.registerForTemporalEvent(Time.now().add(new Time.Duration(5)));
        } else {
            Background.registerForTemporalEvent(Time.now().add(new Time.Duration(1800)));
        }
        var view = new SwimfoWidgetView();
        return [view, new SwimfoWidgetDelegate(view)];
    }

    (:glance)
    function getGlanceView() as [WatchUi.GlanceView] or [WatchUi.GlanceView, WatchUi.GlanceViewDelegate] or Null {
        return [new SwimfoGlanceView()];
    }

}
