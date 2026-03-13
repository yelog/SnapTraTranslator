import AVFoundation
import CryptoKit
import Foundation
import os.log

@MainActor
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private let ttsServiceFactory = TTSServiceFactory()
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "SpeechService")
    private var isCancelled = false
    
    func speak(
        _ text: String,
        language: String?,
        provider: TTSProvider = .apple,
        useAmericanAccent: Bool = true
    ) {
        logger.info("🔊 Speaking with provider: \(provider.rawValue), text: \(text)")
        
        stopSpeaking()
        isCancelled = false
        
        switch provider {
        case .apple:
            logger.info("🎵 Using Apple System Voice")
            speakWithApple(text, language: language)
        case .youdao, .bing, .google, .baidu:
            logger.info("🌐 Using online TTS: \(provider.displayName)")
            Task {
                await speakWithOnlineService(
                    text,
                    language: language,
                    provider: provider,
                    useAmericanAccent: useAmericanAccent
                )
            }
        }
    }
    
    func stopSpeaking() {
        isCancelled = true
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    private func analyzeAudioData(_ data: Data, provider: TTSProvider) {
        guard data.count >= 4 else {
            logger.error("❌ Audio data too small: \(data.count) bytes")
            return
        }
        
        let header = data.prefix(4)
        let hexString = header.map { String(format: "%02x", $0) }.joined(separator: " ")
        logger.info("🔍 Audio header (hex): \(hexString)")
        
        // Check for MP3
        if header[0] == 0xFF && (header[1] & 0xE0) == 0xE0 {
            logger.info("✅ Detected MP3 format (MPEG audio)")
        } else if header.starts(with: [0x49, 0x44, 0x33]) {
            logger.info("✅ Detected MP3 format with ID3 tag")
        } else if header.starts(with: [0x52, 0x49, 0x46, 0x46]) {
            logger.info("✅ Detected WAV format (RIFF)")
        } else if header.starts(with: [0x4F, 0x67, 0x67, 0x53]) {
            logger.info("✅ Detected OGG format")
        } else {
            logger.warning("⚠️ Unknown audio format")
        }
        
        // Check if data is valid
        if data.count < 100 {
            logger.warning("⚠️ Audio data suspiciously small: \(data.count) bytes")
        }
    }
    
    private func speakWithApple(_ text: String, language: String?) {
        let utterance = AVSpeechUtterance(string: text)
        if let language {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
    
    private func speakWithOnlineService(
        _ text: String,
        language: String?,
        provider: TTSProvider,
        useAmericanAccent: Bool
    ) async {
        do {
            logger.info("📡 Fetching audio from \(provider.displayName)...")
            let audioData = try await ttsServiceFactory.fetchAudio(
                text: text,
                language: language,
                provider: provider,
                useAmericanAccent: useAmericanAccent
            )
            
            logger.info("✅ Successfully fetched \(audioData.count) bytes from \(provider.displayName)")
            
            // Debug: Save audio to file for inspection
            #if DEBUG
            let debugURL = FileManager.default.temporaryDirectory.appendingPathComponent("tts_\(provider.rawValue).mp3")
            try? audioData.write(to: debugURL)
            logger.debug("💾 Debug: Audio saved to \(debugURL.path)")
            #endif
            
            try await MainActor.run {
                guard !self.isCancelled else { return }
                
                self.analyzeAudioData(audioData, provider: provider)
                
                do {
                    audioPlayer = try AVAudioPlayer(data: audioData)
                    audioPlayer?.prepareToPlay()
                    
                    // Log audio player details
                    if let player = audioPlayer {
                        logger.info("🔊 Audio format: \(player.format)")
                        logger.info("⏱️ Duration: \(player.duration) seconds")
                        logger.info("🔢 Number of channels: \(player.numberOfChannels)")
                    }
                    
                    let success = audioPlayer?.play() ?? false
                    if success {
                        logger.info("▶️ Started playing audio")
                    } else {
                        logger.error("❌ AVAudioPlayer.play() returned false")
                        logger.error("📊 Audio data size: \(audioData.count) bytes")
                        self.speakWithApple(text, language: language)
                    }
                } catch {
                    logger.error("❌ Failed to create AVAudioPlayer: \(error)")
                    logger.error("📊 Audio data size: \(audioData.count) bytes")
                    logger.error("📄 First 20 bytes: \(audioData.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " "))")
                    self.speakWithApple(text, language: language)
                }
            }
        } catch {
            logger.error("❌ TTS error: \(error)")
            logger.error("❌ Error details: \(error.localizedDescription)")
            logger.info("🔄 Falling back to Apple System Voice")
            // Fallback to Apple TTS
            speakWithApple(text, language: language)
        }
    }
}

// MARK: - TTS Service Factory

@MainActor
final class TTSServiceFactory {
    private let youdaoService = YoudaoTTSService()
    private let bingService = BingTTSService()
    private let googleService = GoogleTTSService()
    private let baiduService = BaiduTTSService()
    
    func fetchAudio(
        text: String,
        language: String?,
        provider: TTSProvider,
        useAmericanAccent: Bool,
        disableCache: Bool = false
    ) async throws -> Data {
        switch provider {
        case .youdao:
            return try await youdaoService.fetchAudio(
                text: text,
                language: language,
                useAmericanAccent: useAmericanAccent,
                disableCache: disableCache
            )
        case .bing:
            return try await bingService.fetchAudio(
                text: text,
                language: language,
                useAmericanAccent: useAmericanAccent,
                disableCache: disableCache
            )
        case .google:
            return try await googleService.fetchAudio(
                text: text,
                language: language,
                useAmericanAccent: useAmericanAccent,
                disableCache: disableCache
            )
        case .baidu:
            return try await baiduService.fetchAudio(
                text: text,
                language: language,
                useAmericanAccent: useAmericanAccent,
                disableCache: disableCache
            )
        case .apple:
            throw TTSError.unsupportedProvider
        }
    }
}

enum TTSError: Error, LocalizedError {
    case unsupportedProvider
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case audioDecodeError
    case tokenExpired
    case tokenExtractionFailed(String)
    case webSocketError(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "Unsupported TTS provider"
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .audioDecodeError:
            return "Failed to decode audio data"
        case .tokenExpired:
            return "Token expired"
        case .tokenExtractionFailed(let msg):
            return "Token extraction failed: \(msg)"
        case .webSocketError(let msg):
            return "WebSocket error: \(msg)"
        }
    }
}

// MARK: - Youdao TTS Service

final class YoudaoTTSService {
    private let baseURL = "https://dict.youdao.com/dictvoice"
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "YoudaoTTS")
    
    private let uncachedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    
    func fetchAudio(
        text: String,
        language: String?,
        useAmericanAccent: Bool,
        disableCache: Bool = false
    ) async throws -> Data {
        let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let langCode = languageCode(for: language)
        let accentType = useAmericanAccent ? "2" : "1"
        
        guard let url = URL(string: "\(baseURL)?audio=\(encodedText)&le=\(langCode)&type=\(accentType)") else {
            logger.error("❌ Invalid URL")
            throw TTSError.invalidURL
        }
        
        logger.info("📡 Requesting Youdao TTS: \(url.absoluteString)")
        
        let session = disableCache ? uncachedSession : URLSession.shared
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("❌ Invalid response type")
            throw TTSError.invalidResponse
        }
        
        logger.info("📊 HTTP Status: \(httpResponse.statusCode), Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
        logger.info("📦 Data size: \(data.count) bytes")
        
        guard httpResponse.statusCode == 200 else {
            logger.error("❌ HTTP error: \(httpResponse.statusCode)")
            throw TTSError.invalidResponse
        }
        
        // Verify it's MP3 data
        if data.count > 2 {
            let header = data.prefix(2)
            if header[0] == 0xFF && (header[1] & 0xE0) == 0xE0 {
                logger.info("✅ Valid MP3 header detected")
            } else {
                logger.warning("⚠️ Data does not start with MP3 header")
            }
        }
        
        return data
    }
    
    private func languageCode(for language: String?) -> String {
        guard let language = language else { return "en" }
        
        let languageMap: [String: String] = [
            "en": "en",
            "zh": "zh",
            "zh-Hans": "zh",
            "zh-Hant": "zh",
            "ja": "ja",
            "ko": "ko",
            "fr": "fr",
            "de": "de",
            "es": "es",
            "ru": "ru",
        ]
        
        return languageMap[language] ?? "en"
    }
}

