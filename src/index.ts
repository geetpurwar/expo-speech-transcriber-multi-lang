// Reexport the native module. On web, it will be resolved to ExpoSpeechTranscriberModule.web.ts
// and on native platforms to ExpoSpeechTranscriberModule.ts
import ExpoSpeechTranscriberModule from './ExpoSpeechTranscriberModule';
import type {
  TranscriptionProgressPayload,
  TranscriptionErrorPayload,
  MicrophonePermissionTypes,
  PermissionTypes
} from './ExpoSpeechTranscriber.types';
import { useState, useEffect } from 'react';

export function recordRealTimeAndTranscribe(): Promise<void> {
  return ExpoSpeechTranscriberModule.recordRealTimeAndTranscribe();
}

export { default as ExpoSpeechTranscriberModule } from './ExpoSpeechTranscriberModule';
export * from './ExpoSpeechTranscriber.types';

export function transcribeAudioWithSFRecognizer(audioFilePath: string): Promise<string> {
  return ExpoSpeechTranscriberModule.transcribeAudioWithSFRecognizer(audioFilePath);
}

export function stopListening(): void {
  return ExpoSpeechTranscriberModule.stopListening();
}

export function transcribeAudioWithAnalyzer(audioFilePath: string): Promise<string> {
  return ExpoSpeechTranscriberModule.transcribeAudioWithAnalyzer(audioFilePath);
}

export function requestPermissions(): Promise<PermissionTypes> {
  return ExpoSpeechTranscriberModule.requestPermissions();
}

export function requestMicrophonePermissions(): Promise<MicrophonePermissionTypes> {
  return ExpoSpeechTranscriberModule.requestMicrophonePermissions();
}

export function isRecording(): boolean {
  return ExpoSpeechTranscriberModule.isRecording();
}

export function isAnalyzerAvailable(): boolean {
  return ExpoSpeechTranscriberModule.isAnalyzerAvailable();
}

export function realtimeBufferTranscribe(
  buffer: number[] | Float32Array,
  sampleRate: number,
): Promise<void> {
  const bufferArray = Array.isArray(buffer) ? buffer : Array.from(buffer);
  return ExpoSpeechTranscriberModule.realtimeBufferTranscribe(
    bufferArray,
    sampleRate,
  );
}

export function stopBufferTranscription(): void {
  return ExpoSpeechTranscriberModule.stopBufferTranscription();
}

// Language configuration functions
export function setLanguage(localeCode: string): Promise<void> {
  return ExpoSpeechTranscriberModule.setLanguage(localeCode);
}

export function getAvailableLanguages(): Promise<string[]> {
  return ExpoSpeechTranscriberModule.getAvailableLanguages();
}

export function getCurrentLanguage(): Promise<string> {
  return ExpoSpeechTranscriberModule.getCurrentLanguage();
}

export function isLanguageAvailable(localeCode: string): Promise<boolean> {
  return ExpoSpeechTranscriberModule.isLanguageAvailable(localeCode);
}

// NEW: Universal real-time transcription (auto-selects best API)
export interface UniversalTranscriptionOptions {
  /**
   * Language code in BCP-47 format (e.g., 'en-US', 'es-ES', 'hi-IN')
   * @default Device language
   */
  language?: string;
}

/**
 * Start real-time speech transcription using the best available API.
 * 
 * APIs used:
 * - iOS 26+: SpeechTranscriber (lower latency, better accuracy)
 * - iOS 13-25: SFSpeechRecognizer (proven and reliable)
 * - Android 13+: SpeechRecognizer (native Android API)
 * 
 * @param options - Optional configuration
 * @param options.language - BCP-47 locale code (e.g., 'es-MX', 'hi-IN'). Defaults to device language.
 * @returns Promise that resolves when transcription starts
 * 
 * @example
 * // Use device default language
 * await recordRealTimeAndTranscribeUniversal();
 * 
 * @example
 * // Specify language
 * await recordRealTimeAndTranscribeUniversal({ language: 'es-MX' });
 */
export function recordRealTimeAndTranscribeUniversal(
  options?: UniversalTranscriptionOptions
): Promise<void> {
  return ExpoSpeechTranscriberModule.recordRealTimeAndTranscribeUniversal(
    options?.language ?? null
  );
}

/**
 * Start real-time speech transcription using the iOS 26+ SpeechTranscriber API directly.
 *
 * This function explicitly targets the new SpeechTranscriber API and will throw
 * an error on iOS versions below 26. For a version-safe alternative that
 * automatically falls back to SFSpeechRecognizer on older devices, use
 * `recordRealTimeAndTranscribeUniversal` instead.
 *
 * Use `isAnalyzerAvailable()` to check iOS 26 availability before calling this.
 *
 * @param options - Optional configuration
 * @param options.language - BCP-47 locale code (e.g., 'en-US', 'es-MX', 'hi-IN').
 *   Defaults to the currently set language.
 * @returns Promise that resolves when transcription starts, or rejects on iOS < 26
 * @throws Error if running on iOS below 26.0
 *
 * @example
 * // Guard with availability check
 * if (isAnalyzerAvailable()) {
 *   await recordRealTimeAndTranscribeWithSpeechTranscriber();
 * }
 *
 * @example
 * // With explicit language
 * await recordRealTimeAndTranscribeWithSpeechTranscriber({ language: 'hi-IN' });
 */
export function recordRealTimeAndTranscribeWithSpeechTranscriber(
  options?: UniversalTranscriptionOptions
): Promise<void> {
  return ExpoSpeechTranscriberModule.recordRealTimeAndTranscribeWithSpeechTranscriber(
    options?.language ?? null
  );
}

export function useRealTimeTranscription() {
  const [text, setText] = useState('');
  const [isFinal, setIsFinal] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isRecording, setIsRecording] = useState(false);

  useEffect(() => {
    const progressListener = ExpoSpeechTranscriberModule.addListener('onTranscriptionProgress', (payload: TranscriptionProgressPayload) => {
      setText(payload.text);
      setIsFinal(payload.isFinal);
    });

    const errorListener = ExpoSpeechTranscriberModule.addListener('onTranscriptionError', (payload: TranscriptionErrorPayload) => {
      setError(payload.message);
    })


    const interval = setInterval(() => {
      const newIsRecording = ExpoSpeechTranscriberModule.isRecording();
      setIsRecording(prev => (prev !== newIsRecording ? newIsRecording : prev));
    }, 100);

    return () => {
      clearInterval(interval);
      progressListener.remove();
      errorListener.remove();
    };
  }, []);


    useEffect(() => {
      if (isRecording) {
        setText('');
        setIsFinal(false);
        setError(null);
      }
    }, [isRecording]);

  return { text, isFinal, error, isRecording };
}
