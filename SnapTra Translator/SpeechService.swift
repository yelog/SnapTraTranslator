import AVFoundation
import Foundation
import os.log

@MainActor
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private let ttsServiceFactory = TTSServiceFactory()
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "SpeechService")
    
    func speak(
        _ text: String,
        language: String?,
        provider: TTSProvider = .apple,
        useAmericanAccent: Bool = true
    ) {
        logger.info("🔊 Speaking with provider: \(provider.rawValue), text: \(text)")
        
        // Stop current playback
        stopSpeaking()
        
        switch provider {
        case .apple:
            logger.info("🎵 Using Apple System Voice")
            speakWithApple(text, language: language)
        case .youdao, .bing, .google, .baidu, .edge:
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
                // Analyze audio data
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
    private let edgeService = EdgeTTSService()
    private let googleService = GoogleTTSService()
    private let baiduService = BaiduTTSService()
    
    func fetchAudio(
        text: String,
        language: String?,
        provider: TTSProvider,
        useAmericanAccent: Bool
    ) async throws -> Data {
        switch provider {
        case .youdao:
            return try await youdaoService.fetchAudio(
                text: text,
                language: language,
                useAmericanAccent: useAmericanAccent
            )
        case .bing:
            return try await bingService.fetchAudio(
                text: text,
                language: language
            )
        case .edge:
            return try await edgeService.fetchAudio(
                text: text,
                language: language
            )
        case .google:
            return try await googleService.fetchAudio(
                text: text,
                language: language
            )
        case .baidu:
            return try await baiduService.fetchAudio(
                text: text,
                language: language,
                useAmericanAccent: useAmericanAccent
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
    
    func fetchAudio(
        text: String,
        language: String?,
        useAmericanAccent: Bool
    ) async throws -> Data {
        let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let langCode = languageCode(for: language)
        let accentType = useAmericanAccent ? "2" : "1"
        
        guard let url = URL(string: "\(baseURL)?audio=\(encodedText)&le=\(langCode)&type=\(accentType)") else {
            logger.error("❌ Invalid URL")
            throw TTSError.invalidURL
        }
        
        logger.info("📡 Requesting Youdao TTS: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
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
    
    func fetchAudio(
        text: String,
        language: String?,
        useAmericanAccent: Bool
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
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
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

// MARK: - Edge TTS Service (Fixed WebSocket Implementation)

final class EdgeTTSService {
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "EdgeTTS")
    private let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    
    func fetchAudio(
        text: String,
        language: String?
    ) async throws -> Data {
        logger.info("🌐 Starting Edge TTS WebSocket connection...")

        // Each connection requires a unique ConnectionId (matches edge-tts Python spec)
        let connectionId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let wsURL = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"
            + "?TrustedClientToken=\(trustedClientToken)"
            + "&Retry-After=3600"
            + "&ConnectionId=\(connectionId)"

        guard let url = URL(string: wsURL) else {
            throw TTSError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(connectionId, forHTTPHeaderField: "X-ConnectionId")
        
        let webSocketTask = URLSession.shared.webSocketTask(with: request)
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    var audioData = Data()
                    let voiceName = self.getVoiceName(language: language)
                    let ssml = self.generateSSML(text: text, voiceName: voiceName)
                    
                    logger.info("🔌 Connecting to WebSocket...")
                    webSocketTask.resume()
                    
                    // Wait for connection
                    try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                    
                    // Send config message
                    let configMessage = self.createConfigMessage()
                    logger.debug("📤 Sending config message")
                    try await webSocketTask.send(.string(configMessage))
                    
                    // Send SSML message
                    let ssmlMessage = self.createSSMLMessage(ssml: ssml)
                    logger.debug("📤 Sending SSML message")
                    try await webSocketTask.send(.string(ssmlMessage))
                    
                    logger.info("⏳ Waiting for audio data...")

                    // Receive audio data with timeout
                    let startTime = Date()
                    var isComplete = false
                    var messageCount = 0

                    while !isComplete && Date().timeIntervalSince(startTime) < 30 { // 30s timeout
                        do {
                            let message = try await webSocketTask.receive()
                            messageCount += 1

                            switch message {
                            case .data(let data):
                                // Edge TTS binary frame structure:
                                //   [2 bytes: header length N (big-endian uint16)]
                                //   [N bytes: text header, e.g. "Path:audio\r\n..."]
                                //   [remaining bytes: actual MP3 audio data]
                                guard data.count >= 2 else { break }
                                let headerLen = (Int(data[0]) << 8) | Int(data[1])
                                let headerEnd = 2 + headerLen
                                guard headerEnd <= data.count else { break }
                                let headerData = data[2..<headerEnd]
                                guard let headerText = String(data: headerData, encoding: .utf8) else { break }

                                if headerText.contains("Path:audio") && headerEnd < data.count {
                                    // Strip the binary header, append only the raw MP3 bytes
                                    audioData.append(contentsOf: data[headerEnd...])
                                    logger.debug("🎵 Audio chunk: \(data.count - headerEnd) bytes (total: \(audioData.count))")
                                } else if headerText.contains("Path:turn.end") {
                                    logger.info("✅ Received turn.end (binary)")
                                    isComplete = true
                                }

                            case .string(let text):
                                logger.debug("📨 Received string message (#\(messageCount)): \(text.prefix(100))")
                                if text.contains("Path:turn.end") {
                                    logger.info("✅ Received turn.end signal")
                                    isComplete = true
                                }
                            }

                            // Safety check
                            if audioData.count > 10_000_000 { // 10MB limit
                                logger.warning("⚠️ Audio data exceeds 10MB, stopping")
                                isComplete = true
                            }
                        } catch {
                            logger.error("❌ WebSocket receive error: \(error)")
                            break
                        }
                    }
                    
                    webSocketTask.cancel(with: .normalClosure, reason: nil)
                    
                    logger.info("📊 Total messages received: \(messageCount)")
                    logger.info("📊 Total audio data: \(audioData.count) bytes")
                    
                    if audioData.count > 0 {
                        logger.info("✅ Edge TTS: Successfully received audio")
                        continuation.resume(returning: audioData)
                    } else {
                        logger.error("❌ No audio data received")
                        throw TTSError.invalidResponse
                    }
                    
                } catch {
                    webSocketTask.cancel(with: .normalClosure, reason: nil)
                    logger.error("❌ Edge TTS error: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func createConfigMessage() -> String {
        let timestamp = getTimestamp()
        // context must be a dictionary (not an array) — matches edge-tts Python spec:
        // {"context":{"synthesis":{"audio":{"metadataoptions":{...},"outputFormat":"..."}}}}
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
        let configData = try! JSONSerialization.data(withJSONObject: config)
        let configString = String(data: configData, encoding: .utf8)!
        return "X-Timestamp:\(timestamp)\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n\(configString)"
    }
    
    private func createSSMLMessage(ssml: String) -> String {
        let timestamp = getTimestamp()
        let requestId = UUID().uuidString.lowercased()
        
        return "X-Timestamp:\(timestamp)\r\nContent-Type:application/ssml+xml\r\nX-RequestId:\(requestId)\r\nPath:ssml\r\n\r\n\(ssml)"
    }
    
    private func generateSSML(text: String, voiceName: String) -> String {
        let escapedText = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        
        return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'><voice name='\(voiceName)'><prosody pitch='+0Hz' rate='+0%' volume='+0%'>\(escapedText)</prosody></voice></speak>"
    }
    
    private func getVoiceName(language: String?) -> String {
        let langCode = language ?? "en"
        
        let voiceMap: [String: String] = [
            "en": "en-US-AriaNeural",
            "zh": "zh-CN-XiaoxiaoNeural",
            "zh-Hans": "zh-CN-XiaoxiaoNeural",
            "zh-Hant": "zh-TW-HsiaoChenNeural",
            "ja": "ja-JP-NanamiNeural",
            "ko": "ko-KR-SunHiNeural",
            "fr": "fr-FR-DeniseNeural",
            "de": "de-DE-KatjaNeural",
            "es": "es-ES-ElviraNeural",
            "it": "it-IT-ElsaNeural",
            "pt": "pt-BR-FranciscaNeural",
            "ru": "ru-RU-SvetlanaNeural",
        ]
        
        return voiceMap[langCode] ?? "en-US-AriaNeural"
    }
    
    private func getTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

// MARK: - Bing TTS Service (Redirects to Edge)

final class BingTTSService {
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "BingTTS")
    
    func fetchAudio(
        text: String,
        language: String?
    ) async throws -> Data {
        logger.info("🔄 Bing TTS using Edge TTS backend")
        let edgeService = EdgeTTSService()
        return try await edgeService.fetchAudio(text: text, language: language)
    }
}

// MARK: - Google TTS Service

final class GoogleTTSService {
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "GoogleTTS")

    func fetchAudio(
        text: String,
        language: String?
    ) async throws -> Data {
        logger.info("📡 Requesting Google TTS...")

        // Google TTS has 100 character limit per request
        let trimmedText = String(text.prefix(100))
        let langCode = googleLanguageCode(for: language)
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

        let (data, response) = try await URLSession.shared.data(for: request)

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

    private func googleLanguageCode(for language: String?) -> String {
        guard let language = language else { return "en" }

        let languageMap: [String: String] = [
            "en": "en",
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
