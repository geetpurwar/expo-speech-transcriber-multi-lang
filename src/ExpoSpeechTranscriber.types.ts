import type { StyleProp, ViewStyle } from 'react-native';

export type OnLoadEventPayload = {
  url: string;
};

export type TranscriptionProgressPayload = {
  text: string;
  isFinal: boolean;
};


export type TranscriptionErrorPayload = {
  message: string;
};

export type ExpoSpeechTranscriberModuleEvents = {
  onTranscriptionProgress(payload: TranscriptionProgressPayload): void;
  onTranscriptionError(payload: TranscriptionErrorPayload): void;
};

export type ChangeEventPayload = {
  value: string;
};


export type PermissionTypes = 'authorized' | 'denied' | 'restricted' | 'notDetermined';

export type MicrophonePermissionTypes = 'granted' | 'denied'

export interface UniversalTranscriptionOptions {
  /**
   * Language code in BCP-47 format (e.g., 'en-US', 'es-ES', 'hi-IN')
   * @default Device language
   */
  language?: string;
}

export type ExpoSpeechTranscriberViewProps = {
  url: string;
  onLoad: (event: { nativeEvent: OnLoadEventPayload }) => void;
  style?: StyleProp<ViewStyle>;
};
