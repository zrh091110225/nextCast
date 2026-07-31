# CastTimer

Garmin Connect IQ Device App：在受支持的守钓场景中识别抛竿，并在换饵间隔到点时提醒用户。

当前代码实现了 PRD 的 Phase 0/MVP 工程骨架：会话状态机、绝对时间倒计时、震动提醒、手动补记与撤销、状态持久化、FIT Fishing 会话以及高频加速度规则检测器。

## 开发前提

- Connect IQ SDK 9.2.0；
- 首轮实机：fēnix 7、Forerunner 255、Venu 3；
- 真实抛竿数据与视频标注。

## 构建

SDK 已安装在 `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2`。用 VS Code 的 Monkey C 扩展打开此目录，选择目标设备后执行构建和模拟器运行。

当前 macOS 环境中的 Java 26 需要以下临时参数才能让编译器以无界面、保守 JIT 模式运行：

```sh
SDK_BIN="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2/bin"
JAVA_TOOL_OPTIONS='-Djava.awt.headless=true -XX:TieredStopAtLevel=1' "$SDK_BIN/monkeyc" \
  -d fenix7 -f monkey.jungle -o bin/CastTimer-fenix7.prg \
  -y .keys/developer_key.der -w
```

已在 `fenix7`、`fr255` 和 `venu3` 上通过编译。Instinct 2 仅支持 Connect IQ API 3.4，而项目最低要求为 4.2，已确认不纳入首发支持范围。

## 关键限制

- 到点震动仅在应用保持 active 时承诺；切换到其他应用后恢复时只做超时状态对账。
- `CastDetector` 使用保守的 Phase 0 规则阈值，不能视为已达成 PRD 的 Precision/Recall 门槛。
- 异常恢复会恢复倒计时和统计，但不会自动重接不持久化的活动 Session；恢复后的会话显式降级为手动计时，直到 WP0 验证可安全重连的方案。
- ActivityRecording 的冲突与 Session 所有权仍是 WP0 真机阻断项；检测到录制中的既有 Session 时会安全拒绝开始。
