import ExpoModulesCore
import Speech
import AVFoundation

public class ExpoSpeechTranscriberModule: Module {
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var bufferRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var bufferRecognitionTask: SFSpeechRecognitionTask?
    private var startedListening = false
    private var currentLocale: Locale = Locale(identifier: "en_US") // Default to English

    // Stored as Any? because SpeechAnalyzer/AnalyzerInput are iOS 26+ only.
    // Stored properties cannot be @available-gated, so we erase the type.
    private var bufferAnalyzer: Any?
    private var bufferStreamContinuation: Any?
    private var bufferAnalysisTask: Task<Void, Never>?

    public func definition() -> ModuleDefinition {
        Name("ExpoSpeechTranscriber")

        Events("onTranscriptionProgress", "onTranscriptionError")

        // expose realtime recording/transcription
        AsyncFunction("recordRealTimeAndTranscribe") { () async -> Void in
            await self.recordRealTimeAndTranscribe()
        }

        // Method 2: Transcribe from URL using SFSpeechRecognizer (iOS 13+)
        AsyncFunction("transcribeAudioWithSFRecognizer") { (audioFilePath: String) async throws -> String in
            let url: URL
            if audioFilePath.hasPrefix("file://") {
                url = URL(string: audioFilePath)!
            } else {
                url = URL(fileURLWithPath: audioFilePath)
            }
            return await self.transcribeAudio(url: url)
        }

        // Method 3: Transcribe from URL using SpeechAnalyzer (iOS 26+)
        AsyncFunction("transcribeAudioWithAnalyzer") { (audioFilePath: String) async throws -> String in
            #if SPEECH_ANALYZER_AVAILABLE
            if #available(iOS 26.0, *) {
                let url: URL
                if audioFilePath.hasPrefix("file://") {
                    url = URL(string: audioFilePath)!
                } else {
                    url = URL(fileURLWithPath: audioFilePath)
                }
                return try await self.transcribeAudioWithAnalyzer(url: url)
            }
            #endif
            throw NSError(domain: "ExpoSpeechTranscriber", code: 501,
                          userInfo: [NSLocalizedDescriptionKey: "SpeechAnalyzer requires iOS 26.0 or later"])
        }

        AsyncFunction("requestPermissions") { () async -> String in
            return await self.requestTranscribePermissions()
        }

        AsyncFunction("requestMicrophonePermissions") { () async -> String in
            return await self.requestMicrophonePermissions()
        }

        Function("stopListening") { () -> Void in
            return self.stopListening()
        }

        Function("isRecording") { () -> Bool in
            return self.isRecording()
        }

