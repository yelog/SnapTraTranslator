# 快捷键查词 P0 性能结果

## 测量口径

- 起点：`AppModel.startLookup(at:)` 接收单击快捷键冻结的鼠标位置，并创建业务 `lookupID`。
- 隐藏面板首次呈现：`NSWindow.orderFrontRegardless()` 返回。
- 已显示面板更新：新 lookup 的 `overlayState` 已发布；即使状态值相同，也会结束该 lookup 的首次呈现区间。
- Apple 发音开始：`AVSpeechSynthesizerDelegate.speechSynthesizer(_:didStart:)`。
- 在线发音代理：`AVAudioPlayer.play()` 返回 `true` 且 `isPlaying == true`，metadata 明确记录为 `playAccepted`，不等同于首个声波样本。
- 所有 stage 使用单调时钟和同一个业务 `lookupID`。

## 环境

| 字段 | Before | After |
| --- | --- | --- |
| 业务基线 | `b660a56` | `c5ff8e1` |
| 埋点构建 | `7eee33f` | `c5ff8e1` |
| macOS | 26.5.2 (25F84) | 26.5.2 (25F84) |
| 机器 / 芯片 | Mac14,6 / Apple M2 Max | 相同 |
| 显示器 | 内置 3456×2234 Retina；外接 3840×2160，UI 1920×1080 | 相同 |
| 语言、词典、TTS provider | 未形成有效人工样本 | 未形成有效人工样本 |
| Learning 规模 | 自动化覆盖 0 / 100 / 5,000 边界 | 自动化覆盖 0 / 100 / 5,000 边界 |

## 采样规则

- Cold：进程启动后的首个有效 lookup，每格至少 5 个样本。
- Warm：3 次不计入的预热后，每格至少 20 个样本。
- 机器、显示缩放、语言、词典源、测试文本与网络条件必须保持一致。
- App Store OCR、Direct OCR/无选区、Direct AX 选区、Direct fresh clipboard 必须分开统计。
- Direct selected-text 不得与 App Store OCR 混算。

## 实测状态

本轮没有形成可用于 before/after 对比的端到端延迟样本。用于采样的无签名 Release 构建没有屏幕录制和辅助功能授权，OCR、AX selection 与 clipboard fallback 均无法完成真实业务链路；因此样本数为 0，P50/P95 不计算，也不以自动化测试耗时替代产品延迟。

Before 曾生成一份原始 Instruments trace：

- `/tmp/snaptra-p0-before-appstore-7eee33f.trace`
- trace 模板数据约 18 MB，但没有有效 lookup 样本。

After 未重复生成无效 trace。为避免替换或重签名用户当前 `/Applications/SnapTra Translator.app`，本轮保留现有已授权应用，不修改 TCC 状态。

## Before 基线

功能基线 `b660a56` 的全量测试为 233 项通过、0 失败；`7eee33f` 的 App Store 与 Direct 无签名 Release 构建均成功。

| Channel | Route | Temperature | Learning count | 有效样本 | Panel P50/P95 | Audio P50/P95 | 结论 |
| --- | --- | --- | ---: | ---: | --- | --- | --- |
| App Store | OCR | cold / warm | 0 | 0 | — | — | TCC 阻塞 |
| Direct | OCR / no selection | cold / warm | 0 | 0 | — | — | TCC 阻塞 |
| Direct | AX selection | warm | 0 | 0 | — | — | TCC 阻塞 |
| Direct | clipboard selection | warm | 0 | 0 | — | — | TCC 阻塞 |

## After P0

`c5ff8e1` 的全量测试为 317 项通过、0 失败；App Store 与 Direct 两个无签名 Release 构建均成功。

| Channel | Route | Temperature | Learning count | 有效样本 | Panel P50/P95 | Audio P50/P95 | 结论 |
| --- | --- | --- | ---: | ---: | --- | --- | --- |
| App Store | OCR | cold / warm | 0 | 0 | — | — | 未进行授权态人工采样 |
| Direct | OCR / no selection | cold / warm | 0 | 0 | — | — | 未进行授权态人工采样 |
| Direct | AX selection | warm | 0 | 0 | — | — | 未进行授权态人工采样 |
| Direct | clipboard selection | warm | 0 | 0 | — | — | 未进行授权态人工采样 |

## 自动化与结构性证据