// MARK: - Baidu TTS Service

final class BaiduTTSService {
    private let baseURL = "https://fanyi.baidu.com/gettts"
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "BaiduTTS")
    
    private let uncachedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    
    func fetchAudio(
        text: String,
        language: String?,
        useAmericanAccent: Bool,
        disableCache: Bool = false
    ) async throws -> Data {
        // Baidu has 1000 character limit
        let trimmedText = String(text.prefix(1000))
        let encodedText = trimmedText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        var langCode = languageCode(for: language)
        
        // Handle UK accent
        if langCode == "en" && !useAmericanAccent {
            langCode = "uk"
        }
        
        let speed = (langCode == "zh") ? "5" : "3"
        
        guard let url = URL(string: "\(baseURL)?text=\(encodedText)&lan=\(langCode)&spd=\(speed)&source=web") else {
            logger.error("❌ Invalid URL")
            throw TTSError.invalidURL
        }
        
        logger.info("📡 Requesting Baidu TTS: \(url.absoluteString)")
        
        let session = disableCache ? uncachedSession : URLSession.shared
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("❌ Invalid response type")
            throw TTSError.invalidResponse
        }
        
        logger.info("📊 HTTP Status: \(httpResponse.statusCode), Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
        logger.info("📦 Data size: \(data.count) bytes")
        
        guard httpResponse.statusCode == 200 else {
            logger.error("❌ HTTP error: \(httpResponse.statusCode)")
            throw TTSError.invalidResponse
        }
        
        return data
    }
    
    private func languageCode(for language: String?) -> String {
        guard let language = language else { return "en" }
        
        let languageMap: [String: String] = [
            "en": "en",
            "zh": "zh",
            "zh-Hans": "zh",
            "zh-Hant": "zh",
            "ja": "jp",
            "ko": "kor",
            "fr": "fra",
            "de": "de",
            "es": "spa",
            "ru": "ru",
            "yue": "yue",
            "th": "th",
            "ar": "ara",
            "pt": "pt",
            "it": "it",
            "nl": "nl",
            "el": "el",
        ]
        
        return languageMap[language] ?? "en"
    }
}

