# Hotkey Word Lookup P0 Performance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在不改变真实选区优先、OCR 精度、面板交互和发音 provider 语义的前提下，显著缩短单击快捷键到单词面板首次呈现及发音启动的时间，并消除旧 TTS 请求和 Learning 持久化对热路径的干扰。

**Architecture:** 先用同一个 `lookupID` 建立可复现的 Release 基线，再依次优化 Direct 版的选区路由、ScreenCaptureKit 元数据获取、TTS 请求生命周期和 Learning 写入。路由使用冻结的鼠标上下文与 selection-first 协调器；截图缓存以 overlay registry generation 和显式失效 epoch 保证正确性；语音使用 request generation 隔离陈旧完成；Learning 将每次查词的持久化工作约束为一次 lookup save 和至多一次 definition save。

**Tech Stack:** Swift 6、SwiftUI、AppKit、AXUIElement、ScreenCaptureKit、Vision、AVFoundation、SwiftData、`OSSignposter`/`Logger`、XCTest、macOS 14+。

---

## 1. 当前链路与 P0 判断

当前单击路径如下：

```text
HotkeyManager
  -> AppModel @MainActor
  -> Direct: 同步 AX 候选/属性遍历
  -> Direct uncertain: Cmd+C + 最长 150ms clipboard wait
  -> SCShareableContent 全量枚举
  -> SCScreenshotManager
  -> Vision accurate OCR
  -> 选中光标下单词
  -> 发起 TTS
  -> overlayState 发布并 orderFront
  -> Learning record + 多次 definition fetch/save
```

重新复核后的 P0 共五组：

1. **端到端埋点与 Release 基线**：否则只能看到“感觉更快”，无法判断收益来自 AX、截图、OCR、面板还是 TTS。
2. **Direct selected-text 串行成本**：AX 当前在 `MainActor` 同步执行，并且对每个候选预先读取 direct/range/marker/attributed/bounds；无选区时还会串行等待 clipboard，再开始截图和 OCR。
3. **ScreenCaptureKit metadata cache**：`cachedExcludedWindows` 每次 capture 都会重建，`SCShareableContent` 实际没有缓存。
4. **TTS 请求生命周期**：线上 `Task` 没有持有；一个全局 `isCancelled` 会被新请求重置，旧请求可能迟到播放或触发 Apple fallback。
5. **Learning 热路径**：`recordLookup` 每次 save 后全量读取全部 `WordRecord`；一个 lookup 的主翻译和多个词典结果还会各自 fetch/save definition。

### 必须保持的行为不变量

- 已知 `selectedRange` 的真实 AX 选区继续优先，即使没有可信 bounds。
- clipboard 只有在 simulated Cmd+C 后 `pasteboard.changeCount` 变化时才算新选区；旧剪贴板永远不能劫持 OCR 查词。
- speculative OCR 可以提前计算，但在 AX/clipboard 仲裁结束前不得展示结果。
- App Store channel 不执行 AX 或 clipboard fallback。
- OCR 继续使用当前 `.accurate` 语义；不能为速度全局切回 `.fast`。
- 缓存后仍只排除已注册的 SnapTra overlay；Settings 等普通本应用窗口仍可被 OCR 捕获。
- 新发音、`stopSpeaking()`、lookup 取消和 overlay dismiss 都必须让旧线上请求失效；取消不能触发 Apple fallback。
- 每次有效 lookup 仍记录 lookup count；完整 matching-record export 语义不变。
- 新增的 `LookupPerformance` logger/signpost 不记录原文、definition、坐标、URL、token 或凭证。

### 本轮明确不做

- OCR frame reuse、全局 `.fast`/自适应 recognition level、Vision 模型重构。
- TTS 音频 LRU/cache、流式/分片播放、provider 替换。
- overlay 视图树常驻或启动时预热。
- SwiftData schema 迁移、ModelActor 大改、合并 AppModel 与 Learning 页的两个 `LearningService` 实例。
- 双击句子、手动区域、图片翻译等非单击查词路径的性能改造。
- 新增第三方依赖。

## 2. 交付顺序与性能门槛

严格按下面顺序合并，避免优化后才补基线：

```text
埋点 -> before baseline
     -> 冻结 lookup 上下文
     -> AX 分阶段执行
     -> overlay generation + capture cache
     -> clipboard / OCR 并行协调
     -> TTS generation + 真取消
     -> Learning bounded writes
     -> after comparison
```

统一样本矩阵：

- Channel：`SnapTra Translator`、`SnapTra Translator Direct`。
- Route：App Store OCR、Direct OCR/no-selection、Direct AX selection、Direct fresh clipboard fallback。
- 温度：cold 每格至少 5 次；warm 预热 3 次后至少 20 次。
- Learning 数据量：0、100、5,000。
- TTS：Apple + 一个 HTTP provider + Bing/Edge WebSocket。
- 同一机器、显示缩放、语言对、词典来源、测试文本和网络条件；before/after 使用同一套 fixture。

核心指标：

