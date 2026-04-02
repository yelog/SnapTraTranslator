# Paragraph Header Drag Hit Testing Implementation Plan

## 目标

修复句子翻译面板在常驻状态下，原文标题行无法稳定拖动窗口的问题，并保持拖动丝滑、跟手。

## 实施步骤

1. 保留现有的 `ParagraphOverlayDragHandle` 原生拖拽实现，不改窗口移动算法。
2. 重构 [OverlayView.swift](/Users/yelog/workspace/swift/SnapTra%20Translator/SnapTra%20Translator/OverlayView.swift) 的标题行布局：
   - 左侧改为显式可拖区域。
   - 右侧保留 `复制` / `关闭` 按钮。
3. 让标题文字作为可拖区域的前景内容，并显式关闭标题文字的命中，确保鼠标事件落到拖拽视图。
4. 保留原文正文拖拽覆盖层，避免修标题行时回归正文拖拽。
5. 运行 `xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build` 验证编译通过。

## 验证重点

- 常驻状态下拖动原文标题文字是否能移动窗口。
- 常驻状态下拖动标题行空白区域是否能移动窗口。
- `复制` 与 `关闭` 按钮点击行为是否不受影响。
- 原文正文区域拖动能力是否保持正常。
