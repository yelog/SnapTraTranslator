# SnapTra Translator

[English](README.md)

一款轻量级 macOS 菜单栏应用，通过屏幕取词和 OCR 即时翻译光标下的单词。按下快捷键悬停到任意文本上，即可看到精美的悬浮气泡，显示翻译、音标、词典释义，并可选择播放发音。

## 预览

<p>
  <img src="docs/Xnip2026-01-19_10-55-57.png" alt="设置界面" width="64%" />
</p>

## 截图

<p>
  <img src="docs/Xnip2026-01-19_00-02-09.png" alt="翻译气泡" width="49%" />
  <img src="docs/Xnip2026-01-19_00-06-14.png" alt="词典释义" width="49%" />
</p>

## 功能特性

### 核心翻译
- **即时 OCR 翻译** - 捕获光标周围的屏幕区域，检测最接近指针的单词
- **悬浮气泡** - 现代半透明气泡在光标附近显示翻译结果
- **词典释义** - 按词性（名词、动词、形容词等）分组显示详细释义
- **音标标注** - 显示识别单词的音标
- **文字转语音** - 可选在翻译后播放发音

### 翻译模式
- **持续翻译** - 按住快捷键移动鼠标时持续翻译
- **单次查询模式** - 每次按下快捷键查询一次，气泡可交互（复制、关闭按钮）

### 支持语言
简体中文、繁体中文、英语、日语、韩语、法语、德语、西班牙语、意大利语、葡萄牙语、俄语、阿拉伯语、泰语、越南语

### 自定义设置
- **单键快捷键** - 从修饰键中选择触发键（Shift、Control、Option、Command、Fn）
- **源语言/目标语言选择** - 选择翻译语言对
- **登录时启动** - 登录时自动启动
- **调试 OCR 区域** - 可视化捕获区域和识别的单词边界框，便于排查问题

### 其他功能
- **复制到剪贴板** - 快速复制单词或翻译
- **语言包检测** - 自动检查并提示缺少的语言包
- **菜单栏应用** - 在菜单栏安静运行，不占用 Dock 空间

## 环境要求

- macOS 14+（翻译功能需要 macOS 15 的系统翻译 API）
- 屏幕录制权限（OCR 捕获需要）

## 构建与运行

在 Xcode 中打开：
```bash
open "SnapTra Translator.xcodeproj"
```

命令行构建：
```bash
# Debug 构建
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build

# Release 构建
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Release build

# 清理
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" clean
```

## 使用方法

1. **授予权限** - 启动应用，按提示授予屏幕录制权限
2. **配置设置** - 在设置窗口中设置首选快捷键和语言对
3. **翻译** - 按住快捷键并将光标悬停到任意文本上，气泡会显示翻译、音标和释义
4. **关闭** - 松开快捷键关闭气泡（单次查询模式下也可点击 X 关闭）

## 故障排查

- **气泡未出现** - 在系统设置 > 隐私与安全性 > 屏幕录制中检查权限
- **macOS 15 上缺少翻译** - 在系统设置 > 通用 > 语言与地区 > 翻译语言中安装语言包
- **快捷键不工作** - 确保没有其他应用使用相同的按键，尝试其他修饰键
- **气泡在屏幕边缘被裁剪** - 开启"调试 OCR 区域"查看捕获范围并调整光标位置

## 许可证

MIT License
