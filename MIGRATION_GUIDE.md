# Migration Guide: Multi-Language Support

This guide helps you migrate from the English-only version to the multi-language version of expo-speech-transcriber.

## Overview

The plugin now supports transcription in any language available on the device. Previously, it was hardcoded to English (en_US locale).

## Breaking Changes

### iOS
- **Previous behavior**: Always used English (en_US)
- **New behavior**: Defaults to English (en_US) but can be changed
- **Impact**: Minimal - existing code continues to work with English

### Android
- **Previous behavior**: Used device default language
- **New behavior**: Still uses device default language but can now be changed
- **Impact**: None for most users; devices already set to English will continue working

## What You Need to Do

### Option 1: No Changes (Keep Using English)

If your app only needs English transcription, you don't need to change anything. The plugin still defaults to English on iOS and respects the device language on Android.

```typescript
// This still works exactly as before
await SpeechTranscriber.recordRealTimeAndTranscribe();
```

### Option 2: Add Multi-Language Support

If you want to support multiple languages, follow these steps:

#### Step 1: Check Available Languages

```typescript
import * as SpeechTranscriber from 'expo-speech-transcriber';

// Get all available languages on this device
const languages = await SpeechTranscriber.getAvailableLanguages();
console.log('Supported languages:', languages);
// Output: ['en-US', 'es-ES', 'fr-FR', 'de-DE', ...]
```

#### Step 2: Let Users Select Language

```typescript
import { Picker } from '@react-native-picker/picker';

function LanguageSelector() {
  const [languages, setLanguages] = useState<string[]>([]);
  const [selected, setSelected] = useState('en-US');

  useEffect(() => {
    loadLanguages();
  }, []);

  const loadLanguages = async () => {
    const available = await SpeechTranscriber.getAvailableLanguages();
    setLanguages(available);
  };

  const handleChange = async (lang: string) => {
    setSelected(lang);
    await SpeechTranscriber.setLanguage(lang);
  };

  return (
    <Picker selectedValue={selected} onValueChange={handleChange}>
      {languages.map(lang => (
        <Picker.Item key={lang} label={lang} value={lang} />
      ))}
    </Picker>
  );
}
```

#### Step 3: Set Language Before Transcription

```typescript
// Always set language before starting transcription
await SpeechTranscriber.setLanguage('es-ES'); // Spanish
await SpeechTranscriber.recordRealTimeAndTranscribe();
```

## Common Migration Patterns

### Pattern 1: App with Fixed Language

If your app always uses a specific non-English language:

```typescript
// Before (didn't work properly)
await SpeechTranscriber.recordRealTimeAndTranscribe();

// After (explicitly set language)
async function startSpanishTranscription() {
  await SpeechTranscriber.setLanguage('es-ES');
  await SpeechTranscriber.recordRealTimeAndTranscribe();
}
```

### Pattern 2: App with User Language Preference

If users can choose their language:

```typescript
import AsyncStorage from '@react-native-async-storage/async-storage';

// Save user's language preference
async function saveLanguagePreference(language: string) {
  await AsyncStorage.setItem('transcription_language', language);
  await SpeechTranscriber.setLanguage(language);
}

// Load language preference on app start
async function loadLanguagePreference() {
  const saved = await AsyncStorage.getItem('transcription_language');
  if (saved) {
    const isAvailable = await SpeechTranscriber.isLanguageAvailable(saved);
    if (isAvailable) {
      await SpeechTranscriber.setLanguage(saved);
    } else {
      // Fallback to English if saved language not available
      await SpeechTranscriber.setLanguage('en-US');
    }
  }
}
```

### Pattern 3: App Following System Language

If you want to match the device's system language:

```typescript
import { NativeModules, Platform } from 'react-native';

async function useSystemLanguage() {
  const deviceLanguage = Platform.OS === 'ios'
    ? NativeModules.SettingsManager.settings.AppleLocale ||
      NativeModules.SettingsManager.settings.AppleLanguages[0]
    : NativeModules.I18nManager.localeIdentifier;

  // Normalize format (e.g., en_US to en-US)
  const normalized = deviceLanguage.replace('_', '-');

  // Check if available
  const isAvailable = await SpeechTranscriber.isLanguageAvailable(normalized);
  
  if (isAvailable) {
    await SpeechTranscriber.setLanguage(normalized);
  } else {
    // Fallback to English
    await SpeechTranscriber.setLanguage('en-US');
  }
}
```

### Pattern 4: Multi-Language Document Processing

If processing documents in different languages:

