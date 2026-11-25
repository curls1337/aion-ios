import AVFoundation
import Foundation
import Observation
import Speech

@MainActor
@Observable
final class AionSpeechService {
    var transcript: String = ""
    var isRecording: Bool = false
    var audioLevel: CGFloat = 0.12
    var permissionMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            Task { await startRecording() }
        }
    }

    func startRecording() async {
        permissionMessage = nil
        let speechAuthorized = await requestSpeechAuthorization()
        guard speechAuthorized else {
            permissionMessage = "Enable Speech Recognition in iOS Settings to dictate prompts."
            return
        }

        let micAuthorized = await requestMicrophoneAuthorization()
        guard micAuthorized else {
            permissionMessage = "Enable Microphone access in iOS Settings to use Voice Mode."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionTask?.cancel()
            recognitionTask = nil

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            let box = UncheckedRequestBox(request: request)
            Self.installAudioTap(on: inputNode, format: recordingFormat, requestBox: box) { [weak self] rms in
                Task { @MainActor [weak self] in
                    self?.audioLevel = min(1.0, max(0.12, CGFloat(rms * 8.0)))
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            AionHaptics.medium()

            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let hasError = error != nil
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let text {
                        self.transcript = text
                    }
                    if hasError || isFinal {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            permissionMessage = "Could not start audio engine: \(error.localizedDescription)"
            stopRecording()
        }
    }

    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        audioLevel = 0.12
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    nonisolated private static func installAudioTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        requestBox: UncheckedRequestBox,
        onRMS: @escaping @Sendable (Float) -> Void
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            requestBox.request.append(buffer)
            onRMS(computeRMS(buffer: buffer))
        }
    }

    nonisolated private static func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        return sqrt(sum / Float(frameLength))
    }
}

private final class UncheckedRequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }
}
