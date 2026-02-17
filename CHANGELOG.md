# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased] - iOS 26 SpeechTranscriber Direct API + Bug Fixes

### Added

- **`recordRealTimeAndTranscribeWithSpeechTranscriber(options?)`** (iOS 26+ only)
  - New function that explicitly targets the Apple `SpeechTranscriber` API introduced in iOS 26
  - Accepts an optional `language` BCP-47 locale code inline — no need to call `setLanguage()` first
  - Throws a descriptive `NSError` (code 501) on iOS < 26
  - Returns `ERR_NOT_SUPPORTED` rejection on Android with a helpful message pointing to `recordRealTimeAndTranscribeUniversal`
  - Reuses the existing `recordRealTimeWithSpeechTranscriber()` private implementation — consistent behaviour with the Universal API on iOS 26+
  - Full TypeScript declaration added to `ExpoSpeechTranscriberModule.ts`
  - Full JSDoc with usage examples exported from `index.ts`

- **Android stub for `recordRealTimeAndTranscribeWithSpeechTranscriber`**
  - Kotlin module now declares the function and rejects with `ERR_NOT_SUPPORTED` instead of crashing

### Fixed

- **`TranscriptionErrorPayload.error` → `message` field mismatch**
  - `ExpoSpeechTranscriber.types.ts` previously declared `error: string` but both Swift and Kotlin send `"message"` as the key
  - This caused `error` state in `useRealTimeTranscription()` to always be `undefined`
  - Fixed: renamed field to `message: string` in the type and updated the hook to read `payload.message`

- **Missing native method declarations in `ExpoSpeechTranscriberModule.ts`**
  - The TypeScript native class declaration was missing `realtimeBufferTranscribe`, `stopBufferTranscription`, `setLanguage`, `getAvailableLanguages`, `getCurrentLanguage`, `isLanguageAvailable`, and `recordRealTimeAndTranscribeUniversal`
  - All methods are now fully declared, giving correct TypeScript types across the board

---

## [Unreleased] - Multi-Language Support

### Added

#### New API Methods

- **`setLanguage(localeCode: string): Promise<void>`**
  - Set the language for speech transcription
  - Accepts BCP-47 locale codes (e.g., 'es-ES', 'fr-FR', 'ar-SA', 'zh-CN')
  - Must be called before starting transcription
  - Available on both iOS and Android

- **`getAvailableLanguages(): Promise<string[]>`**
  - Returns array of all supported language locale codes on the current device
  - Useful for building language selection UI
  - Available on both iOS and Android

- **`getCurrentLanguage(): Promise<string>`**
  - Returns the currently selected language locale code
  - Defaults to 'en-US' on iOS, device language on Android
  - Available on both iOS and Android

- **`isLanguageAvailable(localeCode: string): Promise<boolean>`**
  - Check if a specific language is supported on the current device
  - Returns true if available, false otherwise
  - Available on both iOS and Android

#### iOS Implementation

- Added `currentLocale` property to store selected language
- Updated `SFSpeechRecognizer` initialization to use dynamic locale
- Updated `SpeechAnalyzer` configuration for dynamic locale
- Added language validation and error handling
- Defaults to English (en_US) if no language is set
- Supports all languages available through Apple's Speech framework

#### Android Implementation

- Added `currentLocale` property to store selected language
- Updated `SpeechRecognizer` intent to use dynamic locale
- Added language parsing for various locale formats (en-US, en_US, etc.)
- Defaults to device system language
- Supports all languages available through Android's SpeechRecognizer API

#### Documentation

- Comprehensive README updates with multi-language examples
- Added language configuration API reference section
- Created `MultiLanguageExample.tsx` demonstrating all language features
- Added table of common locale codes
- Complete multi-language usage examples

### Changed

- **BREAKING (Sort of)**: Language is no longer hardcoded to English
  - iOS now defaults to English (en_US)
  - Android now defaults to device language
  - Existing apps will continue to work but may see different behavior on Android
- Updated all transcription methods to respect language setting
- Improved error messages to include locale information

### Removed

- Removed hardcoded `en_US` locale from iOS implementation
- Removed `Locale.getDefault()` hardcoding from Android implementation

### Fixed

- Language selection now persists across transcription sessions
- Better error handling for unsupported languages
- Improved locale parsing for different formats

### Migration Guide

If you were relying on the previous behavior:

```typescript
// Before (implicit English only)
await SpeechTranscriber.recordRealTimeAndTranscribe();

// After (explicit language selection)
await SpeechTranscriber.setLanguage('en-US');
await SpeechTranscriber.recordRealTimeAndTranscribe();
```

For multi-language apps:

```typescript
// Check available languages
const languages = await SpeechTranscriber.getAvailableLanguages();

// Let user select language
const selectedLanguage = 'es-ES'; // Spanish

// Verify it's available
const isAvailable = await SpeechTranscriber.isLanguageAvailable(selectedLanguage);
if (isAvailable) {
  await SpeechTranscriber.setLanguage(selectedLanguage);
  await SpeechTranscriber.recordRealTimeAndTranscribe();
}
```

### Supported Languages

The plugin now supports any language available on the device, including but not limited to:

- **European Languages**: English, Spanish, French, German, Italian, Portuguese, Dutch, Polish, Russian, Turkish
- **Asian Languages**: Chinese (Simplified & Traditional), Japanese, Korean, Hindi, Vietnamese, Thai
- **Middle Eastern Languages**: Arabic, Hebrew, Persian
- **Nordic Languages**: Swedish, Norwegian, Danish, Finnish
- **Other**: And many more depending on device and OS version

Use `getAvailableLanguages()` to get the exact list for the current device.

### Technical Details

#### iOS

- Uses `SFSpeechRecognizer(locale: Locale)` for language-specific recognition
- For iOS 26+, uses `SpeechTranscriber(locale: Locale)` with SpeechAnalyzer
- Automatically handles model downloads for iOS 26+ if needed
- Validates locale support before transcription

#### Android

- Uses `RecognizerIntent.EXTRA_LANGUAGE` with locale string
- Parses various locale formats (BCP-47, underscore, region codes)
- Falls back to common languages list if device doesn't provide supported languages
- Handles locale normalization between different formats

### Notes

- Language support varies by device and OS version
- Some languages may require internet connection on Android (device-dependent)
- iOS may need to download language models for some languages (iOS 26+)
- RTL languages (Arabic, Hebrew) are fully supported
- Tonal languages (Chinese, Vietnamese) are fully supported

### Testing

This update has been tested with:
- Multiple languages (English, Spanish, French, German, Arabic, Chinese, Japanese)
- iOS 13+ devices
- Android 13+ (API 33+) devices
- Both real-time and file-based transcription
- Buffer-based transcription with different languages

---

## [0.1.1] - 2024-12-04

### Added
- Android support for real-time transcription
- Buffer-based transcription for both platforms

### Fixed
- Various bug fixes and stability improvements

## [0.1.0] - 2024-09-XX

### Added
- Initial release
- iOS on-device speech transcription
- Real-time transcription support
- File transcription with SFSpeechRecognizer
- SpeechAnalyzer support for iOS 26+
- Basic permission handling