```typescript
async function transcribeMultipleFiles(files: Array<{uri: string, language: string}>) {
  const results = [];
  
  for (const file of files) {
    // Set language for each file
    await SpeechTranscriber.setLanguage(file.language);
    
    // Transcribe
    const text = await SpeechTranscriber.transcribeAudioWithSFRecognizer(file.uri);
    results.push({ language: file.language, text });
  }
  
  return results;
}

// Usage
const transcriptions = await transcribeMultipleFiles([
  { uri: 'file://english.m4a', language: 'en-US' },
  { uri: 'file://spanish.m4a', language: 'es-ES' },
  { uri: 'file://french.m4a', language: 'fr-FR' },
]);
```

## Validation and Error Handling

Always validate language availability:

```typescript
async function safeSetLanguage(localeCode: string) {
  try {
    // Check if language is available
    const isAvailable = await SpeechTranscriber.isLanguageAvailable(localeCode);
    
    if (!isAvailable) {
      console.warn(`Language ${localeCode} not available`);
      
      // Show available languages to user
      const available = await SpeechTranscriber.getAvailableLanguages();
      console.log('Available languages:', available);
      
      // Fallback to English
      await SpeechTranscriber.setLanguage('en-US');
      return false;
    }
    
    await SpeechTranscriber.setLanguage(localeCode);
    return true;
  } catch (error) {
    console.error('Error setting language:', error);
    return false;
  }
}
```

## Locale Code Reference

Use BCP-47 locale codes (language-REGION format):

| ❌ Incorrect | ✅ Correct | Language |
|--------------|------------|----------|
| `'en'` | `'en-US'` | English (US) |
| `'es'` | `'es-ES'` | Spanish (Spain) |
| `'zh'` | `'zh-CN'` | Chinese (Simplified) |
| `'ar'` | `'ar-SA'` | Arabic (Saudi Arabia) |
| `'en_US'` | `'en-US'` | English (US) |

The plugin accepts both formats but prefers hyphens over underscores.

## Testing Your Migration

1. **Test with English**: Ensure existing functionality still works
   ```typescript
   await SpeechTranscriber.setLanguage('en-US');
   await SpeechTranscriber.recordRealTimeAndTranscribe();
   ```

2. **Test with another language**: Verify multi-language support
   ```typescript
   await SpeechTranscriber.setLanguage('es-ES');
   await SpeechTranscriber.recordRealTimeAndTranscribe();
   // Speak in Spanish and verify transcription
   ```

3. **Test language switching**: Ensure language changes between sessions
   ```typescript
   await SpeechTranscriber.setLanguage('en-US');
   await SpeechTranscriber.recordRealTimeAndTranscribe();
   // ... record English
   SpeechTranscriber.stopListening();
   
   await SpeechTranscriber.setLanguage('fr-FR');
   await SpeechTranscriber.recordRealTimeAndTranscribe();
   // ... record French
   ```

4. **Test unavailable language**: Ensure proper error handling
   ```typescript
   const isAvailable = await SpeechTranscriber.isLanguageAvailable('xx-XX');
   // Should return false
   ```

## Troubleshooting

### Issue: Language not changing

**Solution**: Ensure you set language **before** starting transcription:
```typescript
// ❌ Wrong
await SpeechTranscriber.recordRealTimeAndTranscribe();
await SpeechTranscriber.setLanguage('es-ES'); // Too late!

// ✅ Correct
await SpeechTranscriber.setLanguage('es-ES');
await SpeechTranscriber.recordRealTimeAndTranscribe();
```

### Issue: Language not available error

**Solution**: Check availability first:
```typescript
const isAvailable = await SpeechTranscriber.isLanguageAvailable('es-ES');
if (!isAvailable) {
  // Handle unavailable language
  const alternatives = await SpeechTranscriber.getAvailableLanguages();
  console.log('Try one of these:', alternatives);
}
```

### Issue: Android doesn't recognize language

**Solution**: Use correct locale format:
```typescript
// ❌ Wrong
await SpeechTranscriber.setLanguage('Spanish');

// ✅ Correct
await SpeechTranscriber.setLanguage('es-ES');
```

## Support

If you encounter issues during migration:

1. Check that you're using the latest version
2. Verify locale codes match BCP-47 format
3. Test on physical devices (simulators may have limited language support)
4. Check available languages on the specific device
5. Open an issue on [GitHub](https://github.com/DaveyEke/expo-speech-transcriber/issues)

## Complete Example

See `MultiLanguageExample.tsx` for a complete, working example demonstrating:
- Loading available languages
- User language selection
- Language validation
- Transcription in multiple languages
- Error handling

## Summary

- ✅ Existing English-only apps: No changes needed
- ✅ Multi-language apps: Add language selection UI
- ✅ Always set language before transcription
- ✅ Validate language availability
- ✅ Handle errors gracefully

The migration is designed to be backward compatible while enabling powerful new multi-language capabilities.
