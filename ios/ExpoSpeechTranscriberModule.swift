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
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    deinit {
        cleanupAudioSessionObservers()
        stopListening()
    }
    
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

        Function("getMicrophoneStatus") { () -> [String: Any] in
            return self.getMicrophoneStatus()
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
        if audioEngine.isRunning {
            self.sendEvent("onTranscriptionError", ["message": "Transcription is already running"])
            return
        }

        let microphonePermission = await self.ensureMicrophonePermission()
        guard microphonePermission == "granted" else {
            self.sendEvent("onTranscriptionError", ["message": "Microphone permission is not granted"])
            return
        }

        let session = AVAudioSession.sharedInstance()
        guard session.isInputAvailable else {
            self.sendEvent("onTranscriptionError", ["message": "Microphone is currently unavailable"])
            return
        }

        let speechRecognizer = SFSpeechRecognizer(locale: currentLocale)
        guard let recognizer = speechRecognizer else {
            self.sendEvent("onTranscriptionError", ["message": "Speech recognizer not available for locale: \(currentLocale.identifier)"])
            return
        }

        guard recognizer.isAvailable else {
            self.sendEvent("onTranscriptionError", ["message": "Speech recognizer is currently unavailable"])
            return
        }

        do {
            try self.configureAndActivateAudioSession()
        } catch {
            self.sendEvent("onTranscriptionError", ["message": error.localizedDescription])
            return
        }

        self.setupAudioSessionObserversIfNeeded()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            self.sendEvent("onTranscriptionError", ["message": "Unable to create recognition request"])
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.channelCount > 0 && recordingFormat.sampleRate > 0 else {
            self.sendEvent("onTranscriptionError", ["message": "Invalid microphone audio format"])
            self.stopListening()
            return
        }
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, when in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            startedListening = true
        } catch {
            self.stopListening()
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
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        startedListening = false
        deactivateAudioSessionIfPossible()
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

    private func ensureMicrophonePermission() async -> String {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return "granted"
        case .denied:
            return "denied"
        case .undetermined:
            return await requestMicrophonePermissions()
        @unknown default:
            return "denied"
        }
    }

    private func configureAndActivateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])
        } catch {
            throw NSError(
                domain: "ExpoSpeechTranscriber",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Unable to activate microphone session. Another call or app may be using audio."]
            )
        }
    }

    private func deactivateAudioSessionIfPossible() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Best effort only. Keep silent to avoid noisy logs for expected teardown races.
        }
    }

    private func setupAudioSessionObserversIfNeeded() {
        if interruptionObserver == nil {
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                self?.handleAudioSessionInterruption(notification)
            }
        }

        if routeChangeObserver == nil {
            routeChangeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                self?.handleAudioRouteChange(notification)
            }
        }
    }

    private func cleanupAudioSessionObservers() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }

        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
            self.routeChangeObserver = nil
        }
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let interruptionTypeRaw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let interruptionType = AVAudioSession.InterruptionType(rawValue: interruptionTypeRaw)
        else {
            return
        }

        if interruptionType == .began && (startedListening || audioEngine.isRunning) {
            stopListening()
            sendEvent("onTranscriptionError", ["message": "Recording interrupted by another audio source"])
        }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let routeChangeReasonRaw = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let routeChangeReason = AVAudioSession.RouteChangeReason(rawValue: routeChangeReasonRaw)
        else {
            return
        }

        switch routeChangeReason {
        case .oldDeviceUnavailable, .noSuitableRouteForCategory:
            if startedListening || audioEngine.isRunning {
                stopListening()
                sendEvent("onTranscriptionError", ["message": "Microphone input became unavailable"])
            }
        default:
            break
        }
    }

    private func getMicrophoneStatus() -> [String: Any] {
        let session = AVAudioSession.sharedInstance()
        let permissionStatus: String
        switch session.recordPermission {
        case .granted:
            permissionStatus = "granted"
        case .denied:
            permissionStatus = "denied"
        case .undetermined:
            permissionStatus = "undetermined"
        @unknown default:
            permissionStatus = "undetermined"
        }

        let hasAudioInputRoute = !(session.availableInputs ?? []).isEmpty
        let isInputAvailable = session.isInputAvailable
        let isBusy = !isInputAvailable
        let canRecord = permissionStatus == "granted" && isInputAvailable && hasAudioInputRoute

        var reason: String? = nil
        if permissionStatus != "granted" {
            reason = "Microphone permission not granted"
        } else if !hasAudioInputRoute {
            reason = "No audio input route available"
        } else if !isInputAvailable {
            reason = "Microphone is currently unavailable"
        }

        return [
            "permissionStatus": permissionStatus,
            "isInputAvailable": isInputAvailable,
            "hasAudioInputRoute": hasAudioInputRoute,
            "isRecording": audioEngine.isRunning,
            "isBusy": isBusy,
            "canRecord": canRecord,
            "reason": reason ?? NSNull()
        ]
    }
}