| 指标 | 定义 | P0 门槛 |
| --- | --- | --- |
| lookup -> panel | `handleHotkeyTrigger` 接受请求到首次 `orderFrontRegardless()` 返回；已显示面板另记 `OverlayStatePublished` | Direct OCR warm P50 至少降低 25%，P95 至少降低 20%；App Store OCR warm P95 至少降低 10% |
| AX probe | AX 开始到 selection snapshot/rejection | TextEdit/Notes known-range P95 <= 120ms soft budget；主线程不再出现 AX 阻塞 |
| capture metadata | 请求 metadata 到得到 display/windows | 同 generation 连续 20 次只调用一次 loader |
| TTS TTFS proxy | `speak()` 到 Apple `didStart`，或在线 `play()==true && isPlaying` | `fetch_end_to_play` Release P95 <= 50ms；旧请求播放/回退为 0 |
| Learning record | lookup record 开始到 save 完成 | 5,000 vs 100 条 P50 比值 <= 1.25，P95 增量 <= 5ms |
| instrumentation overhead | 同 fixture 埋点前后 lookup -> panel | P95 回归不超过 5% |

若某个绝对阈值受机器噪声影响，以同机 before/after 为主；任何 route 的 P95 不得回归超过 5%，否则不能以“平均更快”通过验收。

---

### Task 1: 建立可关联、无敏感数据的 lookup 性能记录器

**Files:**

- Create: `SnapTra Translator/LookupPerformance.swift`
- Create: `SnapTra TranslatorTests/LookupPerformanceTests.swift`
- Modify: `SnapTra Translator.xcodeproj/project.pbxproj`

**Step 1: 写失败测试**

新增以下契约测试：

```swift
func testFirstMilestoneForSameLookupIsRecordedOnlyOnce()
func testCancelledLookupClosesOpenPresentationIntervalOnce()
func testDifferentLookupIDsKeepIndependentSignpostState()
func testMonotonicClockProducesStageDurations()
func testReporterAPIHasNoSourceTextOrCoordinateFields()
```

测试使用 injected monotonic clock 和 event sink；不要断言系统 Instruments 的内部实现。

**Step 2: 运行测试确认红灯**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -only-testing:'SnapTra TranslatorTests/LookupPerformanceTests' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: 因 `LookupPerformanceReporter`、trace/stage 类型尚不存在而编译失败。

**Step 3: 实现最小 API**

API 边界固定为：

```swift
enum LookupPerformanceRoute: String, Sendable {
    case appStoreOCR
    case directOCR
    case accessibilitySelection
    case clipboardSelection
}

enum LookupPerformanceStage: String, Sendable {
    case routeResolution
    case accessibilityProbe
    case clipboardFallback
    case captureMetadata
    case screenshot
    case ocr
    case panelPresentation
    case translationFirstReady
    case dictionaryFirstReady
    case learningRecord
    case learningDefinition
    case ttsFetch
    case ttsStart
}

enum LookupPerformanceOutcome: String, Sendable {
    case succeeded
    case cancelled
    case superseded
    case failed
    case cacheHit
    case cacheMiss
}

struct LookupPerformanceTrace: Hashable, Sendable {
    let lookupID: UUID
}

protocol LookupPerformanceReporting: Sendable {
    func beginLookup(_ trace: LookupPerformanceTrace)
    func begin(_ stage: LookupPerformanceStage, trace: LookupPerformanceTrace)
    func end(
        _ stage: LookupPerformanceStage,
        trace: LookupPerformanceTrace,
        outcome: LookupPerformanceOutcome
    )
    func mark(_ stage: LookupPerformanceStage, trace: LookupPerformanceTrace)
    func finishLookup(_ trace: LookupPerformanceTrace, outcome: LookupPerformanceOutcome)
}
```

生产实现内部使用一个 category 为 `LookupPerformance` 的 `Logger` 和 `OSSignposter`。相同 lookup/stage 的 first milestone 只接受一次；取消/失败必须关闭尚未结束的 lookup-to-first-presentation interval。只允许 metadata：lookupID、route、channel、cold/warm、provider、计数 bucket、duration 和 outcome。

**Step 4: 运行测试确认绿灯**

重复 Step 2。Expected: `LookupPerformanceTests` 全部通过。

**Step 5: 提交**

```bash
git add 'SnapTra Translator/LookupPerformance.swift' \
  'SnapTra TranslatorTests/LookupPerformanceTests.swift' \
  'SnapTra Translator.xcodeproj/project.pbxproj'
git commit -m "perf(metrics): add correlated lookup traces"
```

---

### Task 2: 接入单击查词阶段并记录 before baseline

**Files:**

- Modify: `SnapTra Translator/AppModel.swift`
- Modify: `SnapTra Translator/OverlayWindowController.swift`
- Modify: `SnapTra Translator/SelectedTextService.swift`
- Modify: `SnapTra Translator/ScreenCaptureService.swift`
- Modify: `SnapTra Translator/SpeechService.swift`
- Create: `scripts/performance/capture-lookup-trace.sh`
- Create: `docs/performance/hotkey-word-lookup-p0-results.md`
- Test: `SnapTra TranslatorTests/LookupPerformanceTests.swift`

**Step 1: 扩展失败测试**

覆盖以下事件语义：

- lookup 接受时 begin，superseded/cancel 时只 finish 一次。
- 新 panel 在 `orderFrontRegardless()` 返回后记录 `panelPresentation`。
- 已显示 panel 的内容更新只记 state publication，不伪造第二个 order-front。
- capture/OCR/learning/TTS 的 stage 使用相同 `lookupID`。
- reporter 不接收原文和坐标。

**Step 2: 接入最小埋点**

- `AppModel.startLookup` 创建业务 `lookupID` 时同时创建 trace；只覆盖 single-press word/selected-text route。
- `performLookup` 记录 route、AX、clipboard、capture、OCR 和 content resolved。
- `updateOverlay` 在 state 发布后记录 publication；`OverlayWindowController.show` 在真正 order-front 后回调 presentation。
- `SpeechService.speak` 增加默认值为 `nil` 的 performance trace 参数；当前 task 只给 word lookup 传入。
- `LearningService` 的 record/updateDefinition 由调用方包围 stage；本 task 不改变数据行为。
- 结束/取消时先 finish trace，再清 `activeLookupID`。

