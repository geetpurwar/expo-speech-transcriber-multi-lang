# expo-speech-transcriber

On-device speech transcription for Expo apps. Supports iOS (Apple Speech framework) and Android (SpeechRecognizer API).

## Features

- 🎯 On-device transcription - Works offline, privacy-focused
- 📱 Cross-platform - iOS 13+ and Android 13+ (API 33)
- 🚀 Multiple APIs - SFSpeechRecognizer (iOS 13+), SpeechAnalyzer (iOS 26+), and Android SpeechRecognizer
- 📦 Easy integration - Auto-configures permissions
- 🔒 Secure - All processing happens on device
- ⚡ Realtime transcription - Get live speech-to-text updates with built-in audio capture
- 📁 File transcription - Transcribe pre-recorded audio files
- 🎤 Buffer-based transcription - Stream audio buffers from external sources for real-time transcription

## Installation

```bash
npx expo install expo-speech-transcriber expo-audio
```

Add the plugin to your `app.json`:

```json
{
  "expo": {
    "plugins": ["expo-audio", "expo-speech-transcriber"]
  }
}
```

### Custom permission message (recommended):

Apple requires a clear purpose string for speech recognition and microphone permissions. Without it, your app may be rejected during App Store review. Provide a descriptive message explaining why your app needs access.

```json
{
  "expo": {
    "plugins": [
      "expo-audio",
      [
        "expo-speech-transcriber",
        {
          "speechRecognitionPermission": "We need speech recognition to transcribe your recordings",
          "microphonePermission": "We need microphone access to record audio for transcription"
        }
      ]
    ]
  }
}
```

For more details, see Apple's guidelines on [requesting access to protected resources](https://developer.apple.com/documentation/uikit/requesting-access-to-protected-resources).

> **Note for Android:** The plugin automatically adds the `RECORD_AUDIO` permission to your Android manifest. No additional configuration is required.

## Usage

### Realtime Transcription

Start transcribing speech in real-time. This does not require `expo-audio`.

```typescript
import { Platform } from "react-native";
import * as SpeechTranscriber from "expo-speech-transcriber";

// Request permissions
// Note: requestPermissions() is only needed on iOS
if (Platform.OS === "ios") {
  const speechPermission = await SpeechTranscriber.requestPermissions();
  if (speechPermission !== "authorized") {
    console.log("Speech permission denied");
    return;
  }
}

const micPermission = await SpeechTranscriber.requestMicrophonePermissions();
if (micPermission !== "granted") {
  console.log("Microphone permission denied");
  return;
}

// Use the hook for realtime updates
const { text, isFinal, error, isRecording } =
  SpeechTranscriber.useRealTimeTranscription();

// Start transcription
await SpeechTranscriber.recordRealTimeAndTranscribe();

// Stop when done
SpeechTranscriber.stopListening();
```
**NOTE**: See [RecordRealTimeAndTrancribe](example/RecordRealTimeAndTranscribe.tsx) for an example on how to use Real Time transcription on android. 

### File Transcription

