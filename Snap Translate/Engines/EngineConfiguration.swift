import Foundation

/// Single engine API configuration
struct EngineAPIConfig: Codable, Equatable {
    var useCustomAPI: Bool = false
    var apiKey: String = ""
    var secretKey: String = ""
    var appId: String = ""

    init(
        useCustomAPI: Bool = false,
        apiKey: String = "",
        secretKey: String = "",
        appId: String = ""
    ) {
        self.useCustomAPI = useCustomAPI
        self.apiKey = apiKey
        self.secretKey = secretKey
        self.appId = appId
    }
}

/// All engine configurations
struct EngineConfigurations: Codable, Equatable {
    var google: EngineAPIConfig = EngineAPIConfig()
    var bing: EngineAPIConfig = EngineAPIConfig()
    var baidu: EngineAPIConfig = EngineAPIConfig()
    var youdao: EngineAPIConfig = EngineAPIConfig()

    subscript(engine: TranslationEngineType) -> EngineAPIConfig {
        get {
            switch engine {
            case .apple: return EngineAPIConfig()
            case .google: return google
            case .bing: return bing
            case .baidu: return baidu
            case .youdao: return youdao
            }
        }
        set {
            switch engine {
            case .apple: break
            case .google: google = newValue
            case .bing: bing = newValue
            case .baidu: baidu = newValue
            case .youdao: youdao = newValue
            }
        }
    }
}
