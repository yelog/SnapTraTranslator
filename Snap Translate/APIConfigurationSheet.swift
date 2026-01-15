import SwiftUI

struct APIConfigurationSheet: View {
    let engineType: TranslationEngineType
    @State var configuration: EngineAPIConfig
    let onSave: (EngineAPIConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("\(engineType.displayName) Configuration")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    onSave(configuration)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !engineType.requiresAPIKey {
                        // API mode toggle (only for engines that support free API)
                        Toggle("Use Custom API Key", isOn: $configuration.useCustomAPI)
                            .toggleStyle(.switch)

                        if !configuration.useCustomAPI {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                                Text("Using free API with rate limits. For better performance, configure your own API key.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if engineType.requiresAPIKey || configuration.useCustomAPI {
                        VStack(alignment: .leading, spacing: 12) {
                            switch engineType {
                            case .google:
                                apiKeyField(label: "API Key", value: $configuration.apiKey)

                            case .bing:
                                apiKeyField(label: "Azure Subscription Key", value: $configuration.apiKey)

                            case .baidu:
                                apiKeyField(label: "App ID", value: $configuration.appId)
                                apiKeyField(label: "Secret Key", value: $configuration.secretKey, isSecure: true)

                            case .youdao:
                                apiKeyField(label: "App Key", value: $configuration.apiKey)
                                apiKeyField(label: "Secret", value: $configuration.secretKey, isSecure: true)

                            case .apple:
                                EmptyView()
                            }

                            // Get API Key link
                            Link(destination: engineType.apiKeyURL) {
                                HStack {
                                    Image(systemName: "arrow.up.right.square")
                                    Text("Get API Key")
                                }
                                .font(.system(size: 12))
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 400, height: 350)
    }

    private func apiKeyField(label: String, value: Binding<String>, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if isSecure {
                SecureField("", text: value)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField("", text: value)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