| 范围 | 结果 | 证据 |
| --- | --- | --- |
| AX 分阶段短路 | 通过 | known range 不读取 marker、attributed string 或 bounds；executor 离开 MainActor 且串行化 |
| Clipboard/OCR 仲裁 | 通过 | fresh clipboard 保持权威；stale/nil 复用预取 OCR；父 lookup 取消会取消 speculative OCR |
| Capture metadata cache | 通过 | 同 generation/epoch 共用一次 load；失效后旧 completion 不能覆盖；失败不缓存；stale source 最多刷新一次 |
| Overlay exclusion | 通过 | registry generation 驱动 cache key；已注册 overlay 排除，未注册窗口保留 |
| TTS 生命周期 | 通过 | HTTP 与 WebSocket 底层取消可观察；旧播放、旧 fallback、迟到 start 均为 0 |
| TTS 压力复跑 | 通过 | `SpeechServiceTests` 24 项重复 5 轮，共 120 次 test run；其中 100 轮逆序完成压力用例执行 5 次 |
| Audio-start metadata | 通过 | Apple `didStart`、在线 `playAccepted`、Apple submission proxy 类型化并关联同一 lookupID |
| Learning 热路径 | 通过 | 5,000 条记录只更新目标词；lookup 时不刷新全量语言列表 |
| Learning 写入上限 | 通过 | record 与结果 barrier 并行；结果全部完成后才允许唯一 definition commit；supersede 保留 lookupCount、跳过 partial definition |
| Export 边界 | 通过 | 导出仍包含可见页之外的全部匹配记录 |

## 正确性门禁

- [x] Known-range AX selection 保持 selection-first，且不读取 bounds。
- [x] 旧剪贴板不会劫持 OCR lookup。
- [x] speculative OCR 先完成时，fresh clipboard 仍然获胜。
- [x] App Store 路径不会调用 AX 或 clipboard fallback。
- [x] Capture cache 与 overlay registry generation 一致失效。
- [x] 未注册的设置窗口等普通窗口仍可捕获。
- [x] Superseded/stopped TTS 不会播放或 fallback。
- [x] HTTP 和 WebSocket 取消到达底层请求。
- [x] Lookup-time language full fetch 为 0。
- [x] 每个 lookup 只有一次 lookup record，definition 为 0 或 1 次。
- [x] 全量匹配记录导出语义不变。

## 验收结论

| Gate | 目标 | 本轮结果 |
| --- | --- | --- |
| Direct OCR warm panel P50 | 至少快 25% | 未判定：0 个有效授权态样本 |
| Direct OCR warm panel P95 | 至少快 20% | 未判定：0 个有效授权态样本 |
| App Store OCR warm panel P95 | 至少快 10% | 未判定：0 个有效授权态样本 |
| 任一路由 P95 回归 | 不超过 5% | 未判定：0 个有效授权态样本 |
| Capture metadata warm loads | 每 generation 一次 | 自动化通过 |
| 陈旧 TTS 副作用 | 0 | 自动化与 5 轮压力复跑通过 |
| Learning 5,000 vs 100 P95 差值 | 不超过 5 ms | 延迟未判定；全量扫描已从 lookup 热路径移除 |

P0 的功能、并发、取消和持久化边界已经通过自动化验收；百分比提速门槛仍需在同一台机器上使用已授权的正式签名构建完成 before/after 采样后才能判定。

## 原始证据与例外

- Before builds：`/tmp/snaptra-p0-before-appstore`、`/tmp/snaptra-p0-before-direct`。
- After builds：`/tmp/snaptra-p0-after-appstore-final`、`/tmp/snaptra-p0-after-direct-final`。
- Full test result：`/tmp/snaptra-p0-tests-final/Logs/Test/Test-SnapTra Translator-2026.07.16_12-22-32-+0800.xcresult`。
- TTS 5 轮 result：`/tmp/snaptra-p0-tts-repeat/Logs/Test/Test-SnapTra Translator-2026.07.16_12-13-39-+0800.xcresult`。
- 已知既有 warning：项目仍有 Swift 6 actor-isolation 迁移 warning；本轮没有新增编译错误。
- Xcode 26.5 Release 构建会输出一条 `withThrowingTaskGroup` 类型查找诊断，但两个 scheme 均以 exit 0 完成并产出约 8 MB 可执行文件。
- 未排除任何有效样本；本轮是没有有效授权态样本，而不是删除异常值。