**Step 3: 添加采集脚本并校验语法**

先创建专用目录：

```bash
mkdir -p scripts/performance docs/performance
```

脚本接受 `<output.trace> [duration]`，attach 当前 `SnapTra Translator` 进程：

```bash
xcrun xctrace record \
  --template Logging \
  --instrument 'Points of Interest' \
  --instrument os_signpost \
  --attach 'SnapTra Translator' \
  --time-limit "${duration:-60s}" \
  --output "$output"
```

运行：

```bash
bash -n scripts/performance/capture-lookup-trace.sh
```

Expected: exit 0。

**Step 4: 记录优化前 Release 基线**

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" -configuration Release \
  -derivedDataPath /tmp/snaptra-p0-before-appstore \
  build CODE_SIGNING_ALLOWED=NO

xcodebuild -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator Direct" -configuration Release \
  -derivedDataPath /tmp/snaptra-p0-before-direct \
  build CODE_SIGNING_ALLOWED=NO
```

按第 2 节矩阵采集，结果表必须记录机器、系统、显示缩放、build commit、样本数、P50、P95 和 trace 文件路径。Direct selected-text 单列，不与 App Store OCR 混算。

**Step 5: 验证与提交**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -only-testing:'SnapTra TranslatorTests/LookupPerformanceTests' \
  CODE_SIGNING_ALLOWED=NO
```

```bash
git add 'SnapTra Translator/AppModel.swift' \
  'SnapTra Translator/OverlayWindowController.swift' \
  'SnapTra Translator/SelectedTextService.swift' \
  'SnapTra Translator/ScreenCaptureService.swift' \
  'SnapTra Translator/SpeechService.swift' \
  scripts/performance/capture-lookup-trace.sh \
  docs/performance/hotkey-word-lookup-p0-results.md
git commit -m "perf(metrics): instrument word lookup stages"
```

---

### Task 3: 冻结一次 lookup 的鼠标和 capability 上下文

**Files:**

- Create: `SnapTra Translator/SinglePressLookupCoordinator.swift`
- Modify: `SnapTra Translator/AppModel.swift`
- Create: `SnapTra TranslatorTests/SelectedTextPerformanceTests.swift`
- Modify: `SnapTra Translator.xcodeproj/project.pbxproj`

**Step 1: 写失败测试**

```swift
func testRequestKeepsTriggerPointWhenGlobalMouseMovesLater()
func testContinuousLookupCreatesANewFrozenPointPerMovement()
func testUnsupportedChannelUsesOCROnlyPolicy()
func testOCRPolicyNeverInvokesAccessibilityOrClipboard()
```

建议的纯值类型：

```swift
struct SinglePressLookupRequest: Sendable {
    let lookupID: UUID
    let mouseLocation: CGPoint
    let supportsSelectedText: Bool
    let selectedTextEnabled: Bool
    let clipboardFallbackEnabled: Bool
    let hasAccessibilityPermission: Bool
}

enum SinglePressLookupExecutionPolicy: Equatable, Sendable {
    case ocrOnly
    case selectionFirst(allowsClipboardFallback: Bool)
}
```

**Step 2: 运行红灯测试**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -only-testing:'SnapTra TranslatorTests/SinglePressLookupRequestTests' \
  CODE_SIGNING_ALLOWED=NO
```

**Step 3: 实现冻结输入**

- 改为 `startLookup(at mouseLocation: CGPoint)`。
- `handleHotkeyTrigger` 只读取一次 `NSEvent.mouseLocation`，用于 overlay anchor、request 和 capture。
- `handleMouseMoved` 每次 debounce 命中后读取一次位置并建立新 request。
- `performLookup(request:)` 禁止再次读取全局鼠标位置。
- `ScreenCaptureService` 后续接收同一个 frozen point，确保截图 region 与 OCR hit-test point 一致。

**Step 4: 运行绿灯测试并回归路由测试**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -only-testing:'SnapTra TranslatorTests/SinglePressLookupRequestTests' \
  -only-testing:'SnapTra TranslatorTests/SelectedTextLookupRoutingTests' \
  CODE_SIGNING_ALLOWED=NO
```

**Step 5: 提交**

```bash
git add 'SnapTra Translator/SinglePressLookupCoordinator.swift' \
  'SnapTra Translator/AppModel.swift' \
  'SnapTra TranslatorTests/SelectedTextPerformanceTests.swift' \
  'SnapTra Translator.xcodeproj/project.pbxproj'
git commit -m "fix(lookup): freeze single press context"
```

---

### Task 4: 将 AX 探测移出 MainActor，并按成本分阶段短路

**Files:**

- Create: `SnapTra Translator/SelectedTextProbeExecutor.swift`
- Modify: `SnapTra Translator/SelectedTextService.swift`
- Modify: `SnapTra Translator/LookupIntent.swift` only if signatures need adapting; do not change router semantics
- Test: `SnapTra TranslatorTests/SelectedTextPerformanceTests.swift`
- Test: `SnapTra TranslatorTests/SettingsStoreTests.swift`

**Step 1: 写 probe policy 和 executor 红灯测试**

