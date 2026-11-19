# 长文翻译浮窗设计与实施计划

## 问题与设计决策

截图中的译文已超出屏幕，但浮窗没有独立的阅读区。选中文字翻译以鼠标为锚点，现有代码只在按 OCR 区域对齐时计算限高。浮窗按译文的完整高度撑开，移动窗口原点也无法让首尾同时进入屏幕。

保留当前浮窗，用**随内容收起的短文面板和可纵向滚动的长文阅读区**承载两种阅读场景。翻译工具栏固定在顶部，原文、译文和各翻译来源共享一个滚动区。单个阅读区支持滚轮、触控板和原生滚动条，也便于对照不同来源的译文。出现长文时请求系统短暂显示滚动条，之后遵循 macOS 的显示偏好。仍有下文时底部轻微渐隐，滚动到底后恢复清晰边缘。

## 实施步骤

1. **统一浮窗尺寸与落点。** 在 `SnapTra Translator/OverlayWindowController.swift` 中根据当前显示器的可用区域计算宽高上限，四周预留 8 pt，常规高度上限取可用高度的 72%。选中文字的结果优先靠近鼠标，OCR 结果优先贴着原文区域的上方或下方。当 OCR 两侧都放不下 280 pt 高的浮窗时，采用 280 pt 的目标高度并服从屏幕上限，允许与原文区域部分重叠。固定后拖到另一台显示器时重新计算上限。
2. **分离工具栏与阅读区。** 在 `SnapTra Translator/OverlayView.swift` 中为原文、译文和多来源结果使用同一个原生纵向 `ScrollView`。让 SwiftUI 在实际面板宽度下测量文字，以内容高度收起短文，并从面板高度中分配工具栏和正文空间。滚动时保留现有段落、列表缩进、文字选择和各来源的复制操作。
3. **统一布局刷新。** 在 `SnapTra Translator/AppModel.swift` 中将首次显示、异步结果更新和拖动结束交给同一尺寸策略。原文编辑区展开时也触发布局刷新。保留同一个滚动容器，让已有结果的阅读位置可以跨流式更新延续。
4. **验证几何和实际滚动。** 在 `SnapTra TranslatorTests/ParagraphOverlayLayoutTests.swift` 中覆盖短文、超长内容、接近屏幕边缘、OCR 两侧空间不足以及带负坐标的小屏幕。在 AppKit 宿主中验证原生滚动容器的尾段可达，滚动时顶部空间保持不动。

## 验收

| 场景 | 预期 |
| --- | --- |
| 选中一两行，或等待翻译 | 浮窗贴合当前内容，无需滚动时看不到滚动条 |
| 选中几十行，译文继续换行 | 浮窗保持在可见区域内，可滚到最后一段并选择其中的文字 |
| 多来源翻译或展开原文编辑 | 结果共享正文滚动区，顶部工具栏保持可用 |
| 靠近菜单栏、Dock 或拖到更小的显示器 | 面板按目标显示器收缩，拖动结束后工具栏和底边都可见 |
| 滚动条设为自动隐藏 | 有下文时底部仍有渐隐提示，滚到底时提示消失 |

验证命令

```bash
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" \
  -destination "platform=macOS" -configuration Debug \
  -only-testing:SnapTra\ TranslatorTests/ParagraphOverlayLayoutTests test
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator Direct" \
  -destination "platform=macOS" -configuration Debug build
```
