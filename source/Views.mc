using Toybox.Application;
using Toybox.Graphics;
using Toybox.System;
using Toybox.WatchUi;

// The interface deliberately uses a quiet, deep-water palette.  The amber
// bobber is the only warm colour: it always points to the action that matters.
const WATER = 0x031B29;
const WATER_LINE = 0x0C5264;
const FOAM = 0xA8E4DF;
const MIST = 0xD8F4F0;
const MUTED = 0x8DC7C4;
const BOBBER = 0xFFC15E;
const ALERT = 0xFF7262;

class SetupView extends WatchUi.View {
    private var mController;

    function initialize(controller) {
        View.initialize();
        mController = controller;
    }

    function onUpdate(dc) {
        drawWaterBackground(dc);
        var h = dc.getHeight();
        drawBrand(dc, "SMART FISHING");
        drawCjkCenteredColor(dc, "智能守钓", h * 0.17, MIST);
        drawBobber(dc, h * 0.36, BOBBER);
        drawCjkCenteredColor(dc, "换饵间隔", h * 0.54, FOAM);
        drawCenteredColor(dc, formatDuration(mController.intervalSec()), h * 0.60, Graphics.FONT_LARGE, MIST);
        drawActionBar(dc, "选择：开始垂钓", BOBBER);
    }
}

class SetupDelegate extends WatchUi.BehaviorDelegate {
    private var mController;

    function initialize(controller) {
        BehaviorDelegate.initialize();
        mController = controller;
    }

    function onSelect() { return beginSession(); }

    function onKey(keyEvent) {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_START || key == WatchUi.KEY_ENTER) {
            return beginSession();
        } else if (key == WatchUi.KEY_UP) {
            mController.setIntervalSec(mController.intervalSec() - 30);
            return true;
        } else if (key == WatchUi.KEY_DOWN) {
            mController.setIntervalSec(mController.intervalSec() + 30);
            return true;
        }
        return false;
    }

    private function beginSession() {
        if (!mController.startSession()) {
            WatchUi.pushView(new MessageView("无法开始", "请结束现有活动后重试"), null, WatchUi.SLIDE_UP);
        }
        return true;
    }

    function onNextPage() {
        mController.setIntervalSec(mController.intervalSec() + 30);
        return true;
    }

    function onPreviousPage() {
        mController.setIntervalSec(mController.intervalSec() - 30);
        return true;
    }
}

class ActiveSessionView extends WatchUi.View {
    private var mController;

    function initialize(controller) {
        View.initialize();
        mController = controller;
    }

    function onUpdate(dc) {
        drawWaterBackground(dc);
        var h = dc.getHeight();
        drawSessionHeader(dc, mController, h);

        if (mController.isDue()) {
            drawDueState(dc, h);
        } else if (mController.isPaused()) {
            drawPausedState(dc, h);
        } else if (mController.isArmed()) {
            drawArmedState(dc, h);
        } else {
            drawCountingState(dc, h);
        }
    }

    private function drawDueState(dc, h) {
        drawTimerFace(dc, h * 0.32, ALERT, 0, true);
        drawCjkCenteredColor(dc, "时间到，请换饵", h * 0.54, MIST);
        drawCjkCenteredColor(dc, "已超时 " + formatDuration(mController.overdueSec()), h * 0.62, ALERT);
        drawCjkCenteredColor(dc, "正在识别新的抛竿动作", h * 0.69, FOAM);
        drawActionBar(dc, "抛竿后自动开始下一轮", BOBBER);
    }

    private function drawPausedState(dc, h) {
        drawTimerFace(dc, h * 0.35, MUTED, mController.remainingSec(), false);
        drawCjkCenteredColor(dc, "已暂停", h * 0.56, MIST);
        drawCjkCenteredColor(dc, "计时冻结，识别已停止", h * 0.64, FOAM);
        drawActionBar(dc, "选择：继续计时", BOBBER);
    }