```swift
func testKnownRangeFastPathDoesNotReadMarkerAttributedOrBounds()
func testRangeStringSuccessDoesNotEnterMarkerPhase()
func testMarkerStringSuccessDoesNotReadAttributedString()
func testUnknownRangeReadsBoundsForGeometryConfidence()
func testFirstHoveredCandidateSuccessDoesNotEnumerateFocusedCandidates()
func testConcurrentProbesRunWithMaximumConcurrencyOfOne()
func testProbeWorkDoesNotRunOnMainThread()
func testSoftBudgetDoesNotChangeSelectionResult()
func testDisabledDiagnosticsDoesNotEvaluateMessageAutoclosure()
```

**Step 2: 运行测试确认红灯**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -only-testing:'SnapTra TranslatorTests/SelectedTextProbePolicyTests' \
  -only-testing:'SnapTra TranslatorTests/SelectedTextProbeExecutorTests' \
  CODE_SIGNING_ALLOWED=NO
```

**Step 3: 实现明确的探测顺序**

顺序必须是：

1. 惰性取得当前 hovered candidate，不预先构造所有 parent/focused/system-wide chain。
2. 读取 `AXSelectedText` 与 `AXSelectedTextRange`。
3. direct text + known range 立即返回，不读 marker、attributed、bounds。
4. direct text 缺失但 range 已知，只读 `AXStringForRange`；成功立即返回。
5. 再读 text marker range 和 marker string。
6. marker string 缺失才读 attributed string。
7. 只有 unknown range 才补 bounds，供现有 geometry confidence 使用。
8. 当前 candidate 失败才生成下一个 candidate/parent。

`SelectedTextProbeExecutor` 使用 private user-initiated serial queue；每个 phase/candidate 前检查 cancellation。同步 AX IPC 本身不可强制中断，因此单次调用返回后必须立即停止后续 phase。

在 MainActor 只捕获可发送的上下文：mouse point、frontmost PID/bundle ID 和屏幕坐标转换参数；executor 内再创建 AX application/system-wide element。将 `clipboardFallbackEnabled` 从 mutable service property 改为 request 参数，避免跨执行器可变状态。

将 debug helper 改为 `@autoclosure` 或用 `#if DEBUG` 包住 call site，确保 Release 不再为了被丢弃的日志执行 `debugSummary` 的多个 AX IPC。

保留现有 1.5 秒 AX messaging timeout；新增 120ms soft budget 只用于 metrics，不得因超限强制 OCR。先用数据决定后续是否降低 timeout。

**Step 4: 验证全部 AX/路由回归**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -only-testing:'SnapTra TranslatorTests/SelectedTextProbePolicyTests' \
  -only-testing:'SnapTra TranslatorTests/SelectedTextProbeExecutorTests' \
  -only-testing:'SnapTra TranslatorTests/SelectedTextLookupRoutingTests' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: known-range/no-bounds、unknown-range fallback、clipboard freshness 全部保持。

**Step 5: 提交**

```bash
git add 'SnapTra Translator/SelectedTextProbeExecutor.swift' \
  'SnapTra Translator/SelectedTextService.swift' \
  'SnapTra Translator/LookupIntent.swift' \
  'SnapTra TranslatorTests/SelectedTextPerformanceTests.swift' \
  'SnapTra TranslatorTests/SettingsStoreTests.swift'
git commit -m "perf(selected-text): short-circuit accessibility probes"
```

---

### Task 5: 给 overlay exclusion 增加 generation 快照

**Files:**

- Modify: `SnapTra Translator/CaptureExclusionRegistry.swift`
- Modify: `SnapTra TranslatorTests/CaptureExclusionRegistryTests.swift`

**Step 1: 写失败测试**

```swift
func testRegisteringNewWindowNumberAdvancesGeneration()
func testRegisteringSameWindowNumberDoesNotAdvanceGeneration()
func testSnapshotReturnsGenerationAndWindowNumbersAtomically()
func testInvalidWindowNumberDoesNotAdvanceGeneration()
func testOnlyRegisteredWindowsRemainExcluded()
```

**Step 2: 运行红灯测试**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -only-testing:'SnapTra TranslatorTests/CaptureExclusionRegistryTests' \
  CODE_SIGNING_ALLOWED=NO
```

**Step 3: 实现最小 generation 模型**

```swift
struct CaptureExclusionSnapshot: Equatable, Sendable {
    let generation: UInt64
    let windowNumbers: Set<Int>
}
```

- registry 只在 `Set.insert(...).inserted == true` 时 `generation &+= 1`。
- 提供一次性 `snapshot()`，不要分开读 generation 和 numbers。
- 保留 `register(_ window: NSWindow)` 生产 API；增加 internal `register(windowNumber:)` 供纯测试复用。
- 不用时间戳和 TTL。

**Step 4: 运行绿灯测试**

重复 Step 2。Expected: 新旧 exclusion tests 全部通过。

**Step 5: 提交**

```bash
git add 'SnapTra Translator/CaptureExclusionRegistry.swift' \
  'SnapTra TranslatorTests/CaptureExclusionRegistryTests.swift'
