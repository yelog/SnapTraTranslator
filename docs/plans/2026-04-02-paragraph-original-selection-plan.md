# Paragraph Original Selection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让句子翻译面板只在原文标题行支持拖拽，同时恢复原文正文的选中复制能力。

**Architecture:** 直接移除原文正文上的拖拽覆盖层，让正文重新由 `SelectableTextView` 处理鼠标事件；标题行拖拽热区保持不变，因此窗口移动算法与按钮布局无需调整。

**Tech Stack:** SwiftUI, AppKit, NSTextView-backed SelectableTextView

---

### Task 1: 收缩原文拖拽热区

**Files:**
- Modify: `SnapTra Translator/OverlayView.swift`

**Step 1: 删除原文正文拖拽 overlay**

- 移除正文 `paragraphTextContent(...)` 上附加的透明拖拽层。

**Step 2: 删除废弃辅助视图**

- 移除只为正文拖拽服务的 `paragraphOriginalTextDragOverlay`，保持标题行拖拽视图继续使用。

### Task 2: 验证行为

**Files:**
- Modify: none

**Step 1: 执行构建**

Run:
```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

Expected:
- `BUILD SUCCEEDED`

**Step 2: 手动验证**

- 在常驻状态下拖动原文标题行，窗口仍可移动。
- 在原文正文拖动鼠标，应进入文本选择而不是窗口拖动。
- 复制与关闭按钮行为保持正常。
