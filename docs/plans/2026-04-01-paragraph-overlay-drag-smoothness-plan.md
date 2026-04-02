# Paragraph Overlay Drag Smoothness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让常驻句子翻译面板始终可以通过拖动原文内行移动，并消除手动拖拽时的重影、抢位和卡顿。

**Architecture:** 在 `AppModel` 修正 paragraph session 的 release 状态流转；在 `OverlayWindowController` 建立“手动位置优先”规则；在 `OverlayView` 给原文正文增加 pinned-only 拖拽捕获层。

**Tech Stack:** SwiftUI, AppKit, NSPanel, NSTextView-backed paragraph text

---

### Task 1: 修正 paragraph release 状态机

**Files:**
- Modify: `SnapTra Translator/AppModel.swift`

**Step 1: 调整热键 release 顺序**

- 在 `handleHotkeyRelease()` 中，只有在确认不需要保留 paragraph overlay 时，才重置 `activeLookupMode`。
- 若 overlay 已 pinned，则保持 paragraph 会话与交互状态。

**Step 2: 调整 persistent release 顺序**

- 在 `handlePersistentSentenceOverlayRelease()` 中保留 paragraph mode。
- 若 paragraph overlay 可见，则切到 pinned/interactive 状态并保留 `Esc` 监听。

### Task 2: 让手动位置优先于自动对齐

**Files:**
- Modify: `SnapTra Translator/OverlayWindowController.swift`
- Modify: `SnapTra Translator/AppModel.swift`

**Step 1: 暴露手动拖拽状态**

- 为窗口控制器增加只读状态：
  - 是否正在手动拖拽
  - 是否已经存在手动位置

**Step 2: 跳过拖拽中的自动重排**

- `AppModel` 在拖拽进行中不再触发 paragraph 对齐刷新。
- 拖拽结束后再补一次无吸附的布局刷新。

**Step 3: 保留手动原点**

- 当已存在手动位置时，paragraph 刷新只允许调整窗口大小，不再重新吸附到句子矩形。

### Task 3: 增加原文正文拖拽热区

**Files:**
- Modify: `SnapTra Translator/OverlayView.swift`

**Step 1: 新增 pinned-only 原文拖拽覆盖层**

- 只在 paragraph overlay pinned 时显示透明拖拽层。
- 覆盖原文正文区域，将拖动事件转发给现有拖拽 helper。

**Step 2: 统一拖拽光标反馈**

- pinned 状态下，标题栏和原文拖拽区都使用相同的 open-hand / closed-hand 反馈。

### Task 4: 验证

**Files:**
- Modify: none

**Step 1: 构建验证**

Run:
```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

Expected:
- 编译通过
- 无新增 SwiftUI / AppKit 交互错误

**Step 2: 手动行为验证**

- OCR 双击句子面板，进入常驻后拖动原文行，面板跟手移动
- 选中文本单击句子面板，点击固定后拖动标题栏或原文行，面板可移动
- 拖动过程中不再出现明显重影或被自动吸回
