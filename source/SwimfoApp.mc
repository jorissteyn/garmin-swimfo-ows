using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Background;
using Toybox.Communications;
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
        if (!(data instanceof Lang.Dictionary)) {
            System.println("Background returned non-dict: " + data);
            WatchUi.requestUpdate();
            Background.registerForTemporalEvent(Time.now().add(new Time.Duration(1800)));
            return;
        }
        var d = data as Lang.Dictionary;
        var nowSec = Time.now().value();
        // On failure the service returns {locName, lastError}. Merge the error
        // into existing Storage so the watch keeps rendering the last
        // successful sync — only the error banner and unchanged lastUpdate
        // reflect the failure. A successful sync does a full replace, which
        // naturally clears any stale lastError.  lastAttempt is stamped on
        // both paths so the sync-page "Verversen..." indicator clears on a
        // failed retry too (lastUpdate-only would leave it stuck).
        if (d["lastError"] != null) {
            var existing = Storage.getValue("swimfoData");
            if (existing instanceof Lang.Dictionary) {
                var merged = existing as Lang.Dictionary;
                merged["lastError"] = d["lastError"];
                merged["lastAttempt"] = nowSec;
                Storage.setValue("swimfoData", merged);
                System.println("Error merged, prior data preserved");
            } else {
                d["lastAttempt"] = nowSec;
                Storage.setValue("swimfoData", d);
                System.println("Error stored (no prior data)");
            }
        } else {
            d["lastAttempt"] = nowSec;
            Storage.setValue("swimfoData", d);
            System.println("Data stored OK");
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

    // ── Foreground refresh ──────────────────────────────────────
    //
    // Connect IQ enforces a 5-minute floor between background temporal events,
    // so a freshly-tapped "sync now" or settings change can otherwise wait
    // ages before the new data lands. Foreground makeWebRequest has no such
    // floor, so we fire the GET directly from the App. The App singleton is
    // long-lived, which keeps the Method receiver alive until the response
    // arrives. On success Storage gets a full replace; on failure we mirror
    // onBackgroundData's behaviour and merge `lastError` into the existing
    // dict so prior values keep rendering.

    function startForegroundRefresh() as Void {
        var loc = Locations.getSelected();
        var url = SwimfoFetch.urlFor(loc);
        System.println("foreground fetch=" + url);
        Communications.makeWebRequest(
            url,
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onForegroundData)
        );
    }

    function onForegroundData(code as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        System.println("foreground data=" + code);
        var nowSec = Time.now().value();
        if (code == 200 && data instanceof Lang.Dictionary) {
            var result = SwimfoFetch.pickKeys(data as Lang.Dictionary);
            result["lastUpdate"] = nowSec;
            result["lastAttempt"] = nowSec;
            Storage.setValue("swimfoData", result);
        } else {
            var existing = Storage.getValue("swimfoData");
            if (existing instanceof Lang.Dictionary) {
                var merged = existing as Lang.Dictionary;
                merged["lastError"] = code;
                merged["lastAttempt"] = nowSec;
                Storage.setValue("swimfoData", merged);
            }
        }
        WatchUi.requestUpdate();
    }

}
