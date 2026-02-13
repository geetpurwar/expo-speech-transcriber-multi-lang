import { ConfigPlugin, IOSConfig, AndroidConfig } from 'expo/config-plugins';

const SPEECH_RECOGNITION_USAGE = 'Allow $(PRODUCT_NAME) to use speech recognition to transcribe audio';
const MICROPHONE_USAGE = 'Allow $(PRODUCT_NAME) to access your microphone';

const withSpeechTranscriber: ConfigPlugin<{ speechRecognitionPermission?: string | false; microphonePermission?: string | false } | void> = (
  config,
  { speechRecognitionPermission, microphonePermission } = {}
) => {
  config = IOSConfig.Permissions.createPermissionsPlugin({
    NSSpeechRecognitionUsageDescription: SPEECH_RECOGNITION_USAGE,
    NSMicrophoneUsageDescription: MICROPHONE_USAGE,
  })(config, {
    NSSpeechRecognitionUsageDescription: speechRecognitionPermission,
    NSMicrophoneUsageDescription: microphonePermission,
  });

  if (microphonePermission !== false) {
    config = AndroidConfig.Permissions.withPermissions(config, [
      'android.permission.RECORD_AUDIO',
    ]);
  }

  return config;
};

export default withSpeechTranscriber;