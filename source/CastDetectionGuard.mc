using Toybox.Test;

const POST_DUE_CAST_GUARD_SEC = 15;

// The deadline is already persisted as the absolute instant when bait is due,
// so deriving the guard from it also preserves the guard across app recovery.
function isPostDueCastGuardActive(state, deadlineEpoch, currentEpoch) {
    if (deadlineEpoch <= 0 || currentEpoch < deadlineEpoch) {
        return false;
    }
    if (!state.equals("COUNTING") && !state.equals("DUE")) {
        return false;
    }
    return currentEpoch < (deadlineEpoch + POST_DUE_CAST_GUARD_SEC);
}

(:test)
function postDueCastGuardCoversCountdownTransition(logger as Test.Logger) {
    // COUNTING at the deadline covers the sub-second window before onTick()
    // changes the state to DUE.
    return isPostDueCastGuardActive("COUNTING", 100, 100) &&
        isPostDueCastGuardActive("DUE", 100, 114);
}

(:test)
function postDueCastGuardReopensAfterFifteenSeconds(logger as Test.Logger) {
    return !isPostDueCastGuardActive("DUE", 100, 115) &&
        !isPostDueCastGuardActive("COUNTING", 100, 99) &&
        !isPostDueCastGuardActive("ARMED", 0, 100);
}
