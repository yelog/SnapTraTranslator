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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onAppear {
                    // 应用启动后创建后台翻译服务窗口
                    if #available(macOS 15.0, *) {
                        createTranslationServiceWindow(model: model)
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
        sourceLanguage: Locale.Language(identifier: model.settings.sourceLanguage),
        targetLanguage: Locale.Language(identifier: model.settings.targetLanguage)
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
