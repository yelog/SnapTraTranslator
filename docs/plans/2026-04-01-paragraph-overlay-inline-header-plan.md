# Paragraph Overlay Inline Header Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将句子翻译浮层的“原文”标题与右上角控制按钮合并为同一固定顶部栏，减少顶部留白并保持按钮贴边位置。

**Architecture:** 保留现有段落浮层固定顶栏结构，只在段落结果态中把按钮栏升级为“原文标题栏”。正文区删除重复标题，避免影响滚动布局与窗口测量逻辑。

**Tech Stack:** SwiftUI, AppKit-hosted overlay panel

---

### Task 1: 调整段落结果态顶部栏

**Files:**
- Modify: `SnapTra Translator/OverlayView.swift`

**Step 1: 新增原文标题栏视图**

- 基于现有 `paragraphTopBar()` 提取共享按钮样式。
- 新增 `paragraphOriginalTopBar(copyText:)`：
  - 左侧显示 `Original`
  - 紧跟原文复制按钮
  - 右侧显示 `Pin` 或 `Close`

**Step 2: 在段落结果态使用新标题栏**

- 当存在原文时，用 `paragraphOriginalTopBar(copyText:)` 替代 `paragraphTopBar()`。
- 其他状态维持现状。

### Task 2: 压缩原文区域顶部留白

**Files:**
- Modify: `SnapTra Translator/OverlayView.swift`

**Step 1: 删除正文中的重复原文标题行**

- 原文 section 仅保留正文内容。
- 继续保留正文下方分隔线和翻译区结构。

**Step 2: 保持贴边与滚动交互不变**

- 顶部标题栏沿用现有上边距。
- 不改动段落浮层最大高度和滚动容器逻辑。

### Task 3: 验证

**Files:**
- Modify: none

**Step 1: 构建验证**

Run:
```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build
```

Expected:
- 工程成功编译。
- 无新增 SwiftUI 布局错误。

**Step 2: 交互验证**

- 打开句子翻译浮层，确认“原文”与 `Pin` / `Close` 在同一行。
- 检查按钮顶部位置与改动前基本一致。
- 检查长文本场景下顶部按钮仍保持固定可见。
