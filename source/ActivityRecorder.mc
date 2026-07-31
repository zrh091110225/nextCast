using Toybox.Activity;
using Toybox.ActivityRecording;
using Toybox.System;

class ActivityRecorder {
    private var mSession = null;
    private var mOwnedByApp = false;

    function start() {
        if (!(Toybox has :ActivityRecording)) {
            return false;
        }

        try {
            mSession = ActivityRecording.createSession({
                :name => "CastTimer",
                :sport => Activity.SPORT_FISHING
            });

            // A currently recording session was not started by this controller.
            // Never call start/stop/save on it: safe conflict handling is a WP0 gate.
            if (mSession == null || mSession.isRecording()) {
                mSession = null;
                return false;
            }

            mSession.start();
            mOwnedByApp = mSession.isRecording();
            return mOwnedByApp;
        } catch (e) {
            System.println("Activity start failed: " + e.getErrorMessage());
            mSession = null;
            return false;
        }
    }

    function stopAndSave() {
        if (!mOwnedByApp || mSession == null) {
            return;
        }
        try {
            if (mSession.isRecording()) {
                mSession.stop();
            }
            mSession.save();
        } catch (e) {
            System.println("Activity save failed: " + e.getErrorMessage());
        }
        mOwnedByApp = false;
        mSession = null;
    }
}