// MARK: - Edge TTS Service
//
// Uses URLSession.webSocketTask (same networking stack as Google TTS) with
// Sec-MS-GEC DRM token authentication.  URLSession handles system proxies
// correctly, unlike NWConnection which caused POSIX 53 errors through
// Clash/V2Ray.

final class EdgeTTSService {
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "EdgeTTS")

    private let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private let chromiumFullVersion = "143.0.3650.75"
    private let secMsGecVersion = "1-143.0.3650.75"
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        + " (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0"

    func fetchAudio(text: String, language: String?, useAmericanAccent: Bool = true) async throws -> Data {
        logger.info("🌐 Starting Edge TTS (URLSession WebSocket)...")

        let connectionId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let secMsGec = generateSecMsGec()
        let muid = generateMUID()

        let urlString = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"
            + "?TrustedClientToken=\(trustedClientToken)"
            + "&ConnectionId=\(connectionId)"
            + "&Sec-MS-GEC=\(secMsGec)"
            + "&Sec-MS-GEC-Version=\(secMsGecVersion)"

        guard let url = URL(string: urlString) else {
            throw TTSError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(connectionId, forHTTPHeaderField: "X-ConnectionId")
        request.setValue("MUID=\(muid)", forHTTPHeaderField: "Cookie")

        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                defer { task.cancel(with: .goingAway, reason: nil) }

                // Send config
                try await task.send(.string(self.createConfigMessage()))
                self.logger.debug("📤 Config sent")

                // Send SSML
                let voiceName = Self.getVoiceName(language: language, useAmericanAccent: useAmericanAccent)
                let ssml = Self.generateSSML(text: text, voiceName: voiceName)
                try await task.send(.string(self.createSSMLMessage(ssml: ssml)))
                self.logger.debug("📤 SSML sent")

                // Receive audio
                self.logger.info("⏳ Receiving audio frames...")
                return try await self.receiveAudio(task)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                self.logger.error("⏰ Edge TTS timed out after 30s")
                throw TTSError.networkError(URLError(.timedOut))
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw TTSError.invalidResponse
            }
            return result
        }
    }

    // MARK: - Sec-MS-GEC Token

    /// Generate Sec-MS-GEC DRM token (SHA-256 of Windows epoch ticks + client token).
    private func generateSecMsGec() -> String {
        let unixTime = Int64(Date().timeIntervalSince1970)
        let windowsEpochOffset: Int64 = 11644473600
        let roundedSeconds = ((unixTime + windowsEpochOffset) / 300) * 300
        let ticks = roundedSeconds * 10_000_000
        let input = "\(ticks)\(trustedClientToken)"
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { String(format: "%02X", $0) }.joined()
    }

    /// Generate random 32-char uppercase hex MUID cookie value.
    private func generateMUID() -> String {
        (0..<16).map { _ in String(format: "%02X", UInt8.random(in: 0...255)) }.joined()
    }

    // MARK: - Audio Reception

    private func receiveAudio(_ task: URLSessionWebSocketTask) async throws -> Data {
        var audioData = Data()
        var msgCount = 0

        receiveLoop: while true {
            let message = try await task.receive()
            msgCount += 1

            switch message {
            case .data(let payload):
                guard payload.count >= 2 else { continue receiveLoop }
                let hdrLen = (Int(payload[0]) << 8) | Int(payload[1])
                let hdrEnd = 2 + hdrLen
                guard hdrEnd <= payload.count,
                      let hdr = String(data: payload[2..<hdrEnd], encoding: .utf8)
                else { continue receiveLoop }

                if hdr.contains("Path:audio"), hdrEnd < payload.count {
                    audioData.append(contentsOf: payload[hdrEnd...])
                    logger.debug("🎵 chunk \(payload.count - hdrEnd)B  total \(audioData.count)B")
                } else if hdr.contains("Path:turn.end") {
                    logger.info("✅ turn.end after \(msgCount) msgs")
                    break receiveLoop
                }

                if audioData.count > 10_000_000 {
                    logger.warning("⚠️ >10 MB, stopping")
                    break receiveLoop
                }

            case .string(let text):
                logger.debug("📨 text \(msgCount): \(text.prefix(80))")
                if text.contains("Path:turn.end") {
                    logger.info("✅ turn.end (text) after \(msgCount) msgs")
                    break receiveLoop
                }

            @unknown default:
                break
            }
        }

        logger.info("📊 total audio: \(audioData.count) bytes")
        guard !audioData.isEmpty else {
            logger.error("❌ No audio received")
            throw TTSError.invalidResponse
        }
        return audioData
    }

    // MARK: - Protocol Message Builders

    private func createConfigMessage() -> String {
        let config: [String: Any] = [
            "context": [
                "synthesis": [
                    "audio": [
                        "metadataoptions": [
                            "sentenceBoundaryEnabled": "false",
                            "wordBoundaryEnabled": "false",
                        ],
                        "outputFormat": "audio-24khz-48kbitrate-mono-mp3",
                    ],
                ],
            ],
        ]
        let json = String(data: try! JSONSerialization.data(withJSONObject: config), encoding: .utf8)!
        return "X-Timestamp:\(Self.getTimestamp())\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n\(json)"
    }

    private func createSSMLMessage(ssml: String) -> String {
        let requestId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "X-Timestamp:\(Self.getTimestamp())\r\nContent-Type:application/ssml+xml\r\nX-RequestId:\(requestId)\r\nPath:ssml\r\n\r\n\(ssml)"
    }

    private nonisolated static func generateSSML(text: String, voiceName: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
            + "<voice name='\(voiceName)'>"
            + "<prosody pitch='+0Hz' rate='+0%' volume='+0%'>\(escaped)</prosody>"
            + "</voice></speak>"
    }

    private nonisolated static func getVoiceName(language: String?, useAmericanAccent: Bool) -> String {
        let voiceMap: [String: (american: String, british: String)] = [
            "en":      ("en-US-AriaNeural", "en-GB-SoniaNeural"),
            "zh":      ("zh-CN-XiaoxiaoNeural", "zh-CN-XiaoxiaoNeural"),
            "zh-Hans": ("zh-CN-XiaoxiaoNeural", "zh-CN-XiaoxiaoNeural"),
            "zh-Hant": ("zh-TW-HsiaoChenNeural", "zh-TW-HsiaoChenNeural"),
            "ja":      ("ja-JP-NanamiNeural", "ja-JP-NanamiNeural"),
            "ko":      ("ko-KR-SunHiNeural", "ko-KR-SunHiNeural"),
            "fr":      ("fr-FR-DeniseNeural", "fr-FR-DeniseNeural"),
            "de":      ("de-DE-KatjaNeural", "de-DE-KatjaNeural"),
            "es":      ("es-ES-ElviraNeural", "es-ES-ElviraNeural"),
            "it":      ("it-IT-ElsaNeural", "it-IT-ElsaNeural"),
            "pt":      ("pt-BR-FranciscaNeural", "pt-BR-FranciscaNeural"),
            "ru":      ("ru-RU-SvetlanaNeural", "ru-RU-SvetlanaNeural"),
        ]
        let voices = voiceMap[language ?? "en"] ?? ("en-US-AriaNeural", "en-GB-SoniaNeural")
        return useAmericanAccent ? voices.american : voices.british
    }

    private nonisolated static func getTimestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}

