import AVFoundation
import Foundation
import Observation
import Speech

/// Crash-safe native iOS speech recognition service.
/// Lazily creates `AVAudioEngine` only AFTER permissions and `AVAudioSession` are active,
/// and validates hardware audio format before installing taps so no Objective-C NSException can occur.
@MainActor
@Observable
final class AionSpeechService {
    var transcript: String = ""
    var isRecording: Bool = false
    var audioLevel: CGFloat = 0.14
    var statusMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            Task { await startRecording() }
        }
    }

    func startRecording() async {
        statusMessage = nil

        // 1. Check Speech Recognition permission first
        let speechAuthorized = await requestSpeechAuthorization()
        guard speechAuthorized else {
            statusMessage = "Aktifkan izin Speech Recognition di Settings iPhone → Aion."
            return
        }

        // 2. Check Microphone permission
        let micAuthorized = await requestMicrophoneAuthorization()
        guard micAuthorized else {
            statusMessage = "Aktifkan izin Microphone di Settings iPhone → Aion."
            return
        }

        // 3. Resolve an available Speech Recognizer (fallback to en-US if current locale unavailable)
        let recognizer = SFSpeechRecognizer(locale: Locale.current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "id-ID"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

        guard let recognizer, recognizer.isAvailable else {
            statusMessage = "Speech recognition sedang tidak tersedia di perangkat ini."
            return
        }
        self.speechRecognizer = recognizer

        // 4. Clean any previous session safely
        stopRecording()

        do {
            // Configure & activate AVAudioSession BEFORE creating AVAudioEngine
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode

            // Validate input hardware format to prevent AVAudioEngine NSException crash
            let outputFormat = inputNode.outputFormat(forBus: 0)
            let inputFormat = inputNode.inputFormat(forBus: 0)
            let safeFormat: AVAudioFormat?
            if outputFormat.sampleRate > 0 && outputFormat.channelCount > 0 {
                safeFormat = outputFormat
            } else if inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 {
                safeFormat = inputFormat
            } else {
                statusMessage = "Input mikrofon tidak terdeteksi (format audio tidak valid)."
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = false
            }
            self.recognitionRequest = request
            self.audioEngine = engine

            inputNode.removeTap(onBus: 0)
            let box = SpeechRequestBox(request: request)
            Self.installSafeTap(on: inputNode, format: safeFormat, requestBox: box) { [weak self] rms in
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    self.audioLevel = min(1.0, max(0.14, CGFloat(rms * 8.0)))
                }
            }

            engine.prepare()
            try engine.start()
            isRecording = true
            AionHaptics.medium()

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let formatted = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let errorDesc = error?.localizedDescription

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let formatted, !formatted.isEmpty {
                        self.transcript = formatted
                    }
                    if isFinal {
                        self.stopRecording()
                    } else if let errorDesc, self.isRecording {
                        // Ignore benign cancellation errors when user taps stop
                        if !errorDesc.lowercased().contains("cancel") {
                            self.statusMessage = errorDesc
                        }
                        self.stopRecording()
                    }
                }
            }
        } catch {
            statusMessage = "Gagal mengaktifkan mikrofon: \(error.localizedDescription)"
            stopRecording()
        }
    }

    func stopRecording() {
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isRecording = false
        audioLevel = 0.14

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestSpeechAuthorization() async -> Bool {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return true }
        if current == .denied || current == .restricted { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    nonisolated private static func installSafeTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat?,
        requestBox: SpeechRequestBox,
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

private final class SpeechRequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }
}
