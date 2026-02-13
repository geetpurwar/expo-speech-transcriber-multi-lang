# Quick Start: Multi-Language Speech Transcription

Get started with multi-language speech transcription in 5 minutes!

## Installation

```bash
npx expo install expo-speech-transcriber expo-audio
```

Add to your `app.json`:

```json
{
  "expo": {
    "plugins": [
      "expo-audio",
      [
        "expo-speech-transcriber",
        {
          "speechRecognitionPermission": "We need speech recognition to transcribe your recordings",
          "microphonePermission": "We need microphone access to record audio"
        }
      ]
    ]
  }
}
```

Rebuild your development build:
```bash
npx expo prebuild
npx expo run:ios
# or
npx expo run:android
```

## Basic Usage (English)

```typescript
import * as SpeechTranscriber from 'expo-speech-transcriber';
import { Platform } from 'react-native';

// Request permissions
if (Platform.OS === 'ios') {
  await SpeechTranscriber.requestPermissions();
}
await SpeechTranscriber.requestMicrophonePermissions();

// Start recording
await SpeechTranscriber.recordRealTimeAndTranscribe();

// Listen for results
const { text } = SpeechTranscriber.useRealTimeTranscription();

// Stop recording
SpeechTranscriber.stopListening();
```

## Multi-Language Usage

### 1. Check Available Languages

```typescript
const languages = await SpeechTranscriber.getAvailableLanguages();
console.log(languages);
// ['en-US', 'es-ES', 'fr-FR', 'de-DE', 'zh-CN', ...]
```

### 2. Set Your Language

```typescript
// Spanish
await SpeechTranscriber.setLanguage('es-ES');

// French
await SpeechTranscriber.setLanguage('fr-FR');

// Arabic
await SpeechTranscriber.setLanguage('ar-SA');

// Chinese
await SpeechTranscriber.setLanguage('zh-CN');
```

### 3. Start Transcribing

```typescript
await SpeechTranscriber.recordRealTimeAndTranscribe();
```

That's it! Speak in your selected language.

## Complete Example Component

```typescript
import React, { useState } from 'react';
import { View, Button, Text, StyleSheet } from 'react-native';
import * as SpeechTranscriber from 'expo-speech-transcriber';

export default function App() {
  const [language, setLanguage] = useState('en-US');
  const { text, isRecording } = SpeechTranscriber.useRealTimeTranscription();

  const startRecording = async () => {
    // Set language before recording
    await SpeechTranscriber.setLanguage(language);
    await SpeechTranscriber.recordRealTimeAndTranscribe();
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Speech Transcription</Text>
      
      {/* Language Buttons */}
      <View style={styles.languageButtons}>
        <Button title="English" onPress={() => setLanguage('en-US')} />
        <Button title="Spanish" onPress={() => setLanguage('es-ES')} />
        <Button title="French" onPress={() => setLanguage('fr-FR')} />
      </View>

      {/* Recording Controls */}
      <Button 
        title={isRecording ? "Recording..." : "Start"} 
        onPress={startRecording}
        disabled={isRecording}
      />
      <Button 
        title="Stop" 
        onPress={SpeechTranscriber.stopListening}
        disabled={!isRecording}
      />

      {/* Transcription Result */}
      <View style={styles.result}>
        <Text>Language: {language}</Text>
        <Text style={styles.text}>{text || 'Press Start to begin'}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 20, justifyContent: 'center' },
  title: { fontSize: 24, fontWeight: 'bold', marginBottom: 20 },
  languageButtons: { flexDirection: 'row', gap: 10, marginBottom: 20 },
  result: { marginTop: 20, padding: 15, backgroundColor: '#f5f5f5' },
  text: { fontSize: 16, marginTop: 10 },
});
```

## Common Languages