git commit -m "refactor(capture): version overlay exclusions"
```

---

### Task 6: 缓存全部 ScreenCaptureKit metadata，并建立正确失效边界

**Files:**

- Create: `SnapTra Translator/ScreenCaptureContentCache.swift`
- Modify: `SnapTra Translator/ScreenCaptureService.swift`
- Modify: `SnapTra Translator/AppModel.swift`
- Test: `SnapTra TranslatorTests/CaptureExclusionRegistryTests.swift`

**Step 1: 写 async cache 红灯测试**

```swift
func testSameKeySequentialRequestsLoadOnce()
func testSameKeyConcurrentRequestsShareOneLoad()
func testRegistryGenerationChangeReloadsOnce()
func testExplicitInvalidationEpochReloadsOnce()
func testStaleInFlightValueCannotReplaceNewGeneration()
func testMissingDisplayForcesExactlyOneRefresh()
func testMetadataSnapshotCanResolveTwoDisplayIDs()
```

cache key 固定为：

```swift
struct ScreenCaptureCacheKey: Equatable, Sendable {
    let exclusionGeneration: UInt64
    let explicitInvalidationEpoch: UInt64
}
```

**Step 2: 运行红灯测试**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -only-testing:'SnapTra TranslatorTests/ScreenCaptureContentCacheTests' \
  CODE_SIGNING_ALLOWED=NO
```

**Step 3: 实现 cache 和 loader**

- 一个 metadata snapshot 同时缓存全部 `SCDisplay` 和全部 `SCWindow`；每次 capture 仍创建轻量 `SCContentFilter`。
- loader 必须使用：

```swift
try await SCShareableContent.excludingDesktopWindows(
    false,
    onScreenWindowsOnly: false
)
```

`onScreenWindowsOnly: false` 是正确性要求：overlay 通常在隐藏时初始化/注册；若首次 cache 只含 onscreen windows，稍后 `orderFront` 后该 panel 不在 exclusion 中，会重新截到自身。

- 用 registry numbers 从 metadata 中筛选 excluded windows；未注册的同 app Settings window 不排除。
- `invalidateCache()` 增加 explicit epoch 并清理 reusable entry/in-flight state。
- `prepareForSystemSleep`、wake recovery、`NSApplication.didChangeScreenParametersNotification` 都显式 invalidate。
- display 缺失或确定的 stale-source 错误只允许强刷一次；失败不缓存，禁止循环 retry。
- 在 reporter 中记录 cache hit/miss 和 loader duration。

**Step 4: 运行 cache/exclusion 测试并构建两个渠道**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -only-testing:'SnapTra TranslatorTests/CaptureExclusionRegistryTests' \
  CODE_SIGNING_ALLOWED=NO

xcodebuild -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator Direct" -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO
```

**Step 5: 提交**

```bash
git add 'SnapTra Translator/ScreenCaptureContentCache.swift' \
  'SnapTra Translator/ScreenCaptureService.swift' \
  'SnapTra Translator/AppModel.swift' \
  'SnapTra TranslatorTests/CaptureExclusionRegistryTests.swift'
git commit -m "perf(capture): cache shareable content metadata"
```

---

### Task 7: 在 AX 不确定时并行 clipboard 与 OCR candidate，但保持 selection-first

**Files:**

- Modify: `SnapTra Translator/SinglePressLookupCoordinator.swift`
- Modify: `SnapTra Translator/AppModel.swift`
- Modify: `SnapTra Translator/ScreenCaptureService.swift`
- Modify: `SnapTra Translator/OCRService.swift` only if a cancellation check seam is required
- Test: `SnapTra TranslatorTests/SelectedTextPerformanceTests.swift`
- Test: `SnapTra TranslatorTests/SettingsStoreTests.swift`

**Step 1: 用可控 continuation 写并发顺序红灯测试**

```swift
func testKnownAXSelectionDoesNotStartOCRCandidate()
func testFreshClipboardWinsEvenWhenOCRFinishesFirst()
func testUnchangedClipboardConsumesPrefetchedOCRCandidate()
func testAppStorePathDoesNotInvokeAXOrClipboard()
func testSupersededLookupCannotCommitLateOCRResult()
func testAllDependenciesReceiveTheFrozenMousePoint()
```

**Step 2: 运行红灯测试**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -only-testing:'SnapTra TranslatorTests/SinglePressLookupCoordinatorTests' \
  CODE_SIGNING_ALLOWED=NO
```

**Step 3: 拆分 OCR 计算与 UI 提交**

- 将 `performOcrWordLookup` 拆成 `loadOcrWordCandidate(request:) async` 和 `presentOcrWordCandidate(...)`。
- candidate 包含 capture region、recognized words/selected word、语言对所需输入和 error outcome；计算阶段不修改 overlayState、不复制文本、不播放、不写 Learning。
- `captureAroundCursor(at frozenPoint:)` 和 hit-test 都使用 request 的同一个 point。
- 每次 capture、Vision 完成及提交前检查 task cancellation 和 active lookupID。

**Step 4: 实现仲裁时序**

```text
App Store -> 直接 await OCR candidate -> 提交

Direct -> await staged AX
  AX accepted -> selected-text，OCR 调用次数 0
  AX uncertain + clipboard enabled -> 同时启动 clipboard 与 OCR candidate
      fresh clipboard -> selected-text；cancel/discard OCR
      stale/empty clipboard -> await/reuse OCR candidate；提交 OCR
  AX rejected + no clipboard -> 直接 OCR candidate
```

即使 OCR 先完成，也必须等 clipboard freshness 仲裁结束。取消无法中断的 AX/Vision 单次系统调用时，至少要阻止后续 phase 和所有旧 UI/audio/Learning side effect。

**Step 5: 验证并提交**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -only-testing:'SnapTra TranslatorTests/SinglePressLookupCoordinatorTests' \
  -only-testing:'SnapTra TranslatorTests/SelectedTextLookupRoutingTests' \
  -only-testing:'SnapTra TranslatorTests/CaptureExclusionRegistryTests' \
  CODE_SIGNING_ALLOWED=NO