// MARK: - Bing TTS Service (Redirects to Edge)

final class BingTTSService {
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "BingTTS")
    
    func fetchAudio(
        text: String,
        language: String?,
        useAmericanAccent: Bool = true,
        disableCache: Bool = false
    ) async throws -> Data {
        logger.info("🔄 Bing TTS using Edge TTS backend")
        let edgeService = EdgeTTSService()
        return try await edgeService.fetchAudio(text: text, language: language, useAmericanAccent: useAmericanAccent)
    }
}

// MARK: - Google TTS Service

final class GoogleTTSService {
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "GoogleTTS")
    
    private let uncachedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    func fetchAudio(
        text: String,
        language: String?,
        useAmericanAccent: Bool = true,
        disableCache: Bool = false
    ) async throws -> Data {
        logger.info("📡 Requesting Google TTS...")

        // Google TTS has 100 character limit per request
        let trimmedText = String(text.prefix(100))
        let langCode = googleLanguageCode(for: language, useAmericanAccent: useAmericanAccent)
        let encodedText = trimmedText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        // Use the translate_tts endpoint which directly returns MP3 audio.
        // The previous RPC batchexecute approach embedded audio as base64 inside
        // an escaped JSON string, and the regex failed to match the \" delimiters.
        guard let url = URL(string: "https://translate.google.com/translate_tts?ie=UTF-8&q=\(encodedText)&tl=\(langCode)&client=tw-ob") else {
            throw TTSError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://translate.google.com/", forHTTPHeaderField: "Referer")

        let session = disableCache ? uncachedSession : URLSession.shared
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }

        logger.info("📊 HTTP Status: \(httpResponse.statusCode), size: \(data.count) bytes")

        guard httpResponse.statusCode == 200, data.count > 100 else {
            logger.error("❌ HTTP error or empty response: \(httpResponse.statusCode)")
            throw TTSError.invalidResponse
        }

        return data
    }

    private func googleLanguageCode(for language: String?, useAmericanAccent: Bool) -> String {
        guard let language = language else { return useAmericanAccent ? "en" : "en-GB" }

        let languageMap: [String: String] = [
            "en": useAmericanAccent ? "en" : "en-GB",
            "zh": "zh-CN",
            "zh-Hans": "zh-CN",
            "zh-Hant": "zh-TW",
            "ja": "ja",
            "ko": "ko",
            "fr": "fr",
            "de": "de",
            "es": "es",
            "ru": "ru",
            "it": "it",
            "pt": "pt",
        ]

        return languageMap[language] ?? "en"
    }
}
