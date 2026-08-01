using Toybox.Math;
using Toybox.Sensor;
using Toybox.System;

class CastDetector {
    // A slow low-pass estimate tracks gravity while the remaining high-pass
    // component captures wrist movement. A cast is deliberately treated as a
    // three-part sequence, rather than any isolated wrist movement:
    // forceful forward launch -> rod drop -> arm recovery.
    private const GRAVITY_ALPHA = 0.08;
    private const FORWARD_MOTION_THRESHOLD_MG = 1200;
    private const FORWARD_JERK_THRESHOLD_MG = 450;
    private const FOLLOW_THROUGH_MOTION_THRESHOLD_MG = 700;
    private const FOLLOW_THROUGH_JERK_THRESHOLD_MG = 300;
    private const RECOVERY_MOTION_THRESHOLD_MG = 650;
    private const RECOVERY_JERK_THRESHOLD_MG = 250;
    private const MIN_PHASE_GAP_SAMPLES = 2;
    private const MAX_PHASE_SAMPLES = 30;
    private const REVERSAL_DOT_RATIO = 0.20;
    private const WARMUP_SAMPLES = 10;
    private const COOLDOWN_MS = 5000;

    private var mController;
    private var mListening = false;
    private var mSampleRate = 0;
    private var mLastCastMs = 0;
    private var mGravityReady = false;
    private var mGravityX = 0.0;
    private var mGravityY = 0.0;
    private var mGravityZ = 0.0;
    private var mPreviousMotionX = 0.0;
    private var mPreviousMotionY = 0.0;
    private var mPreviousMotionZ = 0.0;
    private var mWarmupRemaining = WARMUP_SAMPLES;
    private var mCastStage = 0;
    private var mStageSamples = 0;
    private var mLaunchMotion = 0.0;
    private var mLaunchX = 0.0;
    private var mLaunchY = 0.0;
    private var mLaunchZ = 0.0;
    private var mDropMotion = 0.0;
    private var mDropX = 0.0;
    private var mDropY = 0.0;
    private var mDropZ = 0.0;

    function initialize(controller) {
        mController = controller;
    }

    function start() {
        var maxRate = Sensor.getMaxSampleRate();
        if (maxRate == null || maxRate < 1) {
            return false;
        }

        resetMotionFilter();

        // 25Hz is the desired baseline. On lower-capability devices the controller
        // stays usable, but this must be treated as manual-only until Phase 0 passes.
        mSampleRate = maxRate >= 25 ? 25 : maxRate;

        try {
            Sensor.registerSensorDataListener(method(:onSensorData), {
                // The Sensor API expresses period in seconds, not milliseconds.
                :period => 1,
                :accelerometer => {
                    :enabled => true,
                    :sampleRate => mSampleRate
                }
            });
            mListening = true;
            return true;
        } catch (e) {
            System.println("CastDetector start failed: " + e.getErrorMessage());
            mListening = false;
            return false;
        }
    }

    function stop() {
        if (!mListening) {
            return;
        }

        try {
            Sensor.unregisterSensorDataListener();
        } catch (e) {
            System.println("CastDetector stop failed: " + e.getErrorMessage());
        }
        mListening = false;
    }

    function sampleRate() {
        return mSampleRate;
    }

    private function resetMotionFilter() {
        mGravityReady = false;
        mGravityX = 0.0;
        mGravityY = 0.0;
        mGravityZ = 0.0;
        mPreviousMotionX = 0.0;
        mPreviousMotionY = 0.0;
        mPreviousMotionZ = 0.0;
        mWarmupRemaining = WARMUP_SAMPLES;
        resetCastSequence();
    }

    private function resetCastSequence() {
        mCastStage = 0;
        mStageSamples = 0;
        mLaunchMotion = 0.0;
        mLaunchX = 0.0;
        mLaunchY = 0.0;
        mLaunchZ = 0.0;
        mDropMotion = 0.0;
        mDropX = 0.0;
        mDropY = 0.0;
        mDropZ = 0.0;
    }