```

```bash
git add 'SnapTra Translator/SinglePressLookupCoordinator.swift' \
  'SnapTra Translator/AppModel.swift' \
  'SnapTra Translator/ScreenCaptureService.swift' \
  'SnapTra Translator/OCRService.swift' \
  'SnapTra TranslatorTests/SelectedTextPerformanceTests.swift' \
  'SnapTra TranslatorTests/SettingsStoreTests.swift'
git commit -m "perf(lookup): overlap OCR with clipboard fallback"
```

---

### Task 8: 用 active task + request generation 隔离 TTS 陈旧完成

**Files:**

- Modify: `SnapTra Translator/SpeechService.swift`
- Create: `SnapTra TranslatorTests/SpeechServiceTests.swift`
- Modify: `SnapTra Translator.xcodeproj/project.pbxproj`

**Step 1: 先建立高层测试 seam**

仅增加两个主流程协议：

```swift
@MainActor
protocol TTSServiceFetching: AnyObject {
    func fetchAudio(
        text: String,
        language: String?,
        provider: TTSProvider,
        useAmericanAccent: Bool,
        disableCache: Bool
    ) async throws -> Data
}

@MainActor
protocol SpeechAudioOutput: AnyObject {
    func stop()
    func playApple(text: String, language: String?)
    func playOnlineAudio(_ data: Data) throws -> Bool
}
```

`TTSServiceFactory` 与 AVFoundation adapter 分别实现；测试使用 controlled fetcher 和 output spy，不 mock `AVAudioPlayer` 本体。

**Step 2: 写请求竞态红灯测试**

```swift
func testCurrentOnlineSuccessPlaysReturnedAudioOnly()
func testCurrentOnlineFailureFallsBackToAppleOnce()
func testSecondSpeakCancelsFirstFetchTask()
func testStopSpeakingCancelsActiveFetchTask()
func testStaleSuccessCannotPlay()
func testStaleErrorCannotFallbackToApple()
func testAppleRequestInvalidatesOlderOnlineRequest()
func testOldCompletionCannotClearNewerActiveTask()
```

最后一项序列：A -> B -> 让忽略取消的 A 完成 -> stop；断言 B 仍收到 cancel。

**Step 3: 运行红灯测试**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -only-testing:'SnapTra TranslatorTests/SpeechServiceTests' \
  CODE_SIGNING_ALLOWED=NO
```

**Step 4: 实现生命周期状态机**

```swift
private var activeTask: Task<Void, Never>?
private var requestGeneration: UInt64 = 0
```

每次 `speak`/`stopSpeaking`：先递增 generation，再清理并 cancel 旧 task，然后停止 Apple/online output。新线上 task 捕获 generation；fetch success、player create/play、任何 Apple fallback 和 debug side effect 前同时检查 `Task.isCancelled` 与 generation。旧 task 的 completion 只有 token 仍匹配时才能把 `activeTask` 置 nil。

删除全局 `isCancelled`。当前请求的真实错误仍 fallback Apple；`CancellationError`、`URLError.cancelled` 或 generation 不匹配必须静默退出。

**Step 5: 运行绿灯测试并提交**

```bash
git add 'SnapTra Translator/SpeechService.swift' \
  'SnapTra TranslatorTests/SpeechServiceTests.swift' \
  'SnapTra Translator.xcodeproj/project.pbxproj'
git commit -m "fix(tts): guard playback with request generations"
```

---

### Task 9: 让 HTTP 与 Bing/Edge WebSocket 真正响应取消

**Files:**

- Modify: `SnapTra Translator/SpeechService.swift`
- Test: `SnapTra TranslatorTests/SpeechServiceTests.swift`

**Step 1: 写 HTTP cancellation 红灯测试**

为测试 URLSession 配置悬挂型 `CancellationObservingURLProtocol`：

```swift
func testYoudaoCancellationCallsURLProtocolStopLoading()
func testBaiduCancellationCallsURLProtocolStopLoading()
func testGoogleCancellationCallsURLProtocolStopLoading()
func testStoppedHTTPRequestNeverFallsBackToApple()
```

测试先等待 `startLoading()`，再 cancel，接受 `CancellationError` 或 `URLError.cancelled`，但必须观察到 `stopLoading()`。

**Step 2: 注入 URLSession 并跑绿灯**

给 Youdao/Baidu/Google 增加：

```swift
init(
    session: URLSession = .shared,
    uncachedSession: URLSession = SharedURLSession.uncached
)
```

保留 URL、header 与 `disableCache` 语义，不重写系统 async bridge。

**Step 3: 写 Edge cancellation 红灯测试**

```swift
func testCancellingEdgeFetchCancelsSocketAndUnblocksReceive()
func testEdgeTimeoutCancelsSocketBeforeThrowing()
func testStoppingBingSpeechCancelsSocketWithoutFallback()
func testSuccessfulEdgeFetchClosesSocket()
```

增加窄 seam：

```swift
protocol TTSWebSocketTasking: AnyObject, Sendable {
    func resume()
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

protocol TTSWebSocketTaskCreating: Sendable {
    func makeTask(for request: URLRequest) -> any TTSWebSocketTasking
}
```

**Step 4: 实现 Edge 真取消**

- 用 `withTaskCancellationHandler` 包围完整 WebSocket 操作；`onCancel` 立即 socket.cancel。
- timeout 分支抛错前也主动 cancel socket；不能只 `group.cancelAll()` 后等待挂起的 receive。
- success/error defer 关闭 socket。
- `BingTTSService` 持有可注入的 Edge service，不再每次临时 new。
- 默认 MainActor isolation 下，adapter 的 send/receive/cancel 要明确正确隔离并用线程安全 fake 验证。

