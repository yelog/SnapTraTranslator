//
//  Snap_TranslateApp.swift
//  Snap Translate
//
//  Created by 杨玉杰 on 2026/1/12.
//

import AppKit
import SwiftUI

@main
struct Snap_TranslateApp: App {
    @StateObject private var model = AppModel()
    @State private var hasInitialized = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onAppear {
                    // 应用启动后立即初始化（只执行一次）
                    guard !hasInitialized else { return }
                    hasInitialized = true

                    if #available(macOS 15.0, *) {
                        // 1. 先创建后台翻译服务窗口
                        createTranslationServiceWindow(model: model)

                        // 2. 等待窗口创建完成后预热服务
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            warmupServices(model: model)
                        }
                    }
                }
        }
        .windowResizability(.contentSize)
    }
}

@available(macOS 15.0, *)
func createTranslationServiceWindow(model: AppModel) {
    // 如果已经创建，不重复创建
    guard TranslationServiceWindowHolder.shared.window == nil else { return }

    let translationView = TranslationBridgeView(
        bridge: model.translationBridge,
        settings: model.settings
    )

    let hostingView = NSHostingView(rootView: translationView)
    hostingView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.isOpaque = false
    window.backgroundColor = .clear
    window.setIsVisible(false)

    // 保持窗口引用，防止被释放
    TranslationServiceWindowHolder.shared.window = window
}

// 单例来持有后台窗口的强引用
@available(macOS 15.0, *)
class TranslationServiceWindowHolder {
    static let shared = TranslationServiceWindowHolder()
    var window: NSWindow?
    private init() {}
}

// 预热翻译服务，减少首次使用延迟
@available(macOS 15.0, *)
func warmupServices(model: AppModel) {
    Task { @MainActor in
        // 延迟一点执行，避免阻塞应用启动
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

        do {
            // 预热翻译服务 - 执行一次虚拟翻译来加载语言模型
            let sourceLanguage = Locale.Language(identifier: model.settings.sourceLanguage)
            let targetLanguage = Locale.Language(identifier: model.settings.targetLanguage)

            // 执行一次简单翻译来初始化 Translation 框架和加载语言模型
            _ = try? await model.translationBridge.translate(
                text: "hello",
                source: sourceLanguage,
                target: targetLanguage,
                timeout: 10.0
            )

            print("✅ Translation service warmed up (source: \(model.settings.sourceLanguage), target: \(model.settings.targetLanguage))")

        } catch {
            print("⚠️ Warmup failed: \(error)")
        }
    }
}