    private function drawArmedState(dc, h) {
        drawCastLine(dc, h * 0.36);
        drawCjkCenteredColor(dc, "准备抛竿", h * 0.55, MIST);
        drawCjkCenteredColor(dc, mController.manualOnly() ? "手动模式：按选择补记" : "自动识别已就绪", h * 0.64, FOAM);
        drawActionBar(dc, "选择：记录抛竿", BOBBER);
    }

    private function drawCountingState(dc, h) {
        drawTimerFace(dc, h * 0.34, BOBBER, mController.remainingSec(), false);
        drawCjkCenteredColor(dc, "第 " + mController.castCount() + " 轮 · " + (mController.manualOnly() ? "手动计时" : "自动识别中"), h * 0.50, MIST);
        drawStatSplit(dc, h * 0.63, "累计抛竿", mController.castCount().toString(), "作钓时长", formatDuration(mController.sessionElapsedSec()));
        var undoSec = mController.undoRemainingSec();
        drawActionBar(dc, undoSec > 0 ? "返回撤销  菜单" : "菜单：暂停/结束", BOBBER);
    }
}

class ActiveSessionDelegate extends WatchUi.BehaviorDelegate {
    private var mController;

    function initialize(controller) {
        BehaviorDelegate.initialize();
        mController = controller;
    }

    function onSelect() { return recordOrResume(); }

    function onKey(keyEvent) {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_START || key == WatchUi.KEY_ENTER) {
            return recordOrResume();
        } else if (key == WatchUi.KEY_ESC) {
            return undo();
        } else if (key == WatchUi.KEY_MENU) {
            return openMenu();
        }
        return false;
    }

    private function recordOrResume() {
        // While a countdown is running or has elapsed, a Select/touch must
        // never create a new cast or reset the deadline. A new round is
        // initiated only after the sensor recognizes a fresh casting motion.
        if (mController.isDue() || (!mController.isPaused() && !mController.isArmed())) {
            return true;
        }
        if (mController.isPaused()) {
            mController.resumeFrozen();
        } else {
            mController.recordManualCast();
        }
        return true;
    }

    function onBack() { return undo(); }

    private function undo() {
        if (!mController.undoLastCast()) {
            WatchUi.pushView(new MessageView("无可撤销事件", "抛竿后 10 秒内可撤销"), null, WatchUi.SLIDE_UP);
        }
        return true;
    }

    function onMenu() { return openMenu(); }

    private function openMenu() {
        WatchUi.pushView(new SessionMenuView(mController), new SessionMenuDelegate(mController), WatchUi.SLIDE_UP);
        return true;
    }
}

class SessionMenuView extends WatchUi.View {
    private var mController;

    function initialize(controller) {
        View.initialize();
        mController = controller;
    }

    function onUpdate(dc) {
        drawWaterBackground(dc);
        var h = dc.getHeight();
        drawBrand(dc, "SESSION CONTROL");
        drawCjkCenteredColor(dc, "本次垂钓", h * 0.14, MIST);
        drawCjkCenteredColor(dc, "已抛竿 " + mController.castCount() + " 次 · " + formatDuration(mController.sessionElapsedSec()), h * 0.21, FOAM);
        drawMenuRow(dc, h * 0.34, "选择", mController.isPaused() ? "继续计时" : "暂停计时", BOBBER);
        drawMenuRow(dc, h * 0.48, "下页", "调整下次间隔", FOAM);
        drawMenuRow(dc, h * 0.62, "上页", "重新计时", FOAM);
        drawMenuRow(dc, h * 0.76, "菜单", "结束本次垂钓", ALERT);
    }
}

class SessionMenuDelegate extends WatchUi.BehaviorDelegate {
    private var mController;

    function initialize(controller) {
        BehaviorDelegate.initialize();
        mController = controller;
    }