**Step 5: 验证并提交**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -only-testing:'SnapTra TranslatorTests/SpeechServiceTests' \
  CODE_SIGNING_ALLOWED=NO
```

```bash
git add 'SnapTra Translator/SpeechService.swift' \
  'SnapTra TranslatorTests/SpeechServiceTests.swift'
git commit -m "fix(tts): cancel active HTTP and WebSocket requests"
```

---

### Task 10: 将 debug 音频写盘移出 TTFS，并记录真实/代理 audio start

**Files:**

- Modify: `SnapTra Translator/SpeechService.swift`
- Modify: `SnapTra Translator/AppModel.swift`
- Test: `SnapTra TranslatorTests/SpeechServiceTests.swift`
- Test: `SnapTra TranslatorTests/LookupPerformanceTests.swift`

**Step 1: 写顺序红灯测试**

```swift
func testDebugDumpIsScheduledAfterOnlinePlay()
func testBlockedDebugDumpDoesNotBlockSpeechService()
func testConcurrentDebugDumpsUseDistinctURLs()
func testStaleRequestDoesNotCreateDebugDump()
func testAppleDidStartAndOnlinePlayAcceptedUseSameLookupID()
```

**Step 2: 实现非阻塞 debug dumper**

- Debug-only dumper 在 play 成功或当前请求 fallback 已提交之后调度。
- 写入 utility actor/task；`SpeechService` 不 await。
- 文件放临时目录 `SnapTraTranslator/TTS`，文件名包含 provider、generation、UUID，使用 atomic write。
- Release 不创建 dumper。本轮不做清理/LRU。

**Step 3: 接入 audio start**

- AVFoundation adapter 通过 `AVSpeechSynthesizerDelegate.didStart` 回报 Apple start。
- 在线以 `play() == true && isPlaying` 作为 P0 代理，并在 metadata 标记 `playAccepted`，不得称为首个声波样本。
- fallback 沿用原 performance trace/lookupID。

**Step 4: 运行测试和 100 次逆序压力测试**

100 次 A/B controlled fetch 逆序完成中，旧播放、旧 fallback、旧 dump、迟到 `AudioStarted` 都必须为 0。

**Step 5: 提交**

```bash
git add 'SnapTra Translator/SpeechService.swift' \
  'SnapTra Translator/AppModel.swift' \
  'SnapTra TranslatorTests/SpeechServiceTests.swift' \
  'SnapTra TranslatorTests/LookupPerformanceTests.swift'
git commit -m "perf(tts): move debug audio dumps off playback path"
```

---

### Task 11: 删除 lookup-time 全量语言扫描

**Files:**

- Modify: `SnapTra Translator/LearningService.swift`
- Modify: `SnapTra TranslatorTests/LearningServicePaginationTests.swift`

**Step 1: 写行为红灯测试**

```swift
func testRecordLookupDoesNotRefreshLanguageSnapshot()
func testExplicitLanguageRefreshStillSeesNewLookupLanguage()
func testRecordLookupPreservesExistingAndNewWordLanguageSemantics()
func testRecordLookupAtFiveThousandRecordsUpdatesOnlyTargetWord()
```

测试流程：先显式 refresh 得到旧 language list，再 `recordLookup` 新语言；断言 list 不自动变化；再次显式 refresh 后才出现新语言。

**Step 2: 运行红灯测试**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -only-testing:'SnapTra TranslatorTests/LearningServicePaginationTests' \
  CODE_SIGNING_ALLOWED=NO
```

**Step 3: 删除热路径 refresh**

- 从 `recordLookup` 删除 `await refreshAvailableLanguageIdentifiers()`。
- 完整 refresh 只保留在 `LearningSettingsView.onAppear` 和管理型 mutation 后。
- 不做 AppModel 实例的增量语言 set：AppModel 与 Learning 页当前是两个 `LearningService` 实例，更新热路径实例的 list 不会刷新正在显示的 Learning 页，只会增加无效状态工作。
- 不改变 lookupCount、source language、review date 或 export。

这会把 language-list 工作从 O(全部记录数) 降为 lookup 热路径上的 0；显式页面 refresh 仍按现有完整语义运行。

**Step 4: 运行绿灯测试**

重复 Step 2。Expected: Learning pagination/export/record tests 全部通过。

**Step 5: 提交**

```bash
git add 'SnapTra Translator/LearningService.swift' \
  'SnapTra TranslatorTests/LearningServicePaginationTests.swift'
git commit -m "perf(learning): remove lookup-time language scans"
```

---

### Task 12: 将一次 lookup 的 definition 持久化收敛为最多一次

**Files:**

- Modify: `SnapTra Translator/AppModel.swift`
- Modify: `SnapTra Translator/LearningService.swift`
- Modify: `SnapTra Translator/WordRecord.swift`
- Modify: `SnapTra TranslatorTests/LearningServicePaginationTests.swift`
- Modify: `SnapTra TranslatorTests/LookupDirectionTests.swift`

**Step 1: 写失败测试**

```swift
func testIdenticalDefinitionUpdateReportsUnchanged()
func testFinalDefinitionUsesStableDictionarySectionOrder()
func testMultipleResultArrivalsProduceOneFinalDefinitionCommit()
func testSupersededLookupKeepsLookupCountButSkipsPartialDefinition()
func testExportStillIncludesRecordsOutsideVisiblePage()
```

**Step 2: 让 `WordRecord.updateDefinition` 可表达 no-op**

