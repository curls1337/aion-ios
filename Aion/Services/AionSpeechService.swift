import AVFoundation
import Foundation
import Observation
import Speech

/// Non-isolated bridge that keeps ALL Apple TCC, Speech, and Realtime Audio callbacks
/// strictly OUTSIDE `@MainActor` isolation so Swift 6 NEVER inserts `_dispatch_assert_queue_main`
/// checks on Apple's background queues (which previously caused instant EXC_BREAKPOINT crashes).
private enum SpeechAudioBridge {
    static func requestSpeechAuth() async -> Bool {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return true }
        if current == .denied || current == .restricted { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static func requestMicAuth() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    static func installTap(
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

    static func startRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onUpdate: @escaping @Sendable (_ text: String?, _ isFinal: Bool, _ errorText: String?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorText = error?.localizedDescription
            onUpdate(text, isFinal, errorText)
        }
    }

    private static func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
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

/// Crash-safe native iOS speech recognition service (Swift 6 strict concurrency verified).
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

        let speechAuthorized = await SpeechAudioBridge.requestSpeechAuth()
        guard speechAuthorized else {
            statusMessage = "Aktifkan izin Speech Recognition di Settings iPhone → Aion."
            return
        }

        let micAuthorized = await SpeechAudioBridge.requestMicAuth()
        guard micAuthorized else {
            statusMessage = "Aktifkan izin Microphone di Settings iPhone → Aion."
            return
        }

        let recognizer = SFSpeechRecognizer(locale: Locale.current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "id-ID"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

        guard let recognizer, recognizer.isAvailable else {
            statusMessage = "Speech recognition sedang tidak tersedia di perangkat ini."
            return
        }
        self.speechRecognizer = recognizer

        stopRecording()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .duckOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode

            let outputFormat = inputNode.outputFormat(forBus: 0)
            let inputFormat = inputNode.inputFormat(forBus: 0)
            let safeFormat: AVAudioFormat?
            if outputFormat.sampleRate > 0 && outputFormat.channelCount > 0 {
                safeFormat = outputFormat
            } else if inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 {
                safeFormat = inputFormat
            } else {
                statusMessage = "Input mikrofon tidak terdeteksi. Pastikan mikrofon tidak dipakai aplikasi lain."
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.recognitionRequest = request
            self.audioEngine = engine

            inputNode.removeTap(onBus: 0)
            let box = SpeechRequestBox(request: request)
            SpeechAudioBridge.installTap(on: inputNode, format: safeFormat, requestBox: box) { [weak self] rms in
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    self.audioLevel = min(1.0, max(0.14, CGFloat(rms * 8.0)))
                }
            }

            engine.prepare()
            try engine.start()
            isRecording = true
            AionHaptics.medium()

            recognitionTask = SpeechAudioBridge.startRecognitionTask(recognizer: recognizer, request: request) { [weak self] text, isFinal, errorText in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let text, !text.isEmpty {
                        self.transcript = text
                    }
                    if isFinal {
                        self.stopRecording()
                    } else if let errorText, self.isRecording {
                        if !errorText.lowercased().contains("cancel") {
                            self.statusMessage = errorText
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
}
