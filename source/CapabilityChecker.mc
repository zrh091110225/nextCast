using Toybox.Sensor;
using Toybox.Attention;

class CapabilityChecker {
    function hasVibration() {
        return Attention has :vibrate;
    }

    function accelerometerRate() {
        try {
            return Sensor.getMaxSampleRate();
        } catch (e) {
            return 0;
        }
    }
}