    function onSelect() {
        if (mController.isPaused()) { mController.resumeFrozen(); } else { mController.pause(); }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onNextPage() {
        var adjustView = new IntervalAdjustView(mController);
        WatchUi.pushView(adjustView, new IntervalAdjustDelegate(mController, adjustView), WatchUi.SLIDE_UP);
        return true;
    }

    function onPreviousPage() {
        mController.waitForNextCast();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onMenu() {
        WatchUi.pushView(new EndConfirmView(mController), new EndConfirmDelegate(mController), WatchUi.SLIDE_UP);
        return true;
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

class IntervalAdjustView extends WatchUi.View {
    private var mIntervalSec;

    function initialize(controller) {
        View.initialize();
        mIntervalSec = controller.intervalSec();
    }

    function intervalSec() { return mIntervalSec; }

    function adjust(delta) {
        mIntervalSec += delta;
        if (mIntervalSec < 30) { mIntervalSec = 30; }
        if (mIntervalSec > 600) { mIntervalSec = 600; }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        drawWaterBackground(dc);
        var h = dc.getHeight();
        drawBrand(dc, "NEXT CAST");
        drawCjkCenteredColor(dc, "下次抛竿间隔", h * 0.20, MIST);
        drawBobber(dc, h * 0.40, BOBBER);
        drawCenteredColor(dc, formatDuration(mIntervalSec), h * 0.57, Graphics.FONT_LARGE, MIST);
        drawCjkCenteredColor(dc, "上/下调整 · 选择保存", h * 0.72, FOAM);
        drawCjkCenteredColor(dc, "返回：取消", h * 0.80, MUTED);
    }
}

class IntervalAdjustDelegate extends WatchUi.BehaviorDelegate {
    private var mController;
    private var mView;

    function initialize(controller, view) {
        BehaviorDelegate.initialize();
        mController = controller;
        mView = view;
    }

    function onSelect() {
        mController.setIntervalSec(mView.intervalSec());
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onKey(keyEvent) {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_START || key == WatchUi.KEY_ENTER) {
            return onSelect();
        } else if (key == WatchUi.KEY_UP) {
            mView.adjust(-30);
            return true;
        } else if (key == WatchUi.KEY_DOWN) {
            mView.adjust(30);
            return true;
        } else if (key == WatchUi.KEY_ESC) {
            return cancel();
        }
        return false;
    }

    function onNextPage() { mView.adjust(30); return true; }
    function onPreviousPage() { mView.adjust(-30); return true; }
    function onBack() { return cancel(); }
    function onMenu() { return cancel(); }

    private function cancel() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

class MessageView extends WatchUi.View {
    private var mTitle;
    private var mBody;

    function initialize(title, body) {
        View.initialize();
        mTitle = title;
        mBody = body;
    }

    function onUpdate(dc) {
        drawWaterBackground(dc);
        var h = dc.getHeight();
        drawBrand(dc, "CAST TIMER");
        drawHook(dc, h * 0.37, ALERT);
        drawCjkCenteredColor(dc, mTitle, h * 0.57, MIST);
        drawCjkCenteredColor(dc, mBody, h * 0.67, FOAM);
        drawActionBar(dc, "返回", BOBBER);
    }
}

class EndConfirmView extends WatchUi.View {
    private var mController;

    function initialize(controller) {
        View.initialize();
        mController = controller;
    }

    function onUpdate(dc) {
        drawWaterBackground(dc);
        var h = dc.getHeight();
        drawBrand(dc, "END SESSION");
        drawHook(dc, h * 0.34, ALERT);
        drawCjkCenteredColor(dc, "结束本次垂钓？", h * 0.54, MIST);
        drawCjkCenteredColor(dc, "已抛竿 " + mController.castCount() + " 次", h * 0.64, FOAM);
        drawCjkCenteredColor(dc, "选择确认  ·  返回继续", h * 0.78, FOAM);
    }
}

class EndConfirmDelegate extends WatchUi.BehaviorDelegate {
    private var mController;

    function initialize(controller) {
        BehaviorDelegate.initialize();
        mController = controller;
    }

    function onSelect() {
        mController.endSession();
        return true;
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

class SummaryView extends WatchUi.View {
    private var mController;

    function initialize(controller) {
        View.initialize();
        mController = controller;
    }

    function onUpdate(dc) {
        drawWaterBackground(dc);
        var h = dc.getHeight();
        var summary = mController.latestSummary();
        drawCjkCenteredColor(dc, "收竿完成", h * 0.14, BOBBER);
        drawCjkCenteredColor(dc, "今日作钓已圆满结束", h * 0.22, MIST);
        drawAchievementMedal(dc, h * 0.36);
        drawCjkCenteredColor(dc, "一竿一守，静候有获", h * 0.50, FOAM);
        drawTripStats(dc, h * 0.64, summary);
        drawSummaryFooter(dc, h * 0.80);
    }
}

class SummaryDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onSelect() { System.exit(); return true; }
    function onBack() { System.exit(); return true; }
}

function drawWaterBackground(dc) {
    dc.setColor(WATER, WATER);
    dc.clear();
}

function drawBrand(dc, text) {
    dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
    dc.drawText(dc.getWidth() / 2, dc.getHeight() * 0.055, Graphics.FONT_TINY, text, Graphics.TEXT_JUSTIFY_CENTER);
}

function drawSessionHeader(dc, controller, h) {
    var activeColour = controller.manualOnly() ? BOBBER : FOAM;
    dc.setColor(activeColour, Graphics.COLOR_TRANSPARENT);
    dc.fillCircle(dc.getWidth() * 0.28, h * 0.055, 3);
    drawCenteredColor(dc, controller.manualOnly() ? "MANUAL" : "AUTO READY", h * 0.035, Graphics.FONT_TINY, MUTED);
}

// A consistent centrepiece makes the timer readable at a glance without
// requiring a filled progress arc, which is not uniformly available on every
// Connect IQ target in this app's device range.
function drawTimerFace(dc, y, colour, remainingSec, isDue) {
    var x = dc.getWidth() / 2;
    var radius = dc.getWidth() * 0.18;
    var timerText = isDue ? "00:00" : formatDuration(remainingSec);
    dc.setColor(WATER_LINE, Graphics.COLOR_TRANSPARENT);
    dc.drawCircle(x, y, radius);
    dc.drawCircle(x, y, radius - 5);
    dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
    dc.drawLine(x, y - radius, x, y - radius + 7);
    dc.drawLine(x + radius, y, x + radius - 7, y);
    dc.drawLine(x, y + radius, x, y + radius - 7);
    dc.drawLine(x - radius, y, x - radius + 7, y);
    if (isDue) {
        drawRipple(dc, y, colour);
    }
    // Place the text by its actual system-font height, not by a fixed guess.
    // This keeps the countdown centred inside the ring on every device.
    var dimensions = dc.getTextDimensions(timerText, Graphics.FONT_LARGE);
    drawCenteredColor(dc, timerText, y - (dimensions[1] / 2), Graphics.FONT_LARGE, isDue ? colour : MIST);
}

function drawStatSplit(dc, y, leftLabel, leftValue, rightLabel, rightValue) {
    var w = dc.getWidth();
    dc.setColor(WATER_LINE, Graphics.COLOR_TRANSPARENT);
    dc.drawLine(w * 0.50, y - 10, w * 0.50, y + 20);
    drawCjkCenteredAt(dc, leftLabel, w * 0.30, y - 12, MUTED);
    drawCenteredAt(dc, leftValue, w * 0.30, y + 2, Graphics.FONT_SMALL, FOAM);
    drawCjkCenteredAt(dc, rightLabel, w * 0.70, y - 12, MUTED);
    drawCenteredAt(dc, rightValue, w * 0.70, y + 2, Graphics.FONT_SMALL, FOAM);
}

function drawBobber(dc, y, colour) {
    var x = dc.getWidth() / 2;
    dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
    dc.drawLine(x, y - 28, x, y - 8);
    dc.setColor(FOAM, Graphics.COLOR_TRANSPARENT);
    dc.fillCircle(x, y, 9);
    dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
    dc.fillCircle(x, y - 3, 7);
    dc.setColor(WATER_LINE, Graphics.COLOR_TRANSPARENT);
    dc.drawLine(x - 30, y + 12, x + 30, y + 12);
    dc.drawLine(x - 18, y + 18, x + 18, y + 18);
}

function drawRipple(dc, y, colour) {
    var x = dc.getWidth() / 2;
    dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
    dc.drawCircle(x, y, 9);
    dc.drawCircle(x, y, 18);
    dc.drawCircle(x, y, 28);
    dc.fillCircle(x, y, 3);
}

function drawAchievementMedal(dc, y) {
    var x = dc.getWidth() / 2;
    dc.setColor(WATER_LINE, WATER_LINE);
    dc.fillCircle(x, y, 25);
    dc.setColor(BOBBER, Graphics.COLOR_TRANSPARENT);
    dc.drawCircle(x, y, 25);
    dc.drawCircle(x, y, 20);
    dc.setColor(FOAM, Graphics.COLOR_TRANSPARENT);
    dc.drawCircle(x - 4, y, 7);
    dc.drawLine(x + 3, y, x + 12, y - 7);
    dc.drawLine(x + 12, y - 7, x + 12, y + 7);
    dc.drawLine(x + 12, y + 7, x + 3, y);
    dc.setColor(BOBBER, Graphics.COLOR_TRANSPARENT);
    dc.fillCircle(x - 6, y - 2, 1);
    dc.setColor(FOAM, Graphics.COLOR_TRANSPARENT);
    dc.drawLine(x - 13, y + 12, x + 8, y + 12);
    dc.setColor(WATER, WATER);
    dc.fillCircle(x + 20, y + 17, 10);
    dc.setColor(BOBBER, Graphics.COLOR_TRANSPARENT);
    dc.drawCircle(x + 20, y + 17, 10);
    dc.drawLine(x + 15, y + 17, x + 19, y + 21);
    dc.drawLine(x + 19, y + 21, x + 26, y + 12);
}

function drawTripStats(dc, y, summary) {
    var w = dc.getWidth();
    var left = w * 0.25;
    var center = w * 0.50;
    var right = w * 0.75;
    dc.setColor(WATER_LINE, Graphics.COLOR_TRANSPARENT);
    dc.drawLine(w * 0.375, y - 12, w * 0.375, y + 24);
    dc.drawLine(w * 0.625, y - 12, w * 0.625, y + 24);
    drawCjkCenteredAt(dc, "总抛竿", left, y - 14, MUTED);
    drawCjkCenteredAt(dc, "作钓时长", center, y - 14, MUTED);
    drawCjkCenteredAt(dc, "换饵提醒", right, y - 14, MUTED);
    drawCenteredAt(dc, summary["castCount"].toString(), left, y + 5, Graphics.FONT_MEDIUM, BOBBER);
    drawCenteredAt(dc, formatDuration(summary["durationSec"]), center, y + 7, Graphics.FONT_SMALL, FOAM);
    drawCenteredAt(dc, summary["baitReminderCount"].toString(), right, y + 5, Graphics.FONT_MEDIUM, BOBBER);
}

function drawSummaryFooter(dc, y) {
    var w = dc.getWidth();
    dc.setColor(WATER_LINE, Graphics.COLOR_TRANSPARENT);
    dc.drawLine(w * 0.20, y - 9, w * 0.80, y - 9);
    drawCjkCenteredAt(dc, "记录已保存", w * 0.37, y, FOAM);
    drawCjkCenteredAt(dc, "选择退出", w * 0.66, y, BOBBER);
}

function drawHook(dc, y, colour) {
    drawFishingLogoMark(dc, y);
}

function drawCastLine(dc, y) {
    drawFishingLogoMark(dc, y);
}

function drawFishingLogoMark(dc, y) {
    var x = dc.getWidth() / 2;
    // Reuse the launcher mark's vocabulary: bobber, line, hook and ripples.
    // Keeping this compact mark identical in spirit makes the confirmation
    // and message pages feel like part of the same product.
    dc.setColor(WATER_LINE, Graphics.COLOR_TRANSPARENT);
    dc.drawCircle(x, y, 25);
    dc.setColor(FOAM, Graphics.COLOR_TRANSPARENT);
    dc.drawLine(x - 5, y - 18, x - 5, y - 7);
    dc.setColor(BOBBER, Graphics.COLOR_TRANSPARENT);
    dc.fillCircle(x - 5, y - 1, 7);
    dc.setColor(WATER, WATER);
    dc.drawLine(x - 12, y - 1, x + 2, y - 1);
    dc.setColor(FOAM, Graphics.COLOR_TRANSPARENT);
    dc.drawLine(x + 12, y - 15, x + 12, y + 5);
    dc.drawCircle(x + 6, y + 6, 10);
    dc.drawLine(x + 10, y - 2, x + 18, y - 10);
    dc.setColor(WATER_LINE, Graphics.COLOR_TRANSPARENT);
    dc.drawLine(x - 16, y + 19, x + 16, y + 19);
    dc.drawLine(x - 10, y + 24, x + 10, y + 24);
}

function drawMenuRow(dc, y, key, label, colour) {
    var w = dc.getWidth();
    dc.setColor(WATER_LINE, Graphics.COLOR_TRANSPARENT);
    dc.drawLine(w * 0.12, y - 12, w * 0.88, y - 12);
    drawCjkLeftColor(dc, key, w * 0.14, y, MUTED);
    drawCjkRightColor(dc, label, w * 0.86, y, colour);
}

function drawActionBar(dc, text, colour) {
    var w = dc.getWidth();
    var h = dc.getHeight();
    dc.setColor(WATER_LINE, WATER_LINE);
    // Round displays lose usable width quickly near the lower edge.  Keep the
    // control inside the inscribed safe circle instead of the raw framebuffer.
    dc.fillRectangle(w * 0.15, h * 0.80, w * 0.70, h * 0.050);
    drawCjkCenteredColor(dc, text, h * 0.805, colour);
}

function drawCentered(dc, text, y, font) {
    drawCenteredColor(dc, text, y, font, MIST);
}

function drawCenteredColor(dc, text, y, font, colour) {
    dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
    dc.drawText(dc.getWidth() / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
}

function drawCenteredAt(dc, text, x, y, font, colour) {
    dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
    dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
}

var gCjkUiFont = null;

function drawCjkCentered(dc, text, y) { drawCjkCenteredColor(dc, text, y, MIST); }

function drawCjkCenteredColor(dc, text, y, colour) {
    if (gCjkUiFont == null) { gCjkUiFont = Application.loadResource(Rez.Fonts.CjkUi); }
    dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
    dc.drawText(dc.getWidth() / 2, y, gCjkUiFont, text, Graphics.TEXT_JUSTIFY_CENTER);
}

function drawCjkCenteredAt(dc, text, x, y, colour) {
    if (gCjkUiFont == null) { gCjkUiFont = Application.loadResource(Rez.Fonts.CjkUi); }
    dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
    dc.drawText(x, y, gCjkUiFont, text, Graphics.TEXT_JUSTIFY_CENTER);
}

function drawCjkLeftColor(dc, text, x, y, colour) {
    if (gCjkUiFont == null) { gCjkUiFont = Application.loadResource(Rez.Fonts.CjkUi); }
    dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
    dc.drawText(x, y, gCjkUiFont, text, Graphics.TEXT_JUSTIFY_LEFT);
}

function drawCjkRightColor(dc, text, x, y, colour) {
    if (gCjkUiFont == null) { gCjkUiFont = Application.loadResource(Rez.Fonts.CjkUi); }
    dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
    dc.drawText(x, y, gCjkUiFont, text, Graphics.TEXT_JUSTIFY_RIGHT);
}

function formatDuration(totalSeconds) {
    var seconds = totalSeconds;
    if (seconds < 0) { seconds = 0; }
    var minutes = seconds / 60;
    var remainder = seconds % 60;
    var hours = minutes / 60;
    minutes = minutes % 60;
    if (hours > 0) { return twoDigits(hours) + ":" + twoDigits(minutes) + ":" + twoDigits(remainder); }
    return twoDigits(minutes) + ":" + twoDigits(remainder);
}

function twoDigits(value) { return value < 10 ? "0" + value : value.toString(); }
