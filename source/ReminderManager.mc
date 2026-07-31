using Toybox.Attention;
using Toybox.System;

class ReminderManager {
    function confirmCast() {
        play([
            new Attention.VibeProfile(70, 120)
        ]);
    }

    function remindDue() {
        play([
            new Attention.VibeProfile(80, 220),
            new Attention.VibeProfile(0, 120),
            new Attention.VibeProfile(80, 220),
            new Attention.VibeProfile(0, 120),
            new Attention.VibeProfile(80, 220)
        ]);
    }

    function remindOverdue() {
        play([
            new Attention.VibeProfile(90, 420),
            new Attention.VibeProfile(0, 160),
            new Attention.VibeProfile(90, 420)
        ]);
    }

    function celebrateTrip() {
        // A restrained rising double tap marks the end of a session without
        // feeling like another alert.
        play([
            new Attention.VibeProfile(45, 70),
            new Attention.VibeProfile(0, 80),
            new Attention.VibeProfile(65, 130)
        ]);
    }

    private function play(pattern) {
        if (!(Attention has :vibrate)) {
            return;
        }
        try {
            Attention.vibrate(pattern);
        } catch (e) {
            System.println("Vibration failed: " + e.getErrorMessage());
        }
    }
}