        Function("isAnalyzerAvailable") { () -> Bool in
            #if SPEECH_ANALYZER_AVAILABLE
            if #available(iOS 26.0, *) {
                return true
            }
            #endif
            return false
        }

        AsyncFunction("realtimeBufferTranscribeBase64") { (base64: String, sampleRate: Double) async -> Void in
            await self.realtimeBufferTranscribeBase64(base64: base64, sampleRate: sampleRate)
        }

        AsyncFunction("realtimeBufferTranscribe") { (buffer: [Float32], sampleRate: Double) async -> Void in
            await self.realtimeBufferTranscribe(buffer: buffer, sampleRate: sampleRate)
        }

        Function("stopBufferTranscription") { () -> Void in
            return self.stopBufferTranscription()
        }

        // Language configuration APIs
        AsyncFunction("setLanguage") { (localeCode: String) async -> Void in
            await self.setLanguage(localeCode: localeCode)
        }

        AsyncFunction("getAvailableLanguages") { () async -> [String] in
            return await self.getAvailableLanguages()
        }

        AsyncFunction("getCurrentLanguage") { () async -> String in
            return await self.getCurrentLanguage()
        }

        AsyncFunction("isLanguageAvailable") { (localeCode: String) async -> Bool in
            return await self.isLanguageAvailable(localeCode: localeCode)
        }
    }

    // MARK: - Buffer Transcription (Base64 entry point)

    private func realtimeBufferTranscribeBase64(base64: String, sampleRate: Double) async -> Void {
        guard let data = Data(base64Encoded: base64) else {
            self.sendEvent("onTranscriptionError", ["message": "Invalid Base64 string"])
            return
        }

        let int16Count = data.count / 2
        var int16Buffer = [Int16](repeating: 0, count: int16Count)
        _ = int16Buffer.withUnsafeMutableBytes { data.copyBytes(to: $0) }

        var floatBuffer = [Float32](repeating: 0.0, count: int16Count)
        for i in 0..<int16Count {
            floatBuffer[i] = Float(int16Buffer[i]) / 32768.0
        }

        await realtimeBufferTranscribe(buffer: floatBuffer, sampleRate: sampleRate)
    }

    // MARK: - Buffer Transcription (dispatch to iOS 26 or legacy)

    private func realtimeBufferTranscribe(buffer: [Float32], sampleRate: Double) async -> Void {
        #if SPEECH_ANALYZER_AVAILABLE
        if #available(iOS 26.0, *) {
            await realtimeBufferTranscribeWithAnalyzer(buffer: buffer, sampleRate: sampleRate)
            return
        }
        #endif
        await realtimeBufferTranscribeLegacy(buffer: buffer, sampleRate: sampleRate)
    }

    // MARK: - iOS 26+ Buffer Transcription (SpeechAnalyzer)

    #if SPEECH_ANALYZER_AVAILABLE
    @available(iOS 26.0, *)
    private func realtimeBufferTranscribeWithAnalyzer(buffer: [Float32], sampleRate: Double) async {
        // Initialize analyzer and stream if not already set up
        if bufferAnalyzer == nil {
            guard await isLocaleSupported(locale: currentLocale) else {
                self.sendEvent("onTranscriptionError", ["message": "Language '\(currentLocale.identifier)' is not supported for SpeechAnalyzer"])
                return
            }

            let transcriber = SpeechTranscriber(
                locale: currentLocale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )

            do {
                try await ensureModel(transcriber: transcriber, locale: currentLocale)
            } catch {
                self.sendEvent("onTranscriptionError", ["message": "Failed to ensure model: \(error.localizedDescription)"])
                return
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.bufferAnalyzer = analyzer

            let stream = AsyncStream<AnalyzerInput> { continuation in
                self.bufferStreamContinuation = continuation
            }

            bufferAnalysisTask = Task {
                do {
                    _ = try await analyzer.start(inputSequence: stream)
                } catch {
                    self.sendEvent("onTranscriptionError", ["message": "Buffer Analyzer error: \(error.localizedDescription)"])
                }
            }

            Task {
                for try await result in transcriber.results {
                    let recognizedText = String(result.text.characters)
                    self.sendEvent(
                        "onTranscriptionProgress",
                        ["text": recognizedText, "isFinal": result.isFinal]
                    )
                }
            }
        }

        // Convert Float32 buffer to AVAudioPCMBuffer
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(buffer.count)) else {
            self.sendEvent("onTranscriptionError", ["message": "Unable to create PCM buffer"])
            return
        }

        pcmBuffer.frameLength = AVAudioFrameCount(buffer.count)
        if let channelData = pcmBuffer.floatChannelData {
            buffer.withUnsafeBufferPointer { bufferPointer in
                guard let sourceAddress = bufferPointer.baseAddress else { return }
                memcpy(channelData[0], sourceAddress, buffer.count * MemoryLayout<Float>.size)
            }
        }

        if let continuation = bufferStreamContinuation as? AsyncStream<AnalyzerInput>.Continuation {
            continuation.yield(AnalyzerInput(buffer: pcmBuffer))
        }
    }
    #endif // SPEECH_ANALYZER_AVAILABLE

    // MARK: - Legacy Buffer Transcription (SFSpeechRecognizer, iOS 13+)

    private func realtimeBufferTranscribeLegacy(buffer: [Float32], sampleRate: Double) async -> Void {
        if bufferRecognitionRequest == nil {
            let speechRecognizer = SFSpeechRecognizer(locale: currentLocale)
            guard let recognizer = speechRecognizer else {
                self.sendEvent("onTranscriptionError", ["message": "Speech recognizer not available for locale: \(currentLocale.identifier)"])
                return
            }
            bufferRecognitionRequest = SFSpeechAudioBufferRecognitionRequest()

            guard let recognitionRequest = bufferRecognitionRequest else {
                self.sendEvent("onTranscriptionError", ["message": "Unable to create recognition request"])
                return
            }
            recognitionRequest.shouldReportPartialResults = true

            bufferRecognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let error = error {
                    self.sendEvent("onTranscriptionError", ["message": error.localizedDescription])
                    return
                }
                guard let result = result else { return }
                let recognizedText = result.bestTranscription.formattedString
                self.sendEvent(
                    "onTranscriptionProgress",
                    ["text": recognizedText, "isFinal": result.isFinal]
                )
            }
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(1))!
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(buffer.count)) else {
            self.sendEvent("onTranscriptionError", ["message": "Unable to create PCM buffer"])
            return
        }

        pcmBuffer.frameLength = AVAudioFrameCount(buffer.count)
        if let channelData = pcmBuffer.floatChannelData {
            buffer.withUnsafeBufferPointer { bufferPointer in
                guard let sourceAddress = bufferPointer.baseAddress else { return }
                memcpy(channelData[0], sourceAddress, buffer.count * MemoryLayout<Float>.size)
            }
        }

        bufferRecognitionRequest?.append(pcmBuffer)
    }

    // MARK: - Stop Buffer Transcription

    private func stopBufferTranscription() {
        // Legacy cleanup
        bufferRecognitionRequest?.endAudio()
        bufferRecognitionRequest = nil
        bufferRecognitionTask?.cancel()
        bufferRecognitionTask = nil

        // SpeechAnalyzer cleanup (iOS 26+ only, compiled conditionally)
        #if SPEECH_ANALYZER_AVAILABLE
        if #available(iOS 26.0, *) {
            if let continuation = bufferStreamContinuation as? AsyncStream<AnalyzerInput>.Continuation {
                continuation.finish()
            }
            bufferStreamContinuation = nil
            bufferAnalysisTask?.cancel()
            bufferAnalysisTask = nil
            bufferAnalyzer = nil
        }
        #endif
    }

    // MARK: - Realtime Recording (dispatch to iOS 26 or legacy)

    private func recordRealTimeAndTranscribe() async -> Void {
        #if SPEECH_ANALYZER_AVAILABLE
        if #available(iOS 26.0, *) {
            await recordRealTimeAndTranscribeWithAnalyzer()
            return
        }
        #endif
        await recordRealTimeAndTranscribeLegacy()
    }

    // MARK: - iOS 26+ Realtime Recording (SpeechAnalyzer)

    #if SPEECH_ANALYZER_AVAILABLE
    @available(iOS 26.0, *)
    private func recordRealTimeAndTranscribeWithAnalyzer() async {
        guard await isLocaleSupported(locale: currentLocale) else {
            self.sendEvent("onTranscriptionError", ["message": "Language '\(currentLocale.identifier)' is not supported for SpeechAnalyzer"])
            return
        }

        let transcriber = SpeechTranscriber(
            locale: currentLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        do {
            try await ensureModel(transcriber: transcriber, locale: currentLocale)
        } catch {
            self.sendEvent("onTranscriptionError", ["message": "Failed to download/ensure model: \(error.localizedDescription)"])
            return
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        let audioStream = AsyncStream<AnalyzerInput> { continuation in
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                continuation.yield(AnalyzerInput(buffer: buffer))
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            startedListening = true
        } catch {
            self.sendEvent("onTranscriptionError", ["message": "Audio Engine failed to start: \(error.localizedDescription)"])
            return
        }

        Task {
            do {
                _ = try await analyzer.start(inputSequence: audioStream)
            } catch {
                self.sendEvent("onTranscriptionError", ["message": "Analyzer error: \(error.localizedDescription)"])
            }
            self.stopListening()
        }

        Task {
            for try await result in transcriber.results {
                let recognizedText = String(result.text.characters)
                self.sendEvent(
                    "onTranscriptionProgress",
                    ["text": recognizedText, "isFinal": result.isFinal]
                )
            }
        }
    }
    #endif // SPEECH_ANALYZER_AVAILABLE

    // MARK: - Legacy Realtime Recording (SFSpeechRecognizer, iOS 13+)

    private func recordRealTimeAndTranscribeLegacy() async -> Void {
        let speechRecognizer = SFSpeechRecognizer(locale: currentLocale)
        guard let recognizer = speechRecognizer else {
            self.sendEvent("onTranscriptionError", ["message": "Speech recognizer not available for locale: \(currentLocale.identifier)"])
            return
        }
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            self.sendEvent("onTranscriptionError", ["message": "Unable to create recognition request"])
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            startedListening = true
        } catch {
            self.sendEvent("onTranscriptionError", ["message": error.localizedDescription])
            return
        }

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
            if let error = error {
                self.stopListening()
                self.sendEvent("onTranscriptionError", ["message": error.localizedDescription])
                return
            }
            guard let result = result else { return }
            let recognizedText = result.bestTranscription.formattedString
            self.sendEvent(
                "onTranscriptionProgress",
                ["text": recognizedText, "isFinal": result.isFinal]
            )
            if result.isFinal {
                self.stopListening()
            }
        }
    }

    // MARK: - Stop Listening

    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func isRecording() -> Bool {
        return audioEngine.isRunning
    }

    // MARK: - URL Transcription (SFSpeechRecognizer, iOS 13+)

    private func transcribeAudio(url: URL) async -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "Error: Audio file not found at \(url.path)"
        }

        return await withCheckedContinuation { continuation in
            guard let recognizer = SFSpeechRecognizer(locale: currentLocale) else {
                continuation.resume(returning: "Error: Speech recognizer not available for locale: \(currentLocale.identifier)")
                return
            }
            guard recognizer.isAvailable else {
                continuation.resume(returning: "Error: Speech recognizer not available at this time")
                return
            }

            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(returning: "Error: \(error.localizedDescription)")
                    return
                }
                guard let result = result else {
                    continuation.resume(returning: "Error: No transcription available")
                    return
                }
                if result.isFinal {
                    let text = result.bestTranscription.formattedString
                    continuation.resume(returning: text.isEmpty ? "No speech detected" : text)
                }
            }
        }
    }

    // MARK: - URL Transcription (SpeechAnalyzer, iOS 26+)

    #if SPEECH_ANALYZER_AVAILABLE
    @available(iOS 26.0, *)
    private func transcribeAudioWithAnalyzer(url: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "ExpoSpeechTranscriber", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Audio file not found at \(url.path)"])
        }

        guard await isLocaleSupported(locale: currentLocale) else {
            throw NSError(domain: "ExpoSpeechTranscriber", code: 400,
                          userInfo: [NSLocalizedDescriptionKey: "Locale \(currentLocale.identifier) not supported"])
        }

        let transcriber = SpeechTranscriber(
            locale: currentLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        try await ensureModel(transcriber: transcriber, locale: currentLocale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: url)

        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        var finalText = ""
        for try await recResponse in transcriber.results {
            if recResponse.isFinal {
                finalText += String(recResponse.text.characters)
            }
        }

        return finalText.isEmpty ? "No speech detected" : finalText
    }

    // MARK: - SpeechAnalyzer Helpers (iOS 26+)

    @available(iOS 26.0, *)
    private func isLocaleSupported(locale: Locale) async -> Bool {
        return await SpeechTranscriber.supportedLocales
            .map { $0.identifier(.bcp47) }
            .contains(locale.identifier(.bcp47))
    }

    @available(iOS 26.0, *)
    private func isLocaleInstalled(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        return installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }

    @available(iOS 26.0, *)
    private func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        guard await isLocaleSupported(locale: locale) else {
            throw NSError(domain: "ExpoSpeechTranscriber", code: 400,
                          userInfo: [NSLocalizedDescriptionKey: "Locale not supported"])
        }
        if await isLocaleInstalled(locale: locale) {
            return
        }
        try await downloadModelIfNeeded(for: transcriber)
    }

    @available(iOS 26.0, *)
    private func downloadModelIfNeeded(for module: SpeechTranscriber) async throws {
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await downloader.downloadAndInstall()
        }
    }
    #endif // SPEECH_ANALYZER_AVAILABLE

    // MARK: - Permissions

    private func requestTranscribePermissions() async -> String {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                let result: String
                switch authStatus {
                case .authorized:    result = "authorized"
                case .denied:        result = "denied"
                case .restricted:    result = "restricted"
                case .notDetermined: result = "notDetermined"
                @unknown default:    result = "unknown"
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func requestMicrophonePermissions() async -> String {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted ? "granted" : "denied")
            }
        }
    }

    // MARK: - Language Management

    private func setLanguage(localeCode: String) async -> Void {
        let locale = Locale(identifier: localeCode)
        if SFSpeechRecognizer(locale: locale) != nil {
            currentLocale = locale
        } else {
            self.sendEvent("onTranscriptionError", ["message": "Language '\(localeCode)' is not available on this device"])
        }
    }

    private func getAvailableLanguages() async -> [String] {
        return SFSpeechRecognizer.supportedLocales().map { $0.identifier }
    }

    private func getCurrentLanguage() async -> String {
        return currentLocale.identifier
    }

    private func isLanguageAvailable(localeCode: String) async -> Bool {
        return SFSpeechRecognizer(locale: Locale(identifier: localeCode)) != nil
    }
}
