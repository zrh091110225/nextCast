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
    const PAUSED = "PAUSED";

    private var mState = "SETUP";
    private var mPreviousState = "SETUP";
    private var mIntervalSec = 180;
    private var mDeadlineEpoch = 0;
    private var mPausedRemainingSec = 0;
    private var mCastCount = 0;
    private var mAutoCastCount = 0;
    private var mManualCastCount = 0;
    private var mUndoneCastCount = 0;
    private var mDueReminderCount = 0;
    private var mBaitReminderCount = 0;
    private var mLastCastEpoch = 0;
    private var mLastCastSource = "";
    private var mSessionStartedEpoch = 0;
    private var mPausedAtEpoch = 0;
    private var mAccumulatedPausedSec = 0;
    private var mManualOnly = false;
    private var mDetector;
    private var mReminder;
    private var mRecorder;
    private var mCapabilities;
    private var mTimer;
    private var mUndo = null;
    private var mLatestSummary = null;

    function initialize() {
        // Initialize state explicitly. Class constants are not reliable in member
        // initializers on every Connect IQ runtime.
        mState = "SETUP";
        mPreviousState = "SETUP";
        mIntervalSec = 180;
        mDeadlineEpoch = 0;
        mPausedRemainingSec = 0;
        mCastCount = 0;
        mAutoCastCount = 0;
        mManualCastCount = 0;
        mUndoneCastCount = 0;
        mDueReminderCount = 0;
        mBaitReminderCount = 0;
        mLastCastEpoch = 0;
        mLastCastSource = "";
        mSessionStartedEpoch = 0;
        mPausedAtEpoch = 0;
        mAccumulatedPausedSec = 0;
        mManualOnly = false;
        mUndo = null;
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
    function isPaused() { return mState.equals("PAUSED"); }
    function isArmed() { return mState.equals("ARMED"); }
    function intervalSec() { return mIntervalSec; }
    function castCount() { return mCastCount; }
    function autoCastCount() { return mAutoCastCount; }
    function manualCastCount() { return mManualCastCount; }
    function manualOnly() { return mManualOnly; }
    function detectorSampleRate() { return mDetector.sampleRate(); }
    function latestSummary() { return mLatestSummary; }
    function undoRemainingSec() {
        if (mUndo == null) { return 0; }
        var remaining = 10 - (nowEpoch() - mUndo[:recordedAt]);
        return remaining > 0 ? remaining : 0;
    }
    function sessionElapsedSec() {
        if (mSessionStartedEpoch == 0) { return 0; }
        var elapsed = nowEpoch() - mSessionStartedEpoch - mAccumulatedPausedSec;
        if (mState.equals("PAUSED") && mPausedAtEpoch > 0) {
            elapsed -= nowEpoch() - mPausedAtEpoch;
        }
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
        if (mState.equals("COUNTING") || mState.equals("DUE")) {
            mDeadlineEpoch = nowEpoch() + mIntervalSec;
            mState = "COUNTING";
            mDueReminderCount = 0;
            persist();
        }
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
        mPausedAtEpoch = 0;
        mAccumulatedPausedSec = 0;
        mManualOnly = !mDetector.start();
        startTicking();
        persist();
        WatchUi.switchToView(new ActiveSessionView(self), new ActiveSessionDelegate(self), WatchUi.SLIDE_IMMEDIATE);
        return true;
    }

    function onAutoCast(confidence, sampleRate) {
        if (mManualOnly || (!mState.equals("ARMED") && !mState.equals("COUNTING") && !mState.equals("DUE"))) {
            return;
        }
        recordCast("auto", confidence);
    }

    function recordManualCast() {
        if (!mState.equals("ARMED") && !mState.equals("COUNTING") && !mState.equals("DUE")) {
            return;
        }
        recordCast("manual", 1.0);
    }

    function pause() {
        if (!mState.equals("ARMED") && !mState.equals("COUNTING") && !mState.equals("DUE")) {
            return;
        }
        mPreviousState = mState;
        mPausedRemainingSec = remainingSec();
        mPausedAtEpoch = nowEpoch();
        mState = "PAUSED";
        mDetector.stop();
        stopTicking();
        persist();
        WatchUi.requestUpdate();
    }

    function resumeFrozen() {
        if (!mState.equals("PAUSED")) {
            return;
        }
        mState = mPreviousState;
        if (mPausedAtEpoch > 0) {
            mAccumulatedPausedSec += nowEpoch() - mPausedAtEpoch;
            mPausedAtEpoch = 0;
        }
        if (mState.equals("COUNTING")) {
            mDeadlineEpoch = nowEpoch() + mPausedRemainingSec;
        }
        if (!mManualOnly) {
            mManualOnly = !mDetector.start();
        }
        startTicking();
        persist();
        WatchUi.requestUpdate();
    }

    function waitForNextCast() {
        var wasPaused = mState.equals("PAUSED");
        if (wasPaused && mPausedAtEpoch > 0) {
            mAccumulatedPausedSec += nowEpoch() - mPausedAtEpoch;
            mPausedAtEpoch = 0;
        }
        mDeadlineEpoch = 0;
        mPausedRemainingSec = 0;
        mDueReminderCount = 0;
        mState = "ARMED";
        mPreviousState = "ARMED";
        // Leaving a paused timer for a fresh cast is a complete resume path:
        // recognition and ticking must return, otherwise the UI would claim
        // that it is armed while no sensor stream is running.
        if (wasPaused) {
            if (!mManualOnly) {
                mManualOnly = !mDetector.start();
            }
            startTicking();
        }
        persist();
        WatchUi.requestUpdate();
    }

    function undoLastCast() {
        if (mUndo == null || (nowEpoch() - mUndo[:recordedAt]) > 10) {
            return false;
        }
        mState = mUndo[:state];
        mDeadlineEpoch = mUndo[:deadline];
        mCastCount = mUndo[:castCount];
        mAutoCastCount = mUndo[:autoCount];
        mManualCastCount = mUndo[:manualCount];
        mDueReminderCount = mUndo[:dueCount];
        mBaitReminderCount = mUndo[:baitReminderCount];
        mUndoneCastCount += 1;
        mUndo = null;
        persist();
        WatchUi.requestUpdate();
        return true;
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
        mUndoneCastCount = 0;
        mDueReminderCount = 0;
        mBaitReminderCount = 0;
        mUndo = null;
        mSessionStartedEpoch = 0;
        mPausedAtEpoch = 0;
        mAccumulatedPausedSec = 0;
        WatchUi.switchToView(new SummaryView(self), new SummaryDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }

    function remainingSec() {
        if (mState.equals("PAUSED")) {
            return mPausedRemainingSec;
        }
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
            "schemaVersion" => 3,
            "state" => mState,
            "previousState" => mPreviousState,
            "intervalSec" => mIntervalSec,
            "deadlineEpoch" => mDeadlineEpoch,
            "pausedRemainingSec" => mPausedRemainingSec,
            "castCount" => mCastCount,
            "autoCastCount" => mAutoCastCount,
            "manualCastCount" => mManualCastCount,
            "undoneCastCount" => mUndoneCastCount,
            "dueReminderCount" => mDueReminderCount,
            "baitReminderCount" => mBaitReminderCount,
            "lastCastEpoch" => mLastCastEpoch,
            "lastCastSource" => mLastCastSource,
            "sessionStartedEpoch" => mSessionStartedEpoch,
            "pausedAtEpoch" => mPausedAtEpoch,
            "accumulatedPausedSec" => mAccumulatedPausedSec,
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
        if (saved == null || (saved["schemaVersion"] != 1 && saved["schemaVersion"] != 2 && saved["schemaVersion"] != 3) || saved["state"] == null || saved["intervalSec"] == null || saved["deadlineEpoch"] == null) {
            return;
        }
        // Builds published before the storage migration used Symbol values for
        // state. Normalize them so an old saved :SETUP does not become a false
        // active session after an update.
        mState = saved["state"].toString();
        mPreviousState = saved["previousState"] == null ? "SETUP" : saved["previousState"].toString();
        mIntervalSec = saved["intervalSec"];
        mDeadlineEpoch = saved["deadlineEpoch"];
        mPausedRemainingSec = saved["pausedRemainingSec"];
        mCastCount = saved["castCount"];
        mAutoCastCount = saved["autoCastCount"];
        mManualCastCount = saved["manualCastCount"];
        mUndoneCastCount = saved["undoneCastCount"];
        mDueReminderCount = saved["dueReminderCount"];
        mBaitReminderCount = saved["baitReminderCount"] == null ? 0 : saved["baitReminderCount"];
        mLastCastEpoch = saved["lastCastEpoch"];
        mLastCastSource = saved["lastCastSource"];
        // Version 1 sessions did not retain their start time. Use the first
        // recoverable timestamp rather than fabricating a duration from launch.
        mSessionStartedEpoch = saved["sessionStartedEpoch"];
        if (mSessionStartedEpoch == null) { mSessionStartedEpoch = mLastCastEpoch; }
        if (mSessionStartedEpoch == null) { mSessionStartedEpoch = 0; }
        mPausedAtEpoch = saved["pausedAtEpoch"] == null ? 0 : saved["pausedAtEpoch"];
        mAccumulatedPausedSec = saved["accumulatedPausedSec"] == null ? 0 : saved["accumulatedPausedSec"];

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
        mUndo = {
            :recordedAt => nowEpoch(),
            :state => mState,
            :deadline => mDeadlineEpoch,
            :castCount => mCastCount,
            :autoCount => mAutoCastCount,
            :manualCount => mManualCastCount,
            :dueCount => mDueReminderCount,
            :baitReminderCount => mBaitReminderCount
        };
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
            "undoneCastCount" => mUndoneCastCount,
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
