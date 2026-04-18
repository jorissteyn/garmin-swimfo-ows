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
        ensureTemporalEvent();
        var view = new SwimfoWidgetView();
        return [view, new SwimfoWidgetDelegate(view)];
    }

    (:glance)
    function getGlanceView() as [WatchUi.GlanceView] or [WatchUi.GlanceView, WatchUi.GlanceViewDelegate] or Null {
        ensureTemporalEvent();
        return [new SwimfoGlanceView()];
    }

    // Seed the 30-min background fetch if nothing is scheduled yet. Called from
    // both widget and glance entry points so having the glance in the carousel
    // is enough to bootstrap the refresh loop — the user doesn't need to open
    // the widget first. Re-registering on every call would reset the timer and
    // starve the fetch, so we skip when an event is already pending.
    hidden function ensureTemporalEvent() as Void {
        if (Background.getTemporalEventRegisteredTime() != null) {
            return;
        }
        var data = Storage.getValue("swimfoData");
        var delay = (data == null) ? 5 : 1800;
        Background.registerForTemporalEvent(
            Time.now().add(new Time.Duration(delay)));
    }

}
