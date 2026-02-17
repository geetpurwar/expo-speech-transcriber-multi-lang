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

// Unified entry point for real-time transcription
// Automatically selects the appropriate engine based on platform/OS:
// - Android: SpeechRecognizer
// - iOS 26+: SpeechAnalyzer
// - iOS < 26: SFSpeechRecognizer
export function startActiveListening(): Promise<void> {
  return ExpoSpeechTranscriberModule.recordRealTimeAndTranscribe();
}

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

// Transcribe raw audio buffer (Float32Array)
export function realtimeBufferTranscribe(buffer: number[] | Float32Array, sampleRate: number): Promise<void> {
  // Convert Float32Array to regular array if needed, as bridge handling varies
  const bufferArray = buffer instanceof Float32Array ? Array.from(buffer) : buffer;
  return ExpoSpeechTranscriberModule.realtimeBufferTranscribe(bufferArray, sampleRate);
}

// Transcribe raw audio buffer (Base64 string of Int16 PCM)
// This is more performant for use with expo-audio-studio
export function realtimeBufferTranscribeBase64(base64Idx: string, sampleRate: number): Promise<void> {
  return ExpoSpeechTranscriberModule.realtimeBufferTranscribeBase64(base64Idx, sampleRate);
}

export function stopBufferTranscription(): void {
  return ExpoSpeechTranscriberModule.stopBufferTranscription();
}

/**
 * Configure the recognition language.
 * @param localeCode A BCP-47 language tag (e.g., "en-US", "fr-FR")
 */
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
      setError(payload.error);
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
