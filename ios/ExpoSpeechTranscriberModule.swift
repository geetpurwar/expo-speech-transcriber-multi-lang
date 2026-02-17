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
            
            let transcription = await self.transcribeAudio(url: url)
            return transcription
        }
        
        // Method 3: Transcribe from URL using SpeechAnalyzer (iOS 26+)
        AsyncFunction("transcribeAudioWithAnalyzer") { (audioFilePath: String) async throws -> String in
            
            if #available(iOS 26.0, *) {
                let url: URL
                if audioFilePath.hasPrefix("file://") {
                    url = URL(string: audioFilePath)!
                } else {
                    url = URL(fileURLWithPath: audioFilePath)
                }
                
                let transcription = try await self.transcribeAudioWithAnalyzer(url: url)
                return transcription
            } else {
                throw NSError(domain: "ExpoSpeechTranscriber", code: 501,
                              userInfo: [NSLocalizedDescriptionKey: "SpeechAnalyzer requires iOS 26.0 or later"])
            }
        }
        
        AsyncFunction("requestPermissions") { () async -> String in
            return await self.requestTranscribePermissions()
        }
        
        AsyncFunction("requestMicrophonePermissions") { () async -> String in
            return await self.requestMicrophonePermissions()
        }
        
        
        Function("stopListening"){ () -> Void in
            return self.stopListening()
        }
        
        Function("isRecording") { () -> Bool in
            return self.isRecording()
        }
        
        Function("isAnalyzerAvailable") { () -> Bool in
            if #available(iOS 26.0, *) {
                return true
            }
            return false
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
        
        // NEW: Universal real-time transcription (auto-selects best API)
        AsyncFunction("recordRealTimeAndTranscribeUniversal") { (language: String?) async -> Void in
            await self.recordRealTimeAndTranscribeUniversal(language: language)
        }
        
        // iOS 26+ only: Real-time transcription using SpeechTranscriber directly
        AsyncFunction("recordRealTimeAndTranscribeWithSpeechTranscriber") { (language: String?) async throws -> Void in
            if #available(iOS 26.0, *) {
                if let lang = language {
                    await self.setLanguage(localeCode: lang)
                }
                await self.recordRealTimeWithSpeechTranscriber()
            } else {
                throw NSError(domain: "ExpoSpeechTranscriber", code: 501,
                              userInfo: [NSLocalizedDescriptionKey: "recordRealTimeAndTranscribeWithSpeechTranscriber requires iOS 26.0 or later"])
            }
        }
    }
    
    // MARK: - Private Implementation Methods
    
    private func realtimeBufferTranscribe(buffer: [Float32], sampleRate: Double) async -> Void {
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
                
                guard let result = result else {
                    return
                }
                
                let recognizedText = result.bestTranscription.formattedString
                self.sendEvent(
                    "onTranscriptionProgress",
                    ["text": recognizedText, "isFinal": result.isFinal]
                )
            }
        }
      
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(1))! // hardcode channel to 1 since we only support mono audio
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(buffer.count)) else {
            self.sendEvent("onTranscriptionError", ["message": "Unable to create PCM buffer"])
            return
        }
        
        pcmBuffer.frameLength = AVAudioFrameCount(buffer.count)
        if let channelData = pcmBuffer.floatChannelData {
            buffer.withUnsafeBufferPointer { bufferPointer in
                guard let sourceAddress = bufferPointer.baseAddress else { return }
                
                let destination = channelData[0]
                let byteCount = buffer.count * MemoryLayout<Float>.size
                
                memcpy(destination, sourceAddress, byteCount)
            }
        }
        
        // Append buffer to recognition request
        bufferRecognitionRequest?.append(pcmBuffer)
    }
    
    private func stopBufferTranscription() {
        bufferRecognitionRequest?.endAudio()
        bufferRecognitionRequest = nil
        
        bufferRecognitionTask?.cancel()
        bufferRecognitionTask = nil
    }
    
    // startRecordingAndTranscription using SFSpeechRecognizer
    private func recordRealTimeAndTranscribe() async -> Void  {
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
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, when in
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
                self.sendEvent("onTranscriptionError", ["message": error.localizedDescription])
                return
            }
            
            guard let result = result else {
                return
            }
            
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
    
    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        //recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
    
    
    private func isRecording() -> Bool {
        return audioEngine.isRunning
    }
    
    
    
    // Implemetation for URL transcription with SFSpeechRecognizer
    private func transcribeAudio(url: URL) async -> String {
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            let err = "Error: Audio file not found at \(url.path)"
            return err
        }
        
        return await withCheckedContinuation { continuation in
            guard let recognizer = SFSpeechRecognizer(locale: currentLocale) else {
                let err = "Error: Speech recognizer not available for locale: \(currentLocale.identifier)"
                continuation.resume(returning: err)
                return
            }
            
            guard recognizer.isAvailable else {
                let err = "Error: Speech recognizer not available at this time"
                continuation.resume(returning: err)
                return
            }
            
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            recognizer.recognitionTask(with: request) { (result, error) in
                if let error = error {
                    let errorMsg = "Error: \(error.localizedDescription)"
                    continuation.resume(returning: errorMsg)
                    return
                }
                
                guard let result = result else {
                    let errorMsg = "Error: No transcription available"
                    continuation.resume(returning: errorMsg)
                    return
                }
                
                if result.isFinal {
                    let text = result.bestTranscription.formattedString
                    let finalResult = text.isEmpty ? "No speech detected" : text
                    continuation.resume(returning: finalResult)
                }
            }
        }
    }
    
    // Implementation for URL transcription with SpeechAnalyzer (iOS 26+)
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
        
        let result = finalText.isEmpty ? "No speech detected" : finalText
        return result
    }
    
    @available(iOS 26.0, *)
    private func isLocaleSupported(locale: Locale) async -> Bool {
        guard SpeechTranscriber.isAvailable else { return false }
        let supported = await DictationTranscriber.supportedLocales
        return supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
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
        } else {
            try await downloadModelIfNeeded(for: transcriber)
        }
    }
    
    @available(iOS 26.0, *)
    private func downloadModelIfNeeded(for module: SpeechTranscriber) async throws {
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await downloader.downloadAndInstall()
        }
    }
    
    private func requestTranscribePermissions() async -> String {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                let result: String
                switch authStatus {
                case .authorized:
                    result = "authorized"
                case .denied:
                    result = "denied"
                case .restricted:
                    result = "restricted"
                case .notDetermined:
                    result = "notDetermined"
                @unknown default:
                    result = "unknown"
                }
                continuation.resume(returning: result)
            }
        }
    }
    
    private func requestMicrophonePermissions() async -> String {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                let result = granted ? "granted" : "denied"
                continuation.resume(returning: result)
            }
        }
    }
    
    // MARK: - Language Management Functions
    
    private func setLanguage(localeCode: String) async -> Void {
        let locale = Locale(identifier: localeCode)
        
        // Verify the locale is valid and supported
        if let _ = SFSpeechRecognizer(locale: locale) {
            currentLocale = locale
        } else {
            self.sendEvent("onTranscriptionError", ["message": "Language '\(localeCode)' is not available on this device"])
        }
    }
    
    private func getAvailableLanguages() async -> [String] {
        let supportedLocales = SFSpeechRecognizer.supportedLocales()
        return supportedLocales.map { $0.identifier }
    }
    
    private func getCurrentLanguage() async -> String {
        return currentLocale.identifier
    }
    
    private func isLanguageAvailable(localeCode: String) async -> Bool {
        let locale = Locale(identifier: localeCode)
        return SFSpeechRecognizer(locale: locale) != nil
    }
    
    // MARK: - Universal Real-Time Transcription
    
    /// Universal real-time transcription that automatically selects the best available API
    /// - iOS 26+: Uses SpeechTranscriber (better latency and accuracy)
    /// - iOS 13-25: Uses SFSpeechRecognizer (proven and reliable)
    private func recordRealTimeAndTranscribeUniversal(language: String?) async -> Void {
        // Set language if provided
        if let lang = language {
            await self.setLanguage(localeCode: lang)
        }
        
        // Check iOS version and use best available API
        if #available(iOS 26.0, *) {
            // Use SpeechTranscriber for iOS 26+
            await self.recordRealTimeWithSpeechTranscriber()
        } else {
            // Fallback to SFSpeechRecognizer for iOS 13-25
            await self.recordRealTimeAndTranscribe()
        }
    }
    
    /// Real-time transcription using SpeechTranscriber (iOS 26+)
    /// Provides better latency and accuracy than SFSpeechRecognizer
    @available(iOS 26.0, *)
    private func recordRealTimeWithSpeechTranscriber() async -> Void {
        // Check if already running
        if audioEngine.isRunning {
            self.sendEvent("onTranscriptionError", ["message": "Transcription is already running"])
            return
        }
        
        // Verify SpeechTranscriber is available
        guard SpeechTranscriber.isAvailable else {
            self.sendEvent("onTranscriptionError", ["message": "SpeechTranscriber not available on this device"])
            return
        }
        
        // Check locale support
        guard await isLocaleSupported(locale: currentLocale) else {
            self.sendEvent("onTranscriptionError", ["message": "Locale \(currentLocale.identifier) not supported by SpeechTranscriber"])
            return
        }
        
        // Create SpeechTranscriber with current locale
        let transcriber = SpeechTranscriber(
            locale: currentLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        
        // Ensure model is downloaded
        do {
            try await ensureModel(transcriber: transcriber, locale: currentLocale)
        } catch {
            self.sendEvent("onTranscriptionError", ["message": "Failed to download transcription model: \(error.localizedDescription)"])
            return
        }
        
        // Create analyzer with transcriber
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        
        // Setup audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Validate audio format
        guard recordingFormat.channelCount > 0 && recordingFormat.sampleRate > 0 else {
            self.sendEvent("onTranscriptionError", ["message": "Invalid microphone audio format"])
            return
        }
        
        // Remove any existing tap
        inputNode.removeTap(onBus: 0)
        
        // Install tap to capture audio
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, when in
            guard let self = self else { return }
            
            // Analyze audio buffer with SpeechTranscriber
            Task {
                do {
                    _ = try await analyzer.analyzeSequence(buffer: buffer)
                } catch {
                    self.sendEvent("onTranscriptionError", ["message": "Analysis error: \(error.localizedDescription)"])
                }
            }
        }
        
        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            startedListening = true
        } catch {
            self.sendEvent("onTranscriptionError", ["message": "Failed to start audio engine: \(error.localizedDescription)"])
            inputNode.removeTap(onBus: 0)
            return
        }
        
        // Stream transcription results
        Task {
            do {
                for try await result in transcriber.results {
                    let transcribedText = String(result.text.characters)
                    self.sendEvent(
                        "onTranscriptionProgress",
                        ["text": transcribedText, "isFinal": result.isFinal]
                    )
                    
                    if result.isFinal {
                        self.stopListening()
                    }
                }
            } catch {
                self.sendEvent("onTranscriptionError", ["message": "Transcription stream error: \(error.localizedDescription)"])
                self.stopListening()
            }
        }
    }
}
