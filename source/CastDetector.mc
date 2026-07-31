using Toybox.Math;
using Toybox.Sensor;
using Toybox.System;

class CastDetector {
    // Phase 0 defaults: deliberately conservative until field data supplies model parameters.
    private const PEAK_DELTA_MG = 1600;
    private const MIN_PEAKS = 2;
    private const COOLDOWN_MS = 5000;

    private var mController;
    private var mListening = false;
    private var mSampleRate = 0;
    private var mLastCastMs = 0;

    function initialize(controller) {
        mController = controller;
    }

    function start() {
        var maxRate = Sensor.getMaxSampleRate();
        if (maxRate == null || maxRate < 1) {
            return false;
        }

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

        var peakDelta = 0;
        var peakCount = 0;
        for (var i = 0; i < xs.size(); i += 1) {
            var magnitude = Math.sqrt((xs[i] * xs[i]) + (ys[i] * ys[i]) + (zs[i] * zs[i]));
            var delta = magnitude >= 1000 ? magnitude - 1000 : 1000 - magnitude;
            if (delta > peakDelta) {
                peakDelta = delta;
            }
            if (delta >= PEAK_DELTA_MG) {
                peakCount += 1;
            }
        }

        var nowMs = System.getTimer();
        if (peakDelta >= PEAK_DELTA_MG && peakCount >= MIN_PEAKS && (mLastCastMs == 0 || (nowMs - mLastCastMs) >= COOLDOWN_MS)) {
            mLastCastMs = nowMs;
            var confidence = peakDelta / (PEAK_DELTA_MG * 2.0);
            if (confidence > 0.99) {
                confidence = 0.99;
            }
            mController.onAutoCast(confidence, mSampleRate);
        }
    }
}
