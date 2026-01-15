import SwiftUI

struct TranslationEngineSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var selectedEngineForConfig: TranslationEngineType?

    var body: some View {
        SettingsSectionCard(
            title: "Translation Engine",
            icon: "globe",
            delay: 0.15
        ) {
            VStack(spacing: 14) {
                enginePickerRow

                Divider().opacity(0.5)

                if settings.translationEngine != .apple {
                    apiConfigRow
                    Divider().opacity(0.5)
                }

                engineDescriptionRow
            }
        }
        .sheet(item: $selectedEngineForConfig) { engine in
            APIConfigurationSheet(
                engineType: engine,
                configuration: settings.engineConfigurations[engine],
                onSave: { config in
                    var configs = settings.engineConfigurations
                    configs[engine] = config
                    settings.engineConfigurations = configs
                }
            )
        }
    }

    private var enginePickerRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Engine")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                Text("Select translation service")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Picker("", selection: $settings.translationEngine) {
                ForEach(TranslationEngineType.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.accentColor)
        }
    }

    private var apiConfigRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("API Configuration")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)

                let config = settings.engineConfigurations[settings.translationEngine]
                if settings.translationEngine.requiresAPIKey {
                    Text(config.appId.isEmpty ? "API key required" : "Using custom API key")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(config.appId.isEmpty ? Color.orange : Color.secondary)
                } else {
                    Text(config.useCustomAPI ? "Using custom API key" : "Using free API")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("Configure") {
                selectedEngineForConfig = settings.translationEngine
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var engineDescriptionRow: some View {
        HStack {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(engineDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    private var engineDescription: String {
        switch settings.translationEngine {
        case .apple:
            return "Uses macOS built-in translation (requires macOS 15+)"
        case .google:
            return "Google Translate with free API or custom API key"
        case .bing:
            return "Bing Translator with free API or Azure subscription"
        case .baidu:
            return "Baidu Translate (requires App ID and Secret Key)"
        case .youdao:
            return "Youdao Dictionary with phonetics and definitions"
        }
    }
}
