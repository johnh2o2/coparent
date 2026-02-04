import Foundation
import Speech
import AVFoundation

/// Service for handling voice input using iOS Speech framework
@Observable
final class VoiceInputService: NSObject {
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // State
    var isAuthorized = false
    var isRecording = false
    var transcribedText = ""
    var errorMessage: String?

    // Callback for real-time transcription
    var onTranscriptionUpdate: ((String) -> Void)?

    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
        speechRecognizer?.delegate = self
    }

    // MARK: - Authorization

    /// Request speech recognition authorization
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    switch status {
                    case .authorized:
                        self.isAuthorized = true
                        continuation.resume(returning: true)
                    case .denied, .restricted, .notDetermined:
                        self.isAuthorized = false
                        self.errorMessage = "Speech recognition not authorized"
                        continuation.resume(returning: false)
                    @unknown default:
                        self.isAuthorized = false
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    /// Request microphone authorization
    func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if !granted {
                        self.errorMessage = "Microphone access not granted"
                    }
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Recording

    /// Start recording and transcribing
    func startRecording() throws {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw VoiceInputError.speechRecognizerUnavailable
        }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            throw VoiceInputError.requestCreationFailed
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true

        // Get input node
        let inputNode = audioEngine.inputNode

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            var isFinal = false

            if let result = result {
                let transcription = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcribedText = transcription
                    self.onTranscriptionUpdate?(transcription)
                }
                isFinal = result.isFinal
            }

            if error != nil || isFinal {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self.recognitionRequest = nil
                self.recognitionTask = nil

                DispatchQueue.main.async {
                    self.isRecording = false
                }
            }
        }

        // Configure audio tap
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()

        DispatchQueue.main.async {
            self.isRecording = true
            self.transcribedText = ""
            self.errorMessage = nil
        }
    }

    /// Stop recording
    func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()

        DispatchQueue.main.async {
            self.isRecording = false
        }
    }

    /// Toggle recording state
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            do {
                try startRecording()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Utilities

    /// Clear transcribed text
    func clearTranscription() {
        transcribedText = ""
    }

    /// Check if speech recognition is available
    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension VoiceInputService: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available {
            DispatchQueue.main.async {
                self.errorMessage = "Speech recognition temporarily unavailable"
            }
        }
    }
}

// MARK: - Errors

enum VoiceInputError: Error, LocalizedError {
    case speechRecognizerUnavailable
    case requestCreationFailed
    case audioSessionFailed
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .speechRecognizerUnavailable:
            return "Speech recognition is not available"
        case .requestCreationFailed:
            return "Could not create speech recognition request"
        case .audioSessionFailed:
            return "Could not configure audio session"
        case .notAuthorized:
            return "Speech recognition is not authorized"
        }
    }
}
