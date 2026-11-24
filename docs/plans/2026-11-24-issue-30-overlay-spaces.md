# Issue #30 取词结果窗跨桌面修复计划

## 目标与复现

在桌面 2 播放视频，进入并退出全屏，再切到桌面 1 按快捷键取词。修复后，桌面 1 应立即显示本次结果。两个桌面应能继续交替取词，整个过程中无需重启 SnapTra Translator。

在 `v1.3.11-beta.5`、公开 `main` 的 `50917d1` 和本地工作区上已复现。退出全屏前，隐藏的结果窗属于两个普通桌面和全屏 Space。退出后，它只属于视频所在的桌面 2。触发取词后，AppKit 将结果窗标为 `isVisible`，它仍未进入桌面 1。同时发现，模拟唤醒通知后立即取词，旧的延迟恢复任务会在约 0.8 秒时清掉新结果。

## 实施步骤

1. **验证窗口恢复方式。** 在临时测试宿主使用真实视频全屏和两个 macOS 桌面，记录退出前后的 `isOnActiveSpace` 和屏幕可见性。比较现有的前置操作与通过公开 AppKit API 重新建立桌面归属的效果。验证同一个窗口在修复后可以从两个桌面显示，且切换不会激活 SnapTra Translator。
2. **修复结果窗展示。** 在 `SnapTra Translator/OverlayWindowController.swift` 集中处理窗口排序和桌面归属。窗口不在当前 Space 时走恢复路径。保留原有的跨 Space 和全屏行为，以及窗口身份、OCR 截图排除、焦点请求和段落子窗挂接。检查 `SnapTra Translator/AppModel.swift` 中单词结果、段落结果和桌面切换入口，确保已排序但在别处的窗口也有机会恢复。
3. **保护唤醒后的新取词。** 审查 `AppModel` 的两种睡眠通知及三种恢复通知。让恢复任务能够区分需要清理的旧状态和恢复期间开始的取词，保留截图缓存及权限检查。用现有 XCTest target 覆盖连续通知及唤醒后新输入的时序。
4. **运行验证。** 先通过相关 XCTest 和构建，再运行下面的桌面矩阵。录像源和桌面诊断工具放在临时目录。记录实际屏幕上的结果、原面板是否复用及未覆盖的场景。

## 实际实施

### 结果窗跨桌面恢复

在 `SnapTra Translator/OverlayWindowController.swift` 集中实现窗口排序与 Space 归属恢复：

- `show()`、`reassertForActiveSpace()` 和已显示窗口的 `refreshLayoutIfNeeded()` 统一调用同一个恢复入口。
- 第一次按原配置设置 `.canJoinAllSpaces` 并置前，50 ms 后在主线程检查 `isOnActiveSpace`。
- 如果 AppKit 仍把窗口留在旧 Space，临时切换为 `.moveToActiveSpace`，让 WindowServer 重建关联，再在下一次主线程回调恢复全部 Space 配置。
- 恢复期间收到新的展示请求时只重复置前，不提前覆盖临时设置。
- 始终复用原 `NSPanel`，保留窗口编号、宿主视图、焦点请求、截图排除和段落单词子窗关系。

### 唤醒通知竞态

在 `SnapTra Translator/AppModel.swift` 调整睡眠和恢复处理：

- `sessionDidResignActiveNotification` 与睡眠通知共用现有停用清理。
- `didWake`、`screensDidWake` 和 `sessionDidBecomeActive` 共用一个可取消的 800 ms 恢复任务，后到的恢复通知会重排而不是叠加任务。
- 再次进入睡眠或会话停用时取消尚未执行的恢复任务。
- 恢复回调只重建快捷键监听并刷新权限，不再取消恢复期间刚开始的查询、隐藏结果窗或重置已经处理中的手势。

### 回归测试

在 `SnapTra TranslatorTests/SentenceReadingCardTests.swift` 新增唤醒通知与展示时序回归测试，验证新结果在旧恢复延迟点之后仍然显示。

## 验收矩阵

| 场景 | 通过条件 | 实际结果 |
| --- | --- | --- |
| 原生视频窗口全屏，退出后从桌面 2 切到桌面 1 | 桌面 1 显示 `orchard`。桌面 2 仍可显示 `lantern`，回到桌面 1 可再次取词 | 通过。两个往返轮次均复用同一面板，屏幕 OCR、窗口可见性和当前 Space 检查一致 |
| WKWebView 视频元素全屏 | 独立运行同样的桌面切换和取词流程，结果显示于当前桌面 | 通过。完整 HTML5 全屏矩阵覆盖全屏中取词及退出后的双桌面往返 |
| 隐藏窗口首次展示，及已显示结果窗更新 | 窗口位于当前 Space。渲染结果与该桌面的 OCR 来源一致 | 通过。首次展示和已显示窗口更新都完成当前 Space 与 backing readback 校验 |
| 长按和点按保留 | 长按后松开可关闭。点按结果可以保留，后续取词继续显示在当前桌面 | 通过。长按、点击保留和 wake 后下一次取词均正常 |
| 段落结果和其单词子窗 | 原有交互与亲子窗口的排序继续有效 | 通过。阅读卡片中查词、翻译保留及按顺序关闭的回归测试通过 |
| 合成唤醒通知与新取词重叠 | 首次唤醒后取词在原延迟时间点之后仍可见。后续快捷键正常 | 通过。通知后立即取词在 1.2 秒检查时仍为结果态，迟到通知未清空结果，后续取词正常 |
| 常规构建 | App Store 和 Direct scheme 可编译 | 通过。`SnapTra Translator` Debug 测试构建和 `SnapTra Translator Direct` Debug 构建均成功 |

## 验证记录

- `SentenceReadingCardTests` 的新增唤醒回归测试通过。
- `ParagraphOverlayLayoutTests`、`CaptureExclusionRegistryTests` 和 `HotkeyManagerTests` 共 88 个测试通过。
- 阅读卡片查词及父子窗口回归测试通过。
- 原生 `AVPlayerView` 全屏矩阵的核心跨桌面验证通过。复跑中，最终从桌面 2 返回桌面 1 的取词已首次成功。两次矩阵里各出现过一次合成快捷键没有启动新查询的等待，重试或另一轮即恢复，没有再次出现结果窗留在旧桌面的现象；这项输入注入时序仍可在后续自动化中单独消除。
- WKWebView HTML5 视频全屏矩阵通过，结果 JSON 无 `missing`、`could not verify`、`invalid lookup` 或 `scenario stopped`。
- 合成睡眠/唤醒矩阵通过。最后一次从桌面 2 返回桌面 1 时出现一次 UI 等待重试，第二次立即取词成功，面板编号继续复用。
- 实际合盖、隔夜睡眠和真实系统唤醒后的恢复仍需要在发布前用实体设备补测。50 ms 的窗口校验点和 800 ms 的唤醒恢复点都不是 AppKit 的公开时序保证，本次通过的是 AppKit 通知与双 Space 的合成矩阵。

常规验证命令

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" \
  -destination "platform=macOS,arch=arm64" -configuration Debug \
  -parallel-testing-enabled NO test
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator Direct" \
  -destination "platform=macOS,arch=arm64" -configuration Debug build
```
