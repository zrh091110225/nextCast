using Toybox.Application.Storage;
using Toybox.System;
using Toybox.Time;
using Toybox.Timer;
using Toybox.WatchUi;

class SessionController {
    const SETUP = "SETUP";
    const ARMED = "ARMED";
    const COUNTING = "COUNTING";
    const DUE = "DUE";

    private var mState = "SETUP";
    private var mIntervalSec = 180;
    private var mDeadlineEpoch = 0;
    private var mCastCount = 0;
    private var mAutoCastCount = 0;
    private var mManualCastCount = 0;
    private var mDueReminderCount = 0;
    private var mBaitReminderCount = 0;
    private var mLastCastEpoch = 0;
    private var mLastCastSource = "";
    private var mSessionStartedEpoch = 0;
    private var mManualOnly = false;
    private var mDetector;
    private var mReminder;
    private var mRecorder;
    private var mCapabilities;
    private var mTimer;
    private var mLatestSummary = null;

    function initialize() {
        // Initialize state explicitly. Class constants are not reliable in member
        // initializers on every Connect IQ runtime.
        mState = "SETUP";
        mIntervalSec = 180;
        mDeadlineEpoch = 0;
        mCastCount = 0;
        mAutoCastCount = 0;
        mManualCastCount = 0;
        mDueReminderCount = 0;
        mBaitReminderCount = 0;
        mLastCastEpoch = 0;
        mLastCastSource = "";
        mSessionStartedEpoch = 0;
        mManualOnly = false;
        mLatestSummary = null;
        mDetector = new CastDetector(self);
        mReminder = new ReminderManager();
        mRecorder = new ActivityRecorder();
        mCapabilities = new CapabilityChecker();
        mTimer = new Timer.Timer();
    }

    function state() { return mState; }
    function hasRecoverableSession() { return !mState.equals("SETUP"); }
    function isDue() { return mState.equals("DUE"); }
    function isArmed() { return mState.equals("ARMED"); }
    function intervalSec() { return mIntervalSec; }
    function castCount() { return mCastCount; }
    function autoCastCount() { return mAutoCastCount; }
    function manualCastCount() { return mManualCastCount; }
    function manualOnly() { return mManualOnly; }
    function detectorSampleRate() { return mDetector.sampleRate(); }
    function latestSummary() { return mLatestSummary; }
    function canDetectCastMotion() {
        if (mManualOnly || (!mState.equals("ARMED") && !mState.equals("COUNTING") && !mState.equals("DUE"))) {
            return false;
        }
        return !isPostDueCastGuardActive(mState, mDeadlineEpoch, nowEpoch());
    }
    function sessionElapsedSec() {
        if (mSessionStartedEpoch == 0) { return 0; }
        var elapsed = nowEpoch() - mSessionStartedEpoch;
        return elapsed > 0 ? elapsed : 0;
    }

    function setIntervalSec(value) {
        if (value < 30) { value = 30; }
        if (value > 600) { value = 600; }
        mIntervalSec = value;
        try {
            Storage.setValue("interval_sec", mIntervalSec);
        } catch (e) {
            System.println("Interval persistence failed: " + e.getErrorMessage());
        }
        // An interval change applies to the next cast only. It never changes
        // the timing of bait already in the water.
        persist();
        WatchUi.requestUpdate();
    }

    function startSession() {
        if (!mState.equals("SETUP")) {
            return false;
        }

        if (!mCapabilities.hasVibration()) {
            return false;
        }

        // Activity recording is required for the release build. If it cannot start,
        // do not silently claim that the full automatic mode is active.
        if (!mRecorder.start()) {
            return false;
        }

        mState = "ARMED";
        mSessionStartedEpoch = nowEpoch();
        mManualOnly = !mDetector.start();
        startTicking();
        persist();
        WatchUi.switchToView(new ActiveSessionView(self), new ActiveSessionDelegate(self), WatchUi.SLIDE_IMMEDIATE);
        return true;
    }

