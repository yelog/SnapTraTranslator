import AVFoundation
import Foundation

@MainActor
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var downloadTask: URLSessionDataTask?

    /// Use local TTS to speak
    func speak(_ text: String, language: String?) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        if let language {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    /// Play audio from remote URL
    func playAudio(from url: URL) {
        stop()

        downloadTask = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }

            // Check for valid audio response
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                return
            }

            DispatchQueue.main.async { [weak self] in
                do {
                    self?.audioPlayer = try AVAudioPlayer(data: data)
                    self?.audioPlayer?.play()
                } catch {
                    print("Audio playback error: \(error)")
                }
            }
        }
        downloadTask?.resume()
    }

    /// Stop all playback
    func stop() {
        downloadTask?.cancel()
        downloadTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
