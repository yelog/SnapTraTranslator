import AVFoundation
import CryptoKit
import Foundation
import os.log

@MainActor
protocol TTSServiceFetching: AnyObject {
    func fetchAudio(
        text: String,
        language: String?,
        provider: TTSProvider,
        useAmericanAccent: Bool,
        disableCache: Bool
    ) async throws -> Data
}

@MainActor
protocol SpeechAudioOutput: AnyObject {
    func stop()
    func playApple(text: String, language: String?)
    func playOnlineAudio(_ data: Data) throws -> Bool
}

@MainActor
protocol SpeechAudioStartObserving: AnyObject {
    func setAppleDidStartHandler(_ handler: @escaping @MainActor () -> Void)
}

protocol TTSDebugAudioDumping: Sendable {
    func dump(_ data: Data, provider: TTSProvider, generation: UInt64) async
}

actor TTSDebugAudioDumper: TTSDebugAudioDumping {
    private let directory: URL

    init(
        directory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapTraTranslator/TTS", isDirectory: true)
    ) {
        self.directory = directory
    }

    func dump(_ data: Data, provider: TTSProvider, generation: UInt64) async {
        #if DEBUG
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory.appendingPathComponent(
                "\(provider.rawValue)-\(generation)-\(UUID().uuidString).mp3"
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Debug artifacts must never affect speech playback.
        }
        #endif
    }
}

@MainActor
final class AVFoundationSpeechAudioOutput: NSObject, SpeechAudioOutput, SpeechAudioStartObserving {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var nextAppleDidStartHandler: (@MainActor () -> Void)?
    private var appleDidStartHandlers: [ObjectIdentifier: @MainActor () -> Void] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        appleDidStartHandlers.removeAll()
        nextAppleDidStartHandler = nil
        audioPlayer?.stop()
        audioPlayer = nil
    }

    func setAppleDidStartHandler(_ handler: @escaping @MainActor () -> Void) {
        nextAppleDidStartHandler = handler
    }

    func playApple(text: String, language: String?) {
        let utterance = AVSpeechUtterance(string: text)
        if let language {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        if let handler = nextAppleDidStartHandler {
            appleDidStartHandlers[ObjectIdentifier(utterance)] = handler
        }
        nextAppleDidStartHandler = nil
        synthesizer.speak(utterance)
    }

    func playOnlineAudio(_ data: Data) throws -> Bool {
        let player = try AVAudioPlayer(data: data)
        player.prepareToPlay()
        guard player.play(), player.isPlaying else {
            player.stop()
            return false
        }
        audioPlayer = player
        return true
    }

    private func handleAppleDidStart(identifier: ObjectIdentifier) {
        let handler = appleDidStartHandlers.removeValue(forKey: identifier)
        handler?()
    }
}

extension AVFoundationSpeechAudioOutput: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.handleAppleDidStart(identifier: identifier)
        }
    }
}

