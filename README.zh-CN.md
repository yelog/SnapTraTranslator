# Snap Translate

[English](README.md)

一款轻量级 macOS SwiftUI 应用，通过屏幕取词和 OCR 在光标附近即时展示翻译气泡。按下快捷键悬停即可查看翻译、音标，并可选择播放发音。

## 特性
- 光标附近弹出翻译气泡，显示翻译与音标
- 捕获光标附近区域并识别单词，优先选择最接近指针的单词
- 可选发音播放（源语言 TTS）
- 可配置源/目标语言与单键快捷键
- 调试模式可显示 OCR 检测区域，便于排查取词问题

## 环境要求
- macOS 14+（系统翻译 API 需要 macOS 15）
- 需授予屏幕录制、辅助功能/输入监控权限

## 构建与运行
- Xcode：打开 `Snap Translate.xcodeproj`，选择 **Snap Translate** scheme 运行 Debug。
- CLI 构建：`xcodebuild -project "Snap Translate.xcodeproj" -scheme "Snap Translate" -configuration Debug build`
- 清理：`xcodebuild -project "Snap Translate.xcodeproj" -scheme "Snap Translate" clean`

## 使用说明
1) 启动应用，按提示授予屏幕录制与辅助功能/输入监控权限。
2) 在设置中配置单键快捷键和语言对。
3) 按住快捷键并将光标悬停到文本上，气泡会在光标附近出现并显示翻译与音标；松开快捷键即可关闭。
4) 如需排查取词区域，开启“调试 OCR 区域”以查看捕获范围和识别词框。

## 故障排查
- 若气泡未出现，请重新检查屏幕录制权限并确认快捷键已启用。
- 在 macOS 15 上如提示缺少翻译，前往 **系统设置 > 通用 > 语言与地区 > 翻译** 安装语言包。
- 若气泡在屏幕边缘被遮挡，可开启调试 OCR 区域确认捕获范围并调整悬停位置。

## 许可
尚未指定。如需分发，请补充许可文件。
