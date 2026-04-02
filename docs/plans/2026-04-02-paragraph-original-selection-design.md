# Paragraph Original Selection Design

## 背景

当前句子翻译面板在常驻状态下，原文正文整块区域都支持拖动窗口。这虽然满足了拖拽能力，但会覆盖 `SelectableTextView` 的文本交互，导致用户无法正常选中原文进行复制。

## 目标

- 仅原文标题行支持拖动窗口。
- 原文正文恢复原生文本选择与复制能力。
- 不改动现有标题行拖拽、按钮位置和窗口拖动算法。

## 根因

原文正文在 [OverlayView.swift](/Users/yelog/workspace/swift/SnapTra%20Translator/SnapTra%20Translator/OverlayView.swift) 中额外挂载了透明拖拽覆盖层。该覆盖层位于 `SelectableTextView` 之上，会优先截获鼠标事件，导致正文文本无法进入 `NSTextView` 的选中链路。

## 方案

采用最小改动方案：

- 删除原文正文上的拖拽 overlay。
- 保留原文标题行现有拖拽热区。
- 不调整 `ParagraphOverlayDragHandle`、`OverlayWindowController` 与按钮布局。

## 预期交互

- 拖动原文标题行：移动窗口。
- 点击并拖动原文正文：选中文字。
- 复制和关闭按钮行为不变。