| Language | Code | Example Usage |
|----------|------|---------------|
| English (US) | `en-US` | `setLanguage('en-US')` |
| Spanish | `es-ES` | `setLanguage('es-ES')` |
| French | `fr-FR` | `setLanguage('fr-FR')` |
| German | `de-DE` | `setLanguage('de-DE')` |
| Chinese | `zh-CN` | `setLanguage('zh-CN')` |
| Japanese | `ja-JP` | `setLanguage('ja-JP')` |
| Arabic | `ar-SA` | `setLanguage('ar-SA')` |
| Hindi | `hi-IN` | `setLanguage('hi-IN')` |

## Pro Tips

### ✅ Always Set Language Before Recording
```typescript
// ✅ Correct
await SpeechTranscriber.setLanguage('es-ES');
await SpeechTranscriber.recordRealTimeAndTranscribe();

// ❌ Wrong - Too late!
await SpeechTranscriber.recordRealTimeAndTranscribe();
await SpeechTranscriber.setLanguage('es-ES');
```

### ✅ Validate Language Availability
```typescript
const isAvailable = await SpeechTranscriber.isLanguageAvailable('es-ES');
if (isAvailable) {
  await SpeechTranscriber.setLanguage('es-ES');
} else {
  console.log('Spanish not available on this device');
}
```

### ✅ Save User Preference
```typescript
import AsyncStorage from '@react-native-async-storage/async-storage';

// Save
await AsyncStorage.setItem('language', 'es-ES');
await SpeechTranscriber.setLanguage('es-ES');

// Load on app start
const saved = await AsyncStorage.getItem('language');
if (saved) {
  await SpeechTranscriber.setLanguage(saved);
}
```

## File Transcription

Transcribe pre-recorded audio files:

```typescript
import { useAudioRecorder, RecordingPresets } from 'expo-audio';

// Record audio
const recorder = useAudioRecorder(RecordingPresets.HIGH_QUALITY);
await recorder.prepareToRecordAsync();
recorder.record();
// ... user speaks ...
await recorder.stop();

// Transcribe in Spanish
await SpeechTranscriber.setLanguage('es-ES');
const text = await SpeechTranscriber.transcribeAudioWithSFRecognizer(
  recorder.uri
);
console.log('Spanish transcription:', text);
```

## Troubleshooting

### Language Not Working?

1. **Check if language is available:**
   ```typescript
   const available = await SpeechTranscriber.getAvailableLanguages();
   console.log('Available:', available);
   ```

2. **Use correct format:**
   ```typescript
   // ❌ Wrong
   await SpeechTranscriber.setLanguage('Spanish');
   
   // ✅ Correct
   await SpeechTranscriber.setLanguage('es-ES');
   ```

3. **Set language BEFORE recording:**
   ```typescript
   await SpeechTranscriber.setLanguage('fr-FR');  // First
   await SpeechTranscriber.recordRealTimeAndTranscribe();  // Then
   ```

### Permissions Denied?

```typescript
import { Platform } from 'react-native';

if (Platform.OS === 'ios') {
  const speech = await SpeechTranscriber.requestPermissions();
  if (speech !== 'authorized') {
    Alert.alert('Permission Required', 'Please enable speech recognition');
  }
}

const mic = await SpeechTranscriber.requestMicrophonePermissions();
if (mic !== 'granted') {
  Alert.alert('Permission Required', 'Please enable microphone access');
}
```

## Next Steps

- 📖 Read the [full README](./README.md) for all features
- 🔄 Check the [Migration Guide](./MIGRATION_GUIDE.md) if upgrading
- 💡 See [MultiLanguageExample.tsx](./example/MultiLanguageExample.tsx) for a complete app
- 🐛 Report issues on [GitHub](https://github.com/DaveyEke/expo-speech-transcriber/issues)

## Need Help?

- 📚 [Full Documentation](./README.md)
- 💬 [GitHub Discussions](https://github.com/DaveyEke/expo-speech-transcriber/discussions)
- 🐛 [Report Bug](https://github.com/DaveyEke/expo-speech-transcriber/issues)
- ⭐ [Star on GitHub](https://github.com/DaveyEke/expo-speech-transcriber)

---

**Happy Transcribing! 🎤**
