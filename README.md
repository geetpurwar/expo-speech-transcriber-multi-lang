# expo-speech-transcriber

On-device speech transcription for Expo apps. Supports iOS (Apple Speech framework) and Android (SpeechRecognizer API).

## Features

- 🎯 **On-device transcription** — Works offline, privacy-focused
- 📱 **Cross-platform** — iOS 13+ and Android 13+ (API 33)
- 🚀 **Multiple APIs** — SFSpeechRecognizer (iOS 13+), SpeechTranscriber (iOS 26+), and Android SpeechRecognizer
- ✨ **Universal API** — Automatically selects the best API for your device
- 🆕 **iOS 26 Direct API** — Explicitly target the new SpeechTranscriber for maximum performance
- 🌍 **60+ Languages** — Pass a BCP-47 language code directly into any real-time function
- 📦 **Easy integration** — Auto-configures permissions via Expo config plugin
- 🔒 **Secure** — All processing happens on device
- ⚡ **Real-time transcription** — Live speech-to-text with built-in audio capture
- 📁 **File transcription** — Transcribe pre-recorded audio files
- 🎤 **Buffer-based transcription** — Stream audio buffers from external sources

---

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

### Custom permission messages (recommended)

Apple requires a clear purpose string for speech recognition and microphone permissions. Without it, your app may be rejected during App Store review.

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

> **Note for Android:** The plugin automatically adds the `RECORD_AUDIO` permission to your Android manifest. No additional configuration is required.

---

## Real-Time Transcription APIs

There are three ways to start real-time transcription. All three fire the same `onTranscriptionProgress` and `onTranscriptionError` events and work with the `useRealTimeTranscription()` hook.

### API Comparison

| Function | Platform | iOS Requirement | Language Parameter |
|---|---|---|---|
| `recordRealTimeAndTranscribeUniversal()` | iOS + Android | iOS 13+ | ✅ Inline `language` option |
| `recordRealTimeAndTranscribeWithSpeechTranscriber()` | iOS only | iOS 26+ | ✅ Inline `language` option |
| `recordRealTimeAndTranscribe()` | iOS + Android | iOS 13+ | ❌ Use `setLanguage()` separately |

---

### 🌟 Universal Real-Time Transcription (Recommended for most apps)

Automatically picks the best available API. On iOS 26+ it uses `SpeechTranscriber` for lower latency and higher accuracy. On iOS 13–25 and Android it falls back to the proven `SFSpeechRecognizer` / `SpeechRecognizer` APIs.

Pass a BCP-47 language code directly in the options — no need to call `setLanguage()` separately.

```typescript
import * as SpeechTranscriber from 'expo-speech-transcriber';
import { Platform } from 'react-native';

async function startTranscription() {
  // Request permissions
  if (Platform.OS === 'ios') {
    const speechPermission = await SpeechTranscriber.requestPermissions();
    if (speechPermission !== 'authorized') return;
  }
  const micPermission = await SpeechTranscriber.requestMicrophonePermissions();
  if (micPermission !== 'granted') return;

  // Use device default language
  await SpeechTranscriber.recordRealTimeAndTranscribeUniversal();

  // OR pass a language code inline — no setLanguage() call needed
  await SpeechTranscriber.recordRealTimeAndTranscribeUniversal({ language: 'es-ES' });
  await SpeechTranscriber.recordRealTimeAndTranscribeUniversal({ language: 'hi-IN' });
  await SpeechTranscriber.recordRealTimeAndTranscribeUniversal({ language: 'vi-VN' });
  await SpeechTranscriber.recordRealTimeAndTranscribeUniversal({ language: 'fr-FR' });
  await SpeechTranscriber.recordRealTimeAndTranscribeUniversal({ language: 'zh-CN' });
  await SpeechTranscriber.recordRealTimeAndTranscribeUniversal({ language: 'ar-SA' });
}

function TranscriptionScreen() {
  const { text, isFinal, error, isRecording } =
    SpeechTranscriber.useRealTimeTranscription();

  return (
    <View>
      <Text>Status: {isRecording ? 'Recording...' : 'Stopped'}</Text>
      <Text>Text: {text}</Text>
      {isFinal && <Text>✅ Final result</Text>}
      {error && <Text style={{ color: 'red' }}>Error: {error}</Text>}
      <Button title="Start" onPress={startTranscription} />
      <Button title="Stop" onPress={() => SpeechTranscriber.stopListening()} />
    </View>
  );
}
```