    function onAutoCast(confidence, sampleRate) {
        if (!canDetectCastMotion()) {
            return;
        }
        recordCast("auto", confidence);
    }

    function recordManualCast() {
        // Once bait-change time has elapsed, only the motion detector may
        // start the next cycle. This prevents an incidental button press from
        // being interpreted as a fresh cast.
        if (!mState.equals("ARMED") && !mState.equals("COUNTING")) {
            return;
        }
        recordCast("manual", 1.0);
    }

    function endSession() {
        mDetector.stop();
        stopTicking();
        mRecorder.stopAndSave();
        saveSummary();
        mReminder.celebrateTrip();
        clearCurrentSession();
        mState = "SETUP";
        mDeadlineEpoch = 0;
        mCastCount = 0;
        mAutoCastCount = 0;
        mManualCastCount = 0;
        mDueReminderCount = 0;
        mBaitReminderCount = 0;
        mSessionStartedEpoch = 0;
        WatchUi.switchToView(new SummaryView(self), new SummaryDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }

    function remainingSec() {
        if (mDeadlineEpoch == 0) {
            return 0;
        }
        var remaining = mDeadlineEpoch - nowEpoch();
        return remaining > 0 ? remaining : 0;
    }

    function overdueSec() {
        if (!mState.equals("DUE") || mDeadlineEpoch == 0) {
            return 0;
        }
        var overdue = nowEpoch() - mDeadlineEpoch;
        return overdue > 0 ? overdue : 0;
    }

    function persist() {
        if (mState.equals("SETUP")) {
            return;
        }
        var saved = {
            "schemaVersion" => 4,
            "state" => mState,
            "intervalSec" => mIntervalSec,
            "deadlineEpoch" => mDeadlineEpoch,
            "castCount" => mCastCount,
            "autoCastCount" => mAutoCastCount,
            "manualCastCount" => mManualCastCount,
            "dueReminderCount" => mDueReminderCount,
            "baitReminderCount" => mBaitReminderCount,
            "lastCastEpoch" => mLastCastEpoch,
            "lastCastSource" => mLastCastSource,
            "sessionStartedEpoch" => mSessionStartedEpoch,
            "manualOnly" => mManualOnly
        };
        try {
            Storage.setValue("current_session", saved);
        } catch (e) {
            System.println("Session persistence failed: " + e.getErrorMessage());
        }
    }

    function restore() {
        var storedInterval = null;
        try {
            storedInterval = Storage.getValue("interval_sec");
        } catch (e) {
            System.println("Interval restore failed: " + e.getErrorMessage());
        }
        if (storedInterval != null) {
            mIntervalSec = storedInterval;
        }

        var saved = null;
        try {
            saved = Storage.getValue("current_session");
        } catch (e) {
            System.println("Session restore failed: " + e.getErrorMessage());
            return;
        }
        if (saved == null || (saved["schemaVersion"] != 1 && saved["schemaVersion"] != 2 && saved["schemaVersion"] != 3 && saved["schemaVersion"] != 4) || saved["state"] == null || saved["intervalSec"] == null || saved["deadlineEpoch"] == null) {
            return;
        }
        // Builds published before the storage migration used Symbol values for
        // state. Normalize them so an old saved :SETUP does not become a false
        // active session after an update.
        mState = saved["state"].toString();
        mIntervalSec = saved["intervalSec"];
        mDeadlineEpoch = saved["deadlineEpoch"];
        mCastCount = saved["castCount"];
        mAutoCastCount = saved["autoCastCount"];
        mManualCastCount = saved["manualCastCount"];
        mDueReminderCount = saved["dueReminderCount"];
        mBaitReminderCount = saved["baitReminderCount"] == null ? 0 : saved["baitReminderCount"];
        mLastCastEpoch = saved["lastCastEpoch"];
        mLastCastSource = saved["lastCastSource"];
        // Version 1 sessions did not retain their start time. Use the first
        // recoverable timestamp rather than fabricating a duration from launch.
        mSessionStartedEpoch = saved["sessionStartedEpoch"];
        if (mSessionStartedEpoch == null) { mSessionStartedEpoch = mLastCastEpoch; }
        if (mSessionStartedEpoch == null) { mSessionStartedEpoch = 0; }

        // A session paused by an older app version is resumed safely during
        // migration because pausing is no longer part of the product flow.
        if (mState.equals("PAUSED")) {
            var previous = saved["previousState"] == null ? "ARMED" : saved["previousState"].toString();
            if (previous.equals("COUNTING")) {
                mState = "COUNTING";
                var pausedRemaining = saved["pausedRemainingSec"] == null ? 0 : saved["pausedRemainingSec"];
                mDeadlineEpoch = nowEpoch() + pausedRemaining;
            } else if (previous.equals("DUE")) {
                mState = "DUE";
            } else {
                mState = "ARMED";
            }
        }

        // A countdown without a deadline can be left behind by an interrupted
        // transition. Recover it as an armed session rather than presenting a
        // misleading 00:00 countdown.
        if ((mState.equals("COUNTING") || mState.equals("DUE")) && mDeadlineEpoch <= 0) {
            mState = "ARMED";
        }
        // The ActivityRecording object itself is not durable across an app restart.
        // Resume the countdown safely, but require a new Phase 0-validated activity
        // flow before claiming that automatic recognition has resumed.
        mManualOnly = true;
        reconcileAfterForeground();
    }

    function reconcileAfterForeground() {
        if (mState.equals("COUNTING") && remainingSec() == 0) {
            // Attention is unavailable while inactive. Restore the state only;
            // no late vibration is emitted because it would misrepresent timing.
            mState = "DUE";
            persist();
        }
    }

    private function recordCast(source, confidence) {
        mCastCount += 1;
        if (source == "auto") {
            mAutoCastCount += 1;
        } else {
            mManualCastCount += 1;
        }
        mLastCastEpoch = nowEpoch();
        mLastCastSource = source;
        mDeadlineEpoch = mLastCastEpoch + mIntervalSec;
        mDueReminderCount = 0;
        mState = "COUNTING";
        mReminder.confirmCast();
        persist();
        WatchUi.requestUpdate();
    }

    function onTick() {
        if (mState.equals("COUNTING") && remainingSec() == 0) {
            mState = "DUE";
            mDueReminderCount = 1;
            mBaitReminderCount += 1;
            mReminder.remindDue();
            persist();
        } else if (mState.equals("DUE")) {
            var overdue = overdueSec();
            if (mDueReminderCount == 1 && overdue >= 60) {
                mDueReminderCount = 2;
                mReminder.remindOverdue();
                persist();
            } else if (mDueReminderCount == 2 && overdue >= 120) {
                mDueReminderCount = 3;
                mReminder.remindOverdue();
                persist();
            }
        }
        WatchUi.requestUpdate();
    }

    private function startTicking() {
        mTimer.stop();
        mTimer.start(method(:onTick), 1000, true);
    }

    private function stopTicking() {
        mTimer.stop();
    }

    private function nowEpoch() {
        return Time.now().value();
    }

    private function saveSummary() {
        var summary = {
            "endedAtEpoch" => nowEpoch(),
            "castCount" => mCastCount,
            "autoCastCount" => mAutoCastCount,
            "manualCastCount" => mManualCastCount,
            "intervalSec" => mIntervalSec,
            "durationSec" => sessionElapsedSec(),
            "baitReminderCount" => mBaitReminderCount
        };
        mLatestSummary = summary;
        try {
            Storage.setValue("latest_summary", summary);
        } catch (e) {
            System.println("Summary persistence failed: " + e.getErrorMessage());
        }
    }

    private function clearCurrentSession() {
        try {
            Storage.deleteValue("current_session");
        } catch (e) {
            System.println("Session cleanup failed: " + e.getErrorMessage());
        }
    }
}
