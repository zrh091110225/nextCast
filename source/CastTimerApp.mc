using Toybox.Application;
using Toybox.WatchUi;

class CastTimerApp extends Application.AppBase {
    private var mController;

    function initialize() {
        Application.AppBase.initialize();
        mController = new SessionController();
    }

    function onStart(state) {
        mController.restore();
    }

    function onStop(state) {
        mController.persist();
    }

    function onActive(state) {
        mController.reconcileAfterForeground();
        WatchUi.requestUpdate();
    }

    function onInactive(state) {
        mController.persist();
    }

    function getInitialView() {
        if (mController.hasRecoverableSession()) {
            return [new ActiveSessionView(mController), new ActiveSessionDelegate(mController)];
        }
        return [new SetupView(mController), new SetupDelegate(mController)];
    }
}