**Which API is selected automatically:**

| Platform | OS Version | API Used | Benefit |
|---|---|---|---|
| iOS | 26+ | **SpeechTranscriber** | Lower latency, better accuracy, on-device |
| iOS | 13–25 | **SFSpeechRecognizer** | Proven, widely compatible |
| Android | 13+ | **SpeechRecognizer** | Native Android API |

---

### 🆕 iOS 26 SpeechTranscriber (Direct, explicit)

Use this when you want to explicitly target the new Apple `SpeechTranscriber` API and don't need a fallback. Provides the best possible accuracy and lowest latency on iOS 26+.

**Throws an error on iOS below 26.** Always guard with `isAnalyzerAvailable()` before calling.

Pass a BCP-47 language code directly in the options — no need to call `setLanguage()` separately.

```typescript
import * as SpeechTranscriber from 'expo-speech-transcriber';

async function startWithSpeechTranscriber() {
  // Guard: only available on iOS 26+
  if (!SpeechTranscriber.isAnalyzerAvailable()) {
    console.warn('SpeechTranscriber requires iOS 26+');
    return;
  }

  // Request permissions
  const speechPermission = await SpeechTranscriber.requestPermissions();
  if (speechPermission !== 'authorized') return;
  const micPermission = await SpeechTranscriber.requestMicrophonePermissions();
  if (micPermission !== 'granted') return;

  // Use device default language
  await SpeechTranscriber.recordRealTimeAndTranscribeWithSpeechTranscriber();

  // OR pass a language code inline — no setLanguage() call needed
  await SpeechTranscriber.recordRealTimeAndTranscribeWithSpeechTranscriber({ language: 'en-US' });
  await SpeechTranscriber.recordRealTimeAndTranscribeWithSpeechTranscriber({ language: 'hi-IN' });
  await SpeechTranscriber.recordRealTimeAndTranscribeWithSpeechTranscriber({ language: 'vi-VN' });
  await SpeechTranscriber.recordRealTimeAndTranscribeWithSpeechTranscriber({ language: 'ja-JP' });
}

function TranscriptionScreen() {
  const { text, isFinal, error, isRecording } =
    SpeechTranscriber.useRealTimeTranscription();

  return (
    <View>
      <Text>Status: {isRecording ? 'Recording...' : 'Stopped'}</Text>
      <Text>Text: {text}</Text>
      {isFinal && <Text>✅ Final result</Text>}
      {error && <Text style={{ color: 'red' }}>Error: {error}</Text>}
      <Button title="Start (iOS 26+)" onPress={startWithSpeechTranscriber} />
      <Button title="Stop" onPress={() => SpeechTranscriber.stopListening()} />
    </View>
  );
}
```

> **When to use this vs Universal?**
> Use `recordRealTimeAndTranscribeWithSpeechTranscriber` when you are building an iOS 26-only feature and want to guarantee you're always on the new API. Use `recordRealTimeAndTranscribeUniversal` for any app that needs to support iOS 13+ or Android.

---

### Legacy Real-Time (SFSpeechRecognizer)

For new projects, prefer `recordRealTimeAndTranscribeUniversal()`. This legacy function does not accept a language parameter — use `setLanguage()` before calling it.

```typescript
import * as SpeechTranscriber from 'expo-speech-transcriber';
import { Platform } from 'react-native';

// Set language separately (required for this API)
await SpeechTranscriber.setLanguage('es-ES');

// Request permissions
if (Platform.OS === 'ios') {
  const speechPermission = await SpeechTranscriber.requestPermissions();
  if (speechPermission !== 'authorized') return;
}
const micPermission = await SpeechTranscriber.requestMicrophonePermissions();
if (micPermission !== 'granted') return;

// Start
await SpeechTranscriber.recordRealTimeAndTranscribe();

// Stop
SpeechTranscriber.stopListening();
```

