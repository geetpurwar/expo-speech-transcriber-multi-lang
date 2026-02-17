import { requireNativeModule, NativeModule } from 'expo-modules-core';
import type {
  ExpoSpeechTranscriberModuleEvents,
  PermissionTypes,
  MicrophonePermissionTypes
} from './ExpoSpeechTranscriber.types';

declare class ExpoSpeechTranscriberNative extends NativeModule<ExpoSpeechTranscriberModuleEvents> {
  recordRealTimeAndTranscribe(): Promise<void>;
  stopListening(): void;
  transcribeAudioWithSFRecognizer(audioFilePath: string): Promise<string>;
  transcribeAudioWithAnalyzer(audioFilePath: string): Promise<string>;
  requestPermissions(): Promise<PermissionTypes>;
  requestMicrophonePermissions(): Promise<MicrophonePermissionTypes>;
  isRecording(): boolean;
  isAnalyzerAvailable(): boolean;
  realtimeBufferTranscribe(buffer: number[], sampleRate: number): Promise<void>;
  stopBufferTranscription(): void;
  setLanguage(localeCode: string): Promise<void>;
  getAvailableLanguages(): Promise<string[]>;
  getCurrentLanguage(): Promise<string>;
  isLanguageAvailable(localeCode: string): Promise<boolean>;
  recordRealTimeAndTranscribeUniversal(language: string | null): Promise<void>;
  recordRealTimeAndTranscribeWithSpeechTranscriber(language: string | null): Promise<void>;
}

const ExpoSpeechTranscriberModule =
  requireNativeModule<ExpoSpeechTranscriberNative>('ExpoSpeechTranscriber');

export default ExpoSpeechTranscriberModule;