@MainActor
final class SpeechService {
    private let fetcher: any TTSServiceFetching
    private let output: any SpeechAudioOutput
    private let debugDumper: (any TTSDebugAudioDumping)?
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "SpeechService")
    private var activeTask: Task<Void, Never>?
    private var requestGeneration: UInt64 = 0

    convenience init() {
        #if DEBUG
        let debugDumper: (any TTSDebugAudioDumping)? = TTSDebugAudioDumper()
        #else
        let debugDumper: (any TTSDebugAudioDumping)? = nil
        #endif
        self.init(
            fetcher: TTSServiceFactory(),
            output: AVFoundationSpeechAudioOutput(),
            debugDumper: debugDumper
        )
    }

    init(
        fetcher: any TTSServiceFetching,
        output: any SpeechAudioOutput,
        debugDumper: (any TTSDebugAudioDumping)?
    ) {
        self.fetcher = fetcher
        self.output = output
        self.debugDumper = debugDumper
    }

    func speak(
        _ text: String,
        language: String?,
        provider: TTSProvider = .apple,
        useAmericanAccent: Bool = true,
        performance: LookupPerformanceContext? = nil
    ) {
        logger.info("🔊 Speaking with provider: \(provider.rawValue)")
        let generation = beginRequest()

        switch provider {
        case .apple:
            logger.info("🎵 Using Apple System Voice")
            submitAppleSpeech(
                text,
                language: language,
                generation: generation,
                performance: performance
            )
        case .youdao, .bing, .google, .baidu:
            logger.info("🌐 Using online TTS: \(provider.displayName)")
            performance?.begin(.ttsFetch)
            let task = Task { [weak self] in
                guard let self else { return }
                await speakWithOnlineService(
                    text,
                    language: language,
                    provider: provider,
                    useAmericanAccent: useAmericanAccent,
                    generation: generation,
                    performance: performance
                )
            }
            activeTask = task
        }
    }

    func stopSpeaking() {
        requestGeneration &+= 1
        activeTask?.cancel()
        activeTask = nil
        output.stop()
    }

    private func beginRequest() -> UInt64 {
        requestGeneration &+= 1
        activeTask?.cancel()
        activeTask = nil
        output.stop()
        return requestGeneration
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        requestGeneration == generation && !Task.isCancelled
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
    
    private func submitAppleSpeech(
        _ text: String,
        language: String?,
        generation: UInt64,
        performance: LookupPerformanceContext?
    ) {
        guard isCurrent(generation) else { return }

        performance?.begin(.ttsStart)
        if let observer = output as? any SpeechAudioStartObserving {
            observer.setAppleDidStartHandler { [weak self] in
                guard let self, self.isCurrent(generation) else { return }
                performance?.end(.ttsStart, outcome: .succeeded)
                performance?.markAudioStart(.appleDidStart)
            }
        }
        output.playApple(text: text, language: language)

        // Custom outputs that cannot report didStart retain the old submission proxy.
        if !(output is any SpeechAudioStartObserving) {
            performance?.end(.ttsStart, outcome: .succeeded)
            performance?.markAudioStart(.appleSubmissionProxy)
        }
    }

    private func speakWithOnlineService(
        _ text: String,
        language: String?,
        provider: TTSProvider,
        useAmericanAccent: Bool,
        generation: UInt64,
        performance: LookupPerformanceContext?
    ) async {
        defer {
            if requestGeneration == generation {
                activeTask = nil
            }
        }

        do {
            logger.info("📡 Fetching audio from \(provider.displayName)...")
            let audioData = try await fetcher.fetchAudio(
                text: text,
                language: language,
                provider: provider,
                useAmericanAccent: useAmericanAccent,
                disableCache: false
            )
            guard isCurrent(generation) else {
                performance?.end(.ttsFetch, outcome: .superseded)
                return
            }
            performance?.end(.ttsFetch, outcome: .succeeded)

            logger.info("✅ Successfully fetched \(audioData.count) bytes from \(provider.displayName)")

            analyzeAudioData(audioData, provider: provider)
            performance?.begin(.ttsStart)

            do {
                let playAccepted = try output.playOnlineAudio(audioData)
                guard isCurrent(generation) else { return }
                if playAccepted {
                    logger.info("▶️ Online audio playback accepted")
                    performance?.end(.ttsStart, outcome: .succeeded)
                    performance?.markAudioStart(.playAccepted)
                } else {
                    logger.error("❌ Online audio playback was not accepted")
                    performance?.end(.ttsStart, outcome: .failed)
                    submitAppleSpeech(
                        text,
                        language: language,
                        generation: generation,
                        performance: performance
                    )
                }
                scheduleDebugDump(audioData, provider: provider, generation: generation)
            } catch {
                let cancelled = Self.isCancellation(error) || Task.isCancelled
                performance?.end(
                    .ttsStart,
                    outcome: cancelled ? .cancelled : .failed
                )
                guard isCurrent(generation), !cancelled else { return }
                logger.error("❌ Failed to create or play online audio: \(error.localizedDescription)")
                submitAppleSpeech(
                    text,
                    language: language,
                    generation: generation,
                    performance: performance
                )
                scheduleDebugDump(audioData, provider: provider, generation: generation)
            }
        } catch {
            let cancelled = Self.isCancellation(error) || Task.isCancelled
            let outcome: LookupPerformanceOutcome = isCurrent(generation)
                ? (cancelled ? .cancelled : .failed)
                : .superseded
            performance?.end(.ttsFetch, outcome: outcome)

            guard isCurrent(generation), !cancelled else { return }
            logger.error("❌ TTS error: \(error)")
            logger.info("🔄 Falling back to Apple System Voice")
            submitAppleSpeech(
                text,
                language: language,
                generation: generation,
                performance: performance
            )
        }
    }

    private func scheduleDebugDump(
        _ data: Data,
        provider: TTSProvider,
        generation: UInt64
    ) {
        guard isCurrent(generation), let debugDumper else { return }
        Task(priority: .utility) {
            await debugDumper.dump(data, provider: provider, generation: generation)
        }
    }

    private nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if let ttsError = error as? TTSError,
           case .networkError(let underlying) = ttsError {
            return isCancellation(underlying)
        }
        return false
    }
}

// MARK: - TTS Service Factory

@MainActor
final class TTSServiceFactory: TTSServiceFetching {
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
    private let session: URLSession
    private let uncachedSession: URLSession

    init(
        session: URLSession = .shared,
        uncachedSession: URLSession = SharedURLSession.uncached
    ) {
        self.session = session
        self.uncachedSession = uncachedSession
    }

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
        
        let selectedSession = disableCache ? uncachedSession : session
        let (data, response) = try await selectedSession.data(from: url)
        
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
    private let session: URLSession
    private let uncachedSession: URLSession