    function onSensorData(data) {
        if (!mListening || data == null || data.accelerometerData == null) {
            return;
        }

        var accel = data.accelerometerData;
        var xs = accel.x;
        var ys = accel.y;
        var zs = accel.z;
        if (xs == null || ys == null || zs == null) {
            return;
        }

        var nowMs = System.getTimer();
        var canDetectCast = mController.canDetectCastMotion();
        for (var i = 0; i < xs.size(); i += 1) {
            if (!mGravityReady) {
                mGravityX = xs[i].toFloat();
                mGravityY = ys[i].toFloat();
                mGravityZ = zs[i].toFloat();
                mGravityReady = true;
                continue;
            }

            mGravityX += (xs[i] - mGravityX) * GRAVITY_ALPHA;
            mGravityY += (ys[i] - mGravityY) * GRAVITY_ALPHA;
            mGravityZ += (zs[i] - mGravityZ) * GRAVITY_ALPHA;

            var motionX = xs[i] - mGravityX;
            var motionY = ys[i] - mGravityY;
            var motionZ = zs[i] - mGravityZ;
            var motion = Math.sqrt((motionX * motionX) + (motionY * motionY) + (motionZ * motionZ));
            var jerkX = motionX - mPreviousMotionX;
            var jerkY = motionY - mPreviousMotionY;
            var jerkZ = motionZ - mPreviousMotionZ;
            var jerk = Math.sqrt((jerkX * jerkX) + (jerkY * jerkY) + (jerkZ * jerkZ));

            mPreviousMotionX = motionX;
            mPreviousMotionY = motionY;
            mPreviousMotionZ = motionZ;

            if (mWarmupRemaining > 0) {
                mWarmupRemaining -= 1;
                continue;
            }

            // Keep the gravity estimate current while the user reels in, but
            // never carry a partial retrieval sequence beyond the guard.
            if (!canDetectCast) {
                resetCastSequence();
                continue;
            }

            if (mCastStage == 0) {
                // Stage 1: a real cast starts with a strong, fast launch. A
                // normal raise-to-check-time gesture should not reach this bar.
                if (motion >= FORWARD_MOTION_THRESHOLD_MG && jerk >= FORWARD_JERK_THRESHOLD_MG) {
                    mCastStage = 1;
                    mStageSamples = 0;
                    mLaunchMotion = motion;
                    mLaunchX = motionX;
                    mLaunchY = motionY;
                    mLaunchZ = motionZ;
                }
            } else if (mCastStage == 1) {
                mStageSamples += 1;
                if (motion > mLaunchMotion) {
                    mLaunchMotion = motion;
                    mLaunchX = motionX;
                    mLaunchY = motionY;
                    mLaunchZ = motionZ;
                }

                // Stage 2: dropping the rod must be a separate, substantial
                // change in a direction away from the launch vector.
                var launchDot = (mLaunchX * motionX) + (mLaunchY * motionY) + (mLaunchZ * motionZ);
                if (mStageSamples >= MIN_PHASE_GAP_SAMPLES &&
                    motion >= FOLLOW_THROUGH_MOTION_THRESHOLD_MG &&
                    jerk >= FOLLOW_THROUGH_JERK_THRESHOLD_MG &&
                    launchDot <= -(mLaunchMotion * motion * REVERSAL_DOT_RATIO)) {
                    mCastStage = 2;
                    mStageSamples = 0;
                    mDropMotion = motion;
                    mDropX = motionX;
                    mDropY = motionY;
                    mDropZ = motionZ;
                } else if (mStageSamples > MAX_PHASE_SAMPLES) {
                    resetCastSequence();
                }
            } else {
                mStageSamples += 1;
                // Stage 3: the arm comes back after the rod is dropped. Only
                // this completed sequence can count as a cast.
                var dropDot = (mDropX * motionX) + (mDropY * motionY) + (mDropZ * motionZ);
                if (mStageSamples >= MIN_PHASE_GAP_SAMPLES &&
                    motion >= RECOVERY_MOTION_THRESHOLD_MG &&
                    jerk >= RECOVERY_JERK_THRESHOLD_MG &&
                    dropDot <= -(mDropMotion * motion * REVERSAL_DOT_RATIO)) {
                    if (mLastCastMs == 0 || (nowMs - mLastCastMs) >= COOLDOWN_MS) {
                        mLastCastMs = nowMs;
                        var confidence = 0.70 + ((mLaunchMotion - FORWARD_MOTION_THRESHOLD_MG) / (FORWARD_MOTION_THRESHOLD_MG * 2.0));
                        if (confidence > 0.99) {
                            confidence = 0.99;
                        }
                        mController.onAutoCast(confidence, mSampleRate);
                    }
                    resetCastSequence();
                    break;
                } else if (mStageSamples > MAX_PHASE_SAMPLES) {
                    resetCastSequence();
                }
            }
        }
    }
}