将方法改为返回 `Bool`：normalized definition 与现值相同或 nil 时返回 false；真实变化才赋值并返回 true。`LearningService.updateDefinition` 只有 inserted/changed 时 save，并返回 `.inserted`、`.updated` 或 `.unchanged` 供测试和 metrics 使用。

**Step 3: 合并 AppModel 写入时机**

- lookup 初始内容展示后仍启动一次 record task，并保留局部 handle；lookupCount 不因用户很快松键而丢失。
- 删除 `applyPrimaryTranslationState` 和每个 `applyDictionarySectionResult` 内的逐次 `updateLearningDefinition`。
- translation/dictionary task group 全部结束后：
  1. 校验 task 未取消且 active lookupID 匹配；
  2. await record task，避免 definition 先于 record；
  3. 从最终累计的 `OverlayContent` 生成稳定 definition；
  4. 最多调用一次 `LearningService.updateDefinition`。
- lookup 中途 superseded 时不保存 partial definition；record task 继续完成 lookupCount。

每次 lookup 的 save 上限：lookupCount 恰好 1 次；definition 0 或 1 次；总计不超过 2 次。

**Step 4: 运行定向与完整 Learning 测试**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -only-testing:'SnapTra TranslatorTests/LearningServicePaginationTests' \
  -only-testing:'SnapTra TranslatorTests/OverlayPrimaryTranslationStateTests' \
  CODE_SIGNING_ALLOWED=NO
```

**Step 5: 提交**

```bash
git add 'SnapTra Translator/AppModel.swift' \
  'SnapTra Translator/LearningService.swift' \
  'SnapTra Translator/WordRecord.swift' \
  'SnapTra TranslatorTests/LearningServicePaginationTests.swift' \
  'SnapTra TranslatorTests/LookupDirectionTests.swift'
git commit -m "perf(learning): coalesce lookup definition writes"
```

---

### Task 13: 全量回归、真实场景验收和 after comparison

**Files:**

- Modify: `docs/performance/hotkey-word-lookup-p0-results.md`
- Verify: all changed production/test/project/script files

**Step 1: 跑完整测试**

```bash
xcodebuild test \
  -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/snaptra-p0-tests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: 全部测试通过，无新 actor-isolation error；既有 warning 单独记录，不伪报为本改动产生。

**Step 2: 构建两个发行面**

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator" -configuration Release \
  -derivedDataPath /tmp/snaptra-p0-after-appstore \
  build CODE_SIGNING_ALLOWED=NO

xcodebuild -project "SnapTra Translator.xcodeproj" \
  -scheme "SnapTra Translator Direct" -configuration Release \
  -derivedDataPath /tmp/snaptra-p0-after-direct \
  build CODE_SIGNING_ALLOWED=NO
```

**Step 3: 真实场景回归**

- TextEdit、Notes：known-range 各 50 次，无 bounds 时仍走 selected-text。
- Chrome/Electron 类应用：fresh Cmd+C 胜出；旧 clipboard 50 次全部走 OCR。
- App Store：AX/clipboard invocation count 始终为 0。
- overlay 隐藏时建立 cache，随后显示并再次查词：不得截到自身；Settings window 仍可 OCR。
- 双屏不同缩放、热插拔/重排、sleep/wake 后第一次 lookup 正确。
- 快速 A/B 发音 100 次只允许最后一次；加载中 dismiss 20 次后无迟到声音/fallback。
- Youdao/Baidu/Google/Bing 各做一次真实播放与加载中停止；真实网络错误仍能 Apple fallback。
- Learning 0/100/5,000 条下 lookupCount、definition、filter/export 正确。

**Step 4: 复跑同一 Release 矩阵**

将 before/after P50/P95、cache hit ratio、AX attribute read counts、TTS cancel latency、Learning save counts、异常样本和原始 trace 路径写回 results 文档。若未达到第 2 节门槛，按 signpost 定位后回到对应 task，不把未改善项标为完成。

**Step 5: 最终卫生检查并提交结果**

```bash
bash -n scripts/performance/capture-lookup-trace.sh
git diff --check
git status --short
```

```bash
git add docs/performance/hotkey-word-lookup-p0-results.md
git commit -m "docs(perf): record P0 lookup comparison"
```

## 3. 推荐的实施组织方式

- Task 1-2 必须最先串行完成并锁定 before baseline。
- Task 3-7 是同一条 lookup/capture 链，按顺序完成；不要让多个分支同时改 `AppModel.swift`。
- Task 8-10 可以在独立 worktree 开发，但合并前需 rebase 到 metrics API；不要与 lookup 分支同时修改同一 `project.pbxproj`。
- Task 11-12 在 lookup coordinator 稳定后实施，避免同时重排 `performOcrWordLookup`。
- 每个 task 独立红灯、绿灯、commit；最后才做真实 Release 比较和总回归。

## 4. 完成定义

只有同时满足以下条件，P0 才算完成：

- before/after 数据齐全，且关键 route 达到性能门槛或有明确、可复现的阶段证据说明未达原因。
- 真实选区、fresh clipboard、stale clipboard、App Store gating 全部回归通过。
- 同 generation capture cache 命中且没有 overlay self-capture。
- TTS 陈旧播放、陈旧 fallback、陈旧 debug dump 均为 0；HTTP/WebSocket 底层取消被测试观察到。
- 每次 lookup 不再全表刷新语言，definition save 为 0 或 1 次，export 仍覆盖完整 matching dataset。
- 全量 tests、两个 Release scheme、`git diff --check` 全部通过。