    init(
        session: URLSession = .shared,
        uncachedSession: URLSession = SharedURLSession.uncached
    ) {
        self.session = session
        self.uncachedSession = uncachedSession
    }

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
        
        let selectedSession = disableCache ? uncachedSession : session
        let (data, response) = try await selectedSession.data(from: url)
        
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

protocol TTSWebSocketTasking: AnyObject, Sendable {
    nonisolated func resume()
    nonisolated func send(_ message: URLSessionWebSocketTask.Message) async throws
    nonisolated func receive() async throws -> URLSessionWebSocketTask.Message
    nonisolated func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

protocol TTSWebSocketTaskCreating: Sendable {
    nonisolated func makeTask(for request: URLRequest) -> any TTSWebSocketTasking
}

extension URLSessionWebSocketTask: TTSWebSocketTasking {}

struct URLSessionTTSWebSocketTaskFactory: TTSWebSocketTaskCreating {
    let session: URLSession

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated func makeTask(for request: URLRequest) -> any TTSWebSocketTasking {
        session.webSocketTask(with: request)
    }
}

final class EdgeTTSService {
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "EdgeTTS")
    private let taskFactory: any TTSWebSocketTaskCreating
    private let timeoutNanoseconds: UInt64

    private let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private let secMsGecVersion = "1-143.0.3650.75"
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        + " (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0"

    init(
        taskFactory: any TTSWebSocketTaskCreating = URLSessionTTSWebSocketTaskFactory(),
        timeoutNanoseconds: UInt64 = 30_000_000_000
    ) {
        self.taskFactory = taskFactory
        self.timeoutNanoseconds = timeoutNanoseconds
    }

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

        let socket = taskFactory.makeTask(for: request)
        socket.resume()

        return try await withTaskCancellationHandler {
            defer { socket.cancel(with: .normalClosure, reason: nil) }
            return try await raceAudioAgainstTimeout(
                socket: socket,
                text: text,
                language: language,
                useAmericanAccent: useAmericanAccent
            )
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
    }

    private func raceAudioAgainstTimeout(
        socket: any TTSWebSocketTasking,
        text: String,
        language: String?,
        useAmericanAccent: Bool
    ) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await socket.send(.string(self.createConfigMessage()))
                self.logger.debug("📤 Config sent")

                let voiceName = Self.getVoiceName(
                    language: language,
                    useAmericanAccent: useAmericanAccent
                )
                let ssml = Self.generateSSML(text: text, voiceName: voiceName)
                try await socket.send(.string(self.createSSMLMessage(ssml: ssml)))
                self.logger.debug("📤 SSML sent")

                self.logger.info("⏳ Receiving audio frames...")
                return try await self.receiveAudio(socket)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: self.timeoutNanoseconds)
                self.logger.error("⏰ Edge TTS timed out")
                // Closing the socket before throwing is what unblocks a pending receive.
                socket.cancel(with: .goingAway, reason: nil)
                throw TTSError.networkError(URLError(.timedOut))
            }

            do {
                guard let result = try await group.next() else {
                    throw TTSError.invalidResponse
                }
                group.cancelAll()
                return result
            } catch {
                socket.cancel(with: .goingAway, reason: nil)
                group.cancelAll()
                throw error
            }
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

    private func receiveAudio(_ task: any TTSWebSocketTasking) async throws -> Data {
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
        // Build the JSON safely. The payload is a static literal dictionary, so
        // serialization is expected to succeed, but we avoid `try!`/`!` so that
        // an unexpected failure can't crash the entire app process.
        let json: String
        if let data = try? JSONSerialization.data(withJSONObject: config),
           let string = String(data: data, encoding: .utf8) {
            json = string
        } else {
            logger.error("Failed to serialize TTS config payload; falling back to empty config")
            json = "{}"
        }
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
    private let edgeService: EdgeTTSService

    init(edgeService: EdgeTTSService = EdgeTTSService()) {
        self.edgeService = edgeService
    }

    func fetchAudio(
        text: String,
        language: String?,
        useAmericanAccent: Bool = true,
        disableCache: Bool = false
    ) async throws -> Data {
        logger.info("🔄 Bing TTS using Edge TTS backend")
        return try await edgeService.fetchAudio(text: text, language: language, useAmericanAccent: useAmericanAccent)
    }
}

// MARK: - Google TTS Service

final class GoogleTTSService {
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "GoogleTTS")
    private let session: URLSession
    private let uncachedSession: URLSession

    init(
        session: URLSession = .shared,
        uncachedSession: URLSession = SharedURLSession.uncached
    ) {
        self.session = session
        self.uncachedSession = uncachedSession
    }

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

        let selectedSession = disableCache ? uncachedSession : session
        let (data, response) = try await selectedSession.data(for: request)

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