---

## File Transcription

Transcribe pre-recorded audio files. Uses `expo-audio` for recording or your own recording implementation.

```typescript
import * as SpeechTranscriber from 'expo-speech-transcriber';
import { useAudioRecorder, RecordingPresets } from 'expo-audio';

const audioRecorder = useAudioRecorder(RecordingPresets.HIGH_QUALITY);
await audioRecorder.prepareToRecordAsync();
audioRecorder.record();
// ... user speaks ...
await audioRecorder.stop();
const audioUri = audioRecorder.uri;

// Transcribe with SFSpeechRecognizer (iOS 13+, preferred)
const text = await SpeechTranscriber.transcribeAudioWithSFRecognizer(audioUri);

// OR with SpeechAnalyzer (iOS 26+ only)
if (SpeechTranscriber.isAnalyzerAvailable()) {
  const text = await SpeechTranscriber.transcribeAudioWithAnalyzer(audioUri);
}
```

Both file transcription methods respect the language set via `setLanguage()`.

---

## Buffer-Based Transcription

Stream raw PCM audio buffers directly — ideal for integrating with audio processing libraries like [react-native-audio-api](https://docs.swmansion.com/react-native-audio-api/).

```typescript
import * as SpeechTranscriber from 'expo-speech-transcriber';
import { AudioManager, AudioRecorder } from 'react-native-audio-api';

const recorder = new AudioRecorder({ sampleRate: 16000, bufferLengthInSamples: 1600 });

AudioManager.setAudioSessionOptions({
  iosCategory: 'playAndRecord',
  iosMode: 'spokenAudio',
  iosOptions: ['allowBluetooth', 'defaultToSpeaker'],
});

await SpeechTranscriber.requestPermissions();
await AudioManager.requestRecordingPermissions();

// Optionally set language before streaming
await SpeechTranscriber.setLanguage('fr-FR');

recorder.onAudioReady(({ buffer }) => {
  const channelData = buffer.getChannelData(0);
  SpeechTranscriber.realtimeBufferTranscribe(channelData, 16000);
});

const { text, isFinal, error } = SpeechTranscriber.useRealTimeTranscription();

recorder.start();
// When done:
recorder.stop();
SpeechTranscriber.stopBufferTranscription();
```

> **Note:** Only mono audio (1 channel) is supported. The channel count is hardcoded to 1 in the native layer.

---

## Language Support

All real-time functions accept a BCP-47 language code either **inline** (Universal and SpeechTranscriber APIs) or via **`setLanguage()`** (legacy API and buffer-based API).

### Inline language (Universal & SpeechTranscriber APIs)

```typescript
// Pass directly in options — takes effect immediately for this session
await SpeechTranscriber.recordRealTimeAndTranscribeUniversal({ language: 'vi-VN' });
await SpeechTranscriber.recordRealTimeAndTranscribeWithSpeechTranscriber({ language: 'hi-IN' });
```

### setLanguage() (all APIs)

```typescript
// Set globally — affects all subsequent transcription calls
await SpeechTranscriber.setLanguage('ko-KR');
await SpeechTranscriber.recordRealTimeAndTranscribe();

// Check what's currently set
const current = await SpeechTranscriber.getCurrentLanguage(); // 'ko-KR'

// Check if a language is supported on this device
const available = await SpeechTranscriber.isLanguageAvailable('ar-SA'); // boolean

// Get all supported languages on this device
const languages = await SpeechTranscriber.getAvailableLanguages(); // string[]
```

### Common BCP-47 Locale Codes

| Language | Code | Language | Code |
|---|---|---|---|
| English (US) | `en-US` | Arabic (Saudi Arabia) | `ar-SA` |
| English (UK) | `en-GB` | Hindi (India) | `hi-IN` |
| Spanish (Spain) | `es-ES` | Vietnamese | `vi-VN` |
| Spanish (Mexico) | `es-MX` | Korean | `ko-KR` |
| French (France) | `fr-FR` | Japanese | `ja-JP` |
| German (Germany) | `de-DE` | Chinese (Simplified) | `zh-CN` |
| Italian (Italy) | `it-IT` | Chinese (Traditional) | `zh-TW` |
| Portuguese (Brazil) | `pt-BR` | Dutch (Netherlands) | `nl-NL` |
| Portuguese (Portugal) | `pt-PT` | Polish (Poland) | `pl-PL` |
| Russian (Russia) | `ru-RU` | Turkish (Turkey) | `tr-TR` |

Use `getAvailableLanguages()` to get the exact list for the current device, as support varies by OS version and device.

---

## API Reference

### Real-Time Transcription

---

#### `recordRealTimeAndTranscribeUniversal(options?)`

**⭐ Recommended** — Start real-time transcription using the best available API. Automatically selects `SpeechTranscriber` on iOS 26+, `SFSpeechRecognizer` on iOS 13–25, and `SpeechRecognizer` on Android.

**Platforms:** iOS 13+, Android 13+

**Parameters:**

```typescript
interface UniversalTranscriptionOptions {
  language?: string; // BCP-47 locale code. Default: device language
}
```

**Returns:** `Promise<void>`

```typescript
await SpeechTranscriber.recordRealTimeAndTranscribeUniversal();
await SpeechTranscriber.recordRealTimeAndTranscribeUniversal({ language: 'es-MX' });
```

---

#### `recordRealTimeAndTranscribeWithSpeechTranscriber(options?)` 🆕

Start real-time transcription using the **iOS 26+ SpeechTranscriber API directly**. Provides the lowest latency and highest accuracy available on Apple devices.

**Platform:** iOS 26+ only. Throws `ERR_NOT_SUPPORTED` on Android and throws an `NSError` (code 501) on iOS below 26. Always guard with `isAnalyzerAvailable()`.

**Parameters:**

```typescript
interface UniversalTranscriptionOptions {
  language?: string; // BCP-47 locale code. Default: currently set language
}
```

**Returns:** `Promise<void>` — resolves when transcription starts; rejects on iOS < 26 or Android

```typescript
if (SpeechTranscriber.isAnalyzerAvailable()) {
  await SpeechTranscriber.recordRealTimeAndTranscribeWithSpeechTranscriber();
  await SpeechTranscriber.recordRealTimeAndTranscribeWithSpeechTranscriber({ language: 'hi-IN' });
}
```

---

#### `recordRealTimeAndTranscribe()`

Start real-time transcription using `SFSpeechRecognizer` (iOS) or `SpeechRecognizer` (Android). Does not accept a language parameter — call `setLanguage()` before starting.

**Platforms:** iOS 13+, Android 13+

**Returns:** `Promise<void>`

```typescript
await SpeechTranscriber.setLanguage('fr-FR');
await SpeechTranscriber.recordRealTimeAndTranscribe();
```

---

#### `stopListening()`

Stop any active real-time transcription session (works for all three real-time APIs).

**Returns:** `void`

```typescript
SpeechTranscriber.stopListening();
```

---

#### `isRecording()`

Check if real-time transcription is currently active.

**Returns:** `boolean`

```typescript
const recording = SpeechTranscriber.isRecording();
```

---

#### `useRealTimeTranscription()`

React hook that subscribes to transcription events and exposes reactive state. Works with all real-time transcription APIs.

**Returns:**

```typescript
{
  text: string;        // Current transcription text (partial or final)
  isFinal: boolean;    // True when the current result is final
  error: string | null; // Error message if something went wrong
  isRecording: boolean; // Whether transcription is currently active
}
```

```typescript
const { text, isFinal, error, isRecording } =
  SpeechTranscriber.useRealTimeTranscription();
```

---

### File Transcription

---

#### `transcribeAudioWithSFRecognizer(audioFilePath)`

Transcribe a pre-recorded audio file using `SFSpeechRecognizer`.

**Platform:** iOS only (iOS 13+)

**Parameters:** `audioFilePath: string` — file URI (e.g. `file:///path/to/audio.m4a`)

**Returns:** `Promise<string>` — transcribed text

```typescript
const text = await SpeechTranscriber.transcribeAudioWithSFRecognizer('file:///path/to/audio.m4a');
```

---

#### `transcribeAudioWithAnalyzer(audioFilePath)`

Transcribe a pre-recorded audio file using the iOS 26+ `SpeechAnalyzer`.

**Platform:** iOS 26+ only. Throws error on iOS < 26.

**Parameters:** `audioFilePath: string` — file URI

**Returns:** `Promise<string>` — transcribed text

```typescript
if (SpeechTranscriber.isAnalyzerAvailable()) {
  const text = await SpeechTranscriber.transcribeAudioWithAnalyzer('file:///path/to/audio.m4a');
}
```

---

### Buffer-Based Transcription

---

#### `realtimeBufferTranscribe(buffer, sampleRate)`

Stream raw PCM audio frames for real-time transcription. Call this repeatedly as audio frames arrive.

**Platform:** iOS only

**Parameters:**

- `buffer: Float32Array | number[]` — mono audio samples
- `sampleRate: number` — sample rate in Hz (e.g. `16000`, `44100`)

**Returns:** `Promise<void>`

```typescript
await SpeechTranscriber.realtimeBufferTranscribe(channelData, 16000);
```

---

#### `stopBufferTranscription()`

End the buffer transcription session and clean up resources.

**Returns:** `void`

```typescript
SpeechTranscriber.stopBufferTranscription();
```

---

### Permissions

---

#### `requestPermissions()`

Request speech recognition permission.

**Platform:** iOS only. On Android, `requestMicrophonePermissions()` is sufficient.

**Returns:** `Promise<'authorized' | 'denied' | 'restricted' | 'notDetermined'>`

```typescript
import { Platform } from 'react-native';
if (Platform.OS === 'ios') {
  const status = await SpeechTranscriber.requestPermissions();
}
```

---

#### `requestMicrophonePermissions()`

Request microphone permission.

**Returns:** `Promise<'granted' | 'denied'>`

```typescript
const status = await SpeechTranscriber.requestMicrophonePermissions();
```

---

### Availability

---

#### `isAnalyzerAvailable()`

Check whether the iOS 26+ `SpeechTranscriber` / `SpeechAnalyzer` API is available on the current device. Always returns `false` on Android.

**Returns:** `boolean`

```typescript
if (SpeechTranscriber.isAnalyzerAvailable()) {
  // Safe to call iOS 26+ APIs
}
```

---

### Language Configuration

---

#### `setLanguage(localeCode)`

Set the language for all subsequent transcription calls. For Universal and SpeechTranscriber APIs, you can pass language inline instead — but `setLanguage()` still works and is the only option for the legacy and buffer-based APIs.

**Platforms:** iOS, Android

**Parameters:** `localeCode: string` — BCP-47 locale code

**Returns:** `Promise<void>`

```typescript
await SpeechTranscriber.setLanguage('vi-VN');
await SpeechTranscriber.setLanguage('ar-SA');
await SpeechTranscriber.setLanguage('zh-CN');
```

---

#### `getAvailableLanguages()`

Get all language codes supported on the current device.

**Platforms:** iOS, Android

**Returns:** `Promise<string[]>`

```typescript
const languages = await SpeechTranscriber.getAvailableLanguages();
// ['en-US', 'es-ES', 'fr-FR', ...]
```

---

#### `getCurrentLanguage()`

Get the currently active language code.

**Platforms:** iOS, Android

**Returns:** `Promise<string>`

```typescript
const lang = await SpeechTranscriber.getCurrentLanguage(); // e.g. 'en-US'
```

---

#### `isLanguageAvailable(localeCode)`

Check whether a specific language is supported on the current device.

**Platforms:** iOS, Android

**Parameters:** `localeCode: string`

**Returns:** `Promise<boolean>`

```typescript
const ok = await SpeechTranscriber.isLanguageAvailable('hi-IN');
```

---

## Complete Examples

### Universal API with inline language (cross-platform)

```typescript
import * as SpeechTranscriber from 'expo-speech-transcriber';
import { Platform } from 'react-native';

async function start(language: string) {
  if (Platform.OS === 'ios') {
    const sp = await SpeechTranscriber.requestPermissions();
    if (sp !== 'authorized') return;
  }
  const mic = await SpeechTranscriber.requestMicrophonePermissions();
  if (mic !== 'granted') return;

  await SpeechTranscriber.recordRealTimeAndTranscribeUniversal({ language });
}

function App() {
  const { text, isFinal, error, isRecording } =
    SpeechTranscriber.useRealTimeTranscription();

  return (
    <View>
      <Button title="English" onPress={() => start('en-US')} />
      <Button title="Spanish" onPress={() => start('es-MX')} />
      <Button title="Hindi" onPress={() => start('hi-IN')} />
      <Button title="Vietnamese" onPress={() => start('vi-VN')} />
      <Button title="Stop" onPress={() => SpeechTranscriber.stopListening()} />
      <Text>{text}</Text>
    </View>
  );
}
```

### iOS 26 SpeechTranscriber with inline language

```typescript
import * as SpeechTranscriber from 'expo-speech-transcriber';

async function startIOS26(language: string) {
  if (!SpeechTranscriber.isAnalyzerAvailable()) {
    console.warn('iOS 26+ required');
    return;
  }
  const sp = await SpeechTranscriber.requestPermissions();
  if (sp !== 'authorized') return;
  const mic = await SpeechTranscriber.requestMicrophonePermissions();
  if (mic !== 'granted') return;

  await SpeechTranscriber.recordRealTimeAndTranscribeWithSpeechTranscriber({ language });
}

function App() {
  const { text, isFinal, error, isRecording } =
    SpeechTranscriber.useRealTimeTranscription();

  return (
    <View>
      <Button title="English (iOS 26)" onPress={() => startIOS26('en-US')} />
      <Button title="Japanese (iOS 26)" onPress={() => startIOS26('ja-JP')} />
      <Button title="Stop" onPress={() => SpeechTranscriber.stopListening()} />
      <Text>{text}</Text>
    </View>
  );
}
```

### File transcription with language

```typescript
import * as SpeechTranscriber from 'expo-speech-transcriber';
import { useAudioRecorder, RecordingPresets } from 'expo-audio';

async function transcribeFile(audioUri: string, language: string) {
  await SpeechTranscriber.setLanguage(language);

  if (SpeechTranscriber.isAnalyzerAvailable()) {
    return await SpeechTranscriber.transcribeAudioWithAnalyzer(audioUri);
  }
  return await SpeechTranscriber.transcribeAudioWithSFRecognizer(audioUri);
}
```

---

## Requirements

### iOS
- iOS 13.0+ (real-time and SFSpeechRecognizer)
- iOS 26.0+ (SpeechTranscriber and SpeechAnalyzer APIs)
- Expo SDK 52+
- Development build required (Expo Go not supported — [why?](https://expo.dev/blog/expo-go-vs-development-builds))

### Android
- Android 13+ (API level 33)
- Expo SDK 52+
- Development build required

---

## Limitations

- **Language availability** — Supported languages vary by device and OS version. Use `getAvailableLanguages()` to check what's available.
- **File size** — Best for short recordings (under 1 minute).
- **Recording not included** — Real-time APIs handle audio capture internally. File transcription requires a pre-recorded file (use `expo-audio` or your own implementation).
- **Android file transcription** — `transcribeAudioWithSFRecognizer` and `transcribeAudioWithAnalyzer` are iOS only.
- **Buffer transcription** — iOS only. Mono audio only (1 channel).
- **SpeechTranscriber** — iOS 26+ only. On Android and iOS < 26, use Universal or legacy APIs.

---

## Example App

See the [example](./example) directory for a complete implementation demonstrating all APIs, including real-time, file, buffer-based, and multi-language transcription.

---

## License

MIT

## Contributing

Contributions welcome! Open an issue or PR on [GitHub](https://github.com/geetpurwar/expo-speech-transcriber-multi-lang).

## Author

Dave Mkpa Eke — [GitHub](https://github.com/daveyeke) | [X](https://x.com/1804davey)