Transcribe pre-recorded audio files. Our library handles transcription but not recording—use `expo-audio` to record audio (see [expo-audio documentation](https://docs.expo.dev/versions/latest/sdk/audio/)), or implement your own recording logic with microphone access via `requestMicrophonePermissions()`.

```typescript
import * as SpeechTranscriber from "expo-speech-transcriber";
import { useAudioRecorder, RecordingPresets } from "expo-audio";

// Record audio with expo-audio
const audioRecorder = useAudioRecorder(RecordingPresets.HIGH_QUALITY);
await audioRecorder.prepareToRecordAsync();
audioRecorder.record();
// ... user speaks ...
await audioRecorder.stop();
const audioUri = audioRecorder.uri;

// Transcribe with SFSpeechRecognizer (preferred)
const text = await SpeechTranscriber.transcribeAudioWithSFRecognizer(audioUri);
console.log("Transcription:", text);

// Or with SpeechAnalyzer if available
if (SpeechTranscriber.isAnalyzerAvailable()) {
  const text = await SpeechTranscriber.transcribeAudioWithAnalyzer(audioUri);
  console.log("Transcription:", text);
}
```

For custom recording without `expo-audio`:

```typescript
// Request microphone permission for your custom recording implementation
const micPermission = await SpeechTranscriber.requestMicrophonePermissions();
// Implement your own audio recording logic here to save a file
// Then transcribe the resulting audio file URI
```

### Buffer-Based Transcription

Stream audio buffers directly to the transcriber for real-time processing. This is ideal for integrating with audio processing libraries like [react-native-audio-api](https://docs.swmansion.com/react-native-audio-api/).

```typescript
import * as SpeechTranscriber from "expo-speech-transcriber";
import { AudioManager, AudioRecorder } from "react-native-audio-api";

// Set up audio recorder
const recorder = new AudioRecorder({
  sampleRate: 16000,
  bufferLengthInSamples: 1600,
});

AudioManager.setAudioSessionOptions({
  iosCategory: "playAndRecord",
  iosMode: "spokenAudio",
  iosOptions: ["allowBluetooth", "defaultToSpeaker"],
});

// Request permissions
const speechPermission = await SpeechTranscriber.requestPermissions();
const micPermission = await AudioManager.requestRecordingPermissions();

// Stream audio buffers to transcriber
recorder.onAudioReady(({ buffer }) => {
  const channelData = buffer.getChannelData(0);
  SpeechTranscriber.realtimeBufferTranscribe(
    channelData, // Float32Array or number[]
    16000, // sample rate
  );
});

// Use the hook to get transcription updates
const { text, isFinal, error } = SpeechTranscriber.useRealTimeTranscription();

// Start streaming
recorder.start();

// Stop when done
recorder.stop();
SpeechTranscriber.stopBufferTranscription();
```

See the [BufferTranscriptionExample](./example/BufferTranscriptionExample.tsx) for a complete implementation.



## API Reference

### `requestPermissions()`
Request speech recognition permission.

**Platform:** iOS only. On Android, speech recognition permission is handled through `requestMicrophonePermissions()`.

**Returns:** `Promise<PermissionTypes>` - One of: `'authorized'`, `'denied'`, `'restricted'`, or `'notDetermined'`

**Example:**

```typescript
import { Platform } from "react-native";

if (Platform.OS === "ios") {
  const status = await SpeechTranscriber.requestPermissions();
}
```

### `requestMicrophonePermissions()`

Request microphone permission.

**Returns:** `Promise<MicrophonePermissionTypes>` - One of: `'granted'` or `'denied'`

**Example:**

```typescript
const status = await SpeechTranscriber.requestMicrophonePermissions();
```

### `recordRealTimeAndTranscribe()`

Start real-time speech transcription. Listen for events via `useRealTimeTranscription` hook.

**Returns:** `Promise<void>`

**Example:**

```typescript
await SpeechTranscriber.recordRealTimeAndTranscribe();
```

### `stopListening()`

Stop real-time transcription.

**Returns:** `void`

**Example:**

```typescript
SpeechTranscriber.stopListening();
```

### `isRecording()`

Check if real-time transcription is currently recording.

**Returns:** `boolean`

**Example:**

```typescript
const recording = SpeechTranscriber.isRecording();
```

### `transcribeAudioWithSFRecognizer(audioFilePath: string)`

Transcribe audio from a pre-recorded file using SFSpeechRecognizer. I prefer this API for its reliability.

**Platform:** iOS only

**Requires:** iOS 13+, pre-recorded audio file URI (record with `expo-audio` or your own implementation)

**Returns:** `Promise<string>` - Transcribed text

**Example:**

```typescript
const transcription = await SpeechTranscriber.transcribeAudioWithSFRecognizer(
  "file://path/to/audio.m4a"
);
```

### `transcribeAudioWithAnalyzer(audioFilePath: string)`

Transcribe audio from a pre-recorded file using SpeechAnalyzer.

**Platform:** iOS only

**Requires:** iOS 26+, pre-recorded audio file URI (record with `expo-audio` or your own implementation)

**Returns:** `Promise<string>` - Transcribed text

**Example:**

```typescript
const transcription = await SpeechTranscriber.transcribeAudioWithAnalyzer(
  "file://path/to/audio.m4a"
);
```

### `isAnalyzerAvailable()`

Check if SpeechAnalyzer API is available.

**Platform:** iOS only. Always returns `false` on Android.

**Returns:** `boolean` - `true` if iOS 26+, `false` otherwise

**Example:**

```typescript
if (SpeechTranscriber.isAnalyzerAvailable()) {
  // Use SpeechAnalyzer
}
```

### `useRealTimeTranscription()`

React hook for real-time transcription state.

**Returns:** `{ text: string, isFinal: boolean, error: string | null, isRecording: boolean }`

**Example:**

```typescript
const { text, isFinal, error, isRecording } =
  SpeechTranscriber.useRealTimeTranscription();
```

### `realtimeBufferTranscribe(buffer, sampleRate)`

Stream audio buffers for real-time transcription. Ideal for integration with audio processing libraries.

**Parameters:**

- `buffer: Float32Array | number[]` - Audio samples
- `sampleRate: number` - Sample rate in Hz (e.g., 16000)

**NOTE** We currently support transcription for mono audio only. Natively, the channel is set to 1. 

**Returns:** `Promise<void>`

**Example:**

```typescript
const audioBuffer = new Float32Array([...]);
await SpeechTranscriber.realtimeBufferTranscribe(audioBuffer, 16000);
```

### `stopBufferTranscription()`

Stop buffer-based transcription and clean up resources.

**Returns:** `void`

**Example:**

```typescript
SpeechTranscriber.stopBufferTranscription();
```

---

## Language Configuration

### `setLanguage(localeCode: string)`

Set the language for speech transcription. Must be called before starting transcription.

**Platform:** iOS and Android

**Parameters:**

- `localeCode: string` - BCP-47 locale code (e.g., 'es-ES', 'fr-FR', 'ar-SA', 'zh-CN')

**Returns:** `Promise<void>`

**Example:**

```typescript
// Set to Spanish (Spain)
await SpeechTranscriber.setLanguage('es-ES');

// Set to Arabic (Saudi Arabia)
await SpeechTranscriber.setLanguage('ar-SA');

// Set to Chinese (China)
await SpeechTranscriber.setLanguage('zh-CN');

// Then start transcription
await SpeechTranscriber.recordRealTimeAndTranscribe();
```

**Common Locale Codes:**

| Language | Locale Code |
|----------|-------------|
| English (US) | en-US |
| English (UK) | en-GB |
| Spanish (Spain) | es-ES |
| Spanish (Mexico) | es-MX |
| French (France) | fr-FR |
| German (Germany) | de-DE |
| Italian (Italy) | it-IT |
| Portuguese (Brazil) | pt-BR |
| Russian (Russia) | ru-RU |
| Chinese (Simplified) | zh-CN |
| Chinese (Traditional) | zh-TW |
| Japanese | ja-JP |
| Korean | ko-KR |
| Arabic (Saudi Arabia) | ar-SA |
| Hindi (India) | hi-IN |
| Dutch (Netherlands) | nl-NL |
| Polish (Poland) | pl-PL |
| Turkish (Turkey) | tr-TR |
| Vietnamese | vi-VN |

### `getAvailableLanguages()`

Get a list of all languages supported on the current device.

**Platform:** iOS and Android

**Returns:** `Promise<string[]>` - Array of locale codes

**Example:**

```typescript
const languages = await SpeechTranscriber.getAvailableLanguages();
console.log('Available languages:', languages);
// Output: ['en-US', 'es-ES', 'fr-FR', 'de-DE', ...]
```

### `getCurrentLanguage()`

Get the currently selected language for transcription.

**Platform:** iOS and Android

**Returns:** `Promise<string>` - Current locale code

**Example:**

```typescript
const current = await SpeechTranscriber.getCurrentLanguage();
console.log('Current language:', current);
// Output: 'en-US'
```

### `isLanguageAvailable(localeCode: string)`

Check if a specific language is available on the current device.

**Platform:** iOS and Android

**Parameters:**

- `localeCode: string` - BCP-47 locale code to check

**Returns:** `Promise<boolean>` - true if available, false otherwise

**Example:**

```typescript
const isSpanishAvailable = await SpeechTranscriber.isLanguageAvailable('es-ES');
if (isSpanishAvailable) {
  await SpeechTranscriber.setLanguage('es-ES');
  console.log('Spanish is available!');
} else {
  console.log('Spanish is not supported on this device');
}
```

---

## Complete Multi-Language Example

```typescript
import * as SpeechTranscriber from 'expo-speech-transcriber';
import { Platform } from 'react-native';

async function transcribeInSpanish() {
  // Request permissions
  if (Platform.OS === 'ios') {
    const speechPermission = await SpeechTranscriber.requestPermissions();
    if (speechPermission !== 'authorized') {
      console.log('Speech permission denied');
      return;
    }
  }

  const micPermission = await SpeechTranscriber.requestMicrophonePermissions();
  if (micPermission !== 'granted') {
    console.log('Microphone permission denied');
    return;
  }

  // Check if Spanish is available
  const isSpanishAvailable = await SpeechTranscriber.isLanguageAvailable('es-ES');
  if (!isSpanishAvailable) {
    console.log('Spanish not supported on this device');
    
    // Show available languages
    const languages = await SpeechTranscriber.getAvailableLanguages();
    console.log('Available languages:', languages);
    return;
  }

  // Set language to Spanish
  await SpeechTranscriber.setLanguage('es-ES');
  console.log('Language set to Spanish');

  // Start transcription
  await SpeechTranscriber.recordRealTimeAndTranscribe();
  console.log('Recording in Spanish...');
}

// For file transcription with different language
async function transcribeFileInFrench(audioUri: string) {
  await SpeechTranscriber.setLanguage('fr-FR');
  const text = await SpeechTranscriber.transcribeAudioWithSFRecognizer(audioUri);
  console.log('French transcription:', text);
}
```

## Example

See the [example app](./example) for a complete implementation demonstrating all APIs.

## Requirements

### iOS
- iOS 13.0+
- Expo SDK 52+
- Development build (Expo Go not supported - [why?](https://expo.dev/blog/expo-go-vs-development-builds))

### Android
- Android 13+ (API level 33)
- Expo SDK 52+
- Development build (Expo Go not supported)

## Limitations

- **Language availability** - Supported languages vary by device and OS version. Use `getAvailableLanguages()` to check what's supported on the current device
- **File size** - Best for short recordings (< 1 minute)
- **Recording not included** - Real-time transcription captures audio internally; file transcription requires pre-recorded audio files (use `expo-audio` or implement your own recording with `requestMicrophonePermissions()`)
- **Android file transcription** - File-based transcription (`transcribeAudioWithSFRecognizer`, `transcribeAudioWithAnalyzer`) is iOS only. Android supports real-time transcription
- **Android API level** - Android requires API level 33+ (Android 13)

## License

MIT

## Contributing

Contributions welcome! Please open an issue or PR on [GitHub](https://github.com/daveyeke).

## Author

Dave Mkpa Eke - [GitHub](https://github.com/daveyeke) | [X](https://x.com/1804davey)
