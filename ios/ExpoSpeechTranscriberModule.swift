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
    
    // MARK: - Private Implementation Methods
    
    private func realtimeBufferTranscribeBase64(base64: String, sampleRate: Double) async -> Void {
        guard let data = Data(base64Encoded: base64) else {
            self.sendEvent("onTranscriptionError", ["message": "Invalid Base64 string"])
            return
        }
        
        // Expo Audio Studio returns 16-bit PCM. Convert to Float32.
        let byteCount = data.count
        let int16Count = byteCount / 2
        
        var int16Buffer = [Int16](repeating: 0, count: int16Count)
        _ = int16Buffer.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        
        var floatBuffer = [Float32](repeating: 0.0, count: int16Count)
        
        // Convert Int16 to Float32 and normalize to [-1.0, 1.0]
        // This simple loop is performant enough for real-time 50ms chunks.
        // Accelerate framework could be used for further optimization but adds complexity.
        for i in 0..<int16Count {
            floatBuffer[i] = Float(int16Buffer[i]) / 32768.0
        }
        
        await realtimeBufferTranscribe(buffer: floatBuffer, sampleRate: sampleRate)
    }
    
    // State for SpeechAnalyzer buffer transcription (iOS 26+)
    // Stored as Any because SpeechAnalyzer and AnalyzerInput are only available on iOS 26+
    // and stored properties cannot have @available usage restrictions in a class available on older iOS.
    private var bufferAnalyzer: Any? 
    private var bufferStreamContinuation: Any?
    private var bufferAnalysisTask: Task<Void, Never>?

    private func realtimeBufferTranscribe(buffer: [Float32], sampleRate: Double) async -> Void {
        if #available(iOS 26.0, *) {
            await realtimeBufferTranscribeWithAnalyzer(buffer: buffer, sampleRate: sampleRate)
        } else {
            await realtimeBufferTranscribeLegacy(buffer: buffer, sampleRate: sampleRate)
        }
    }

    @available(iOS 26.0, *)
    private func realtimeBufferTranscribeWithAnalyzer(buffer: [Float32], sampleRate: Double) async {
        // Initialize analyzer and stream if not already exists
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
            
            // Create the stream and store continuation
            let stream = AsyncStream<AnalyzerInput> { continuation in
                self.bufferStreamContinuation = continuation
            }
            
            // Start analysis task
            bufferAnalysisTask = Task {
                do {
                    _ = try await analyzer.start(inputSequence: stream)
                } catch {
                    self.sendEvent("onTranscriptionError", ["message": "Buffer Analyzer error: \(error.localizedDescription)"])
                }
            }
            
            // Start result processing
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
        
        // Yield to analyzer
        if let continuation = bufferStreamContinuation as? AsyncStream<AnalyzerInput>.Continuation {
            continuation.yield(AnalyzerInput(buffer: pcmBuffer))
        }
    }

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
        // Legacy cleanup
        bufferRecognitionRequest?.endAudio()
        bufferRecognitionRequest = nil
        bufferRecognitionTask?.cancel()
        bufferRecognitionTask = nil
        
        // SpeechAnalyzer cleanup (iOS 26+)
        if #available(iOS 26.0, *) {
            if let continuation = bufferStreamContinuation as? AsyncStream<AnalyzerInput>.Continuation {
                continuation.finish()
            }
            bufferStreamContinuation = nil
            // Analyzer tasks should finish when stream finishes
            bufferAnalysisTask?.cancel() // Ensure task is cancelled just in case
            bufferAnalysisTask = nil
            bufferAnalyzer = nil
        }
    }
    
    // startRecordingAndTranscription using SFSpeechRecognizer or SpeechAnalyzer (iOS 26+)
    private func recordRealTimeAndTranscribe() async -> Void {
        if #available(iOS 26.0, *) {
            await recordRealTimeAndTranscribeWithAnalyzer()
        } else {
            await recordRealTimeAndTranscribeLegacy()
        }
    }

    @available(iOS 26.0, *)
    private func recordRealTimeAndTranscribeWithAnalyzer() async {
        guard await isLocaleSupported(locale: currentLocale) else {
            self.sendEvent("onTranscriptionError", ["message": "Language '\(currentLocale.identifier)' is not supported for SpeechAnalyzer"])
            return
        }
        
        // Ensure model is available
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
        
        // Use AsyncStream to bridge the audio buffer block to the analyzer
        let audioStream = AsyncStream<AnalyzerInput> { continuation in
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, when in
                continuation.yield(AnalyzerInput(buffer: buffer))
            }
            
             // Handle stream termination cleanup if needed
             // continuation.onTermination = { @Sendable _ in ... }
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            startedListening = true
        } catch {
            self.sendEvent("onTranscriptionError", ["message": "Audio Engine failed to start: \(error.localizedDescription)"])
            return
        }
        
        // Start analysis task
        Task {
            do {
                // Feed audio stream to analyzer
                // Note: The SpeechAnalyzer API might expect an AsyncSequence of buffers or similar.
                // Assuming `analyze(audioStream)` or similar exists based on general swift concurrency patterns for this API.
                // If the specific API requires pushing buffers manually, we'd adjust.
                // Based on `analyzeSequence(from: AVAudioFile)`, there should be a streaming equivalent.
                // Let's assume `analyze(audioStream)` for now given the context of "realtime".
                // If not, we might need a push-based approach if the API exposes one.
                
                // Correction: The WWDC examples typically show using an `AVAudioSession` and feeding it,
                // or just `files`. If we need custom audio input (like from Expo's engine setup),
                // we might need to conform to an AsyncSequence returning buffers.
                
                // Correct API found: start(inputSequence:)
                _ = try await analyzer.start(inputSequence: audioStream)
            } catch {
                self.sendEvent("onTranscriptionError", ["message": "Analyzer error: \(error.localizedDescription)"])
            }
            
            self.stopListening()
        }
        
        // Handle results concurrently
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

    private func recordRealTimeAndTranscribeLegacy() async -> Void  {
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
                self.stopListening()
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
}

