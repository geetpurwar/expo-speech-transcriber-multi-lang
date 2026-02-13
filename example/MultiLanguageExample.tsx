import React, { useState, useEffect } from 'react';
import { View, Text, Button, StyleSheet, ScrollView, Platform, Alert } from 'react-native';
import * as SpeechTranscriber from 'expo-speech-transcriber';
import { Picker } from '@react-native-picker/picker';

export default function MultiLanguageExample() {
  const [availableLanguages, setAvailableLanguages] = useState<string[]>([]);
  const [selectedLanguage, setSelectedLanguage] = useState<string>('en-US');
  const [currentLanguage, setCurrentLanguage] = useState<string>('');
  const { text, isFinal, error, isRecording } = SpeechTranscriber.useRealTimeTranscription();

  useEffect(() => {
    loadAvailableLanguages();
    loadCurrentLanguage();
  }, []);

  const loadAvailableLanguages = async () => {
    try {
      const languages = await SpeechTranscriber.getAvailableLanguages();
      setAvailableLanguages(languages);
      console.log('Available languages:', languages);
    } catch (err) {
      console.error('Error loading languages:', err);
    }
  };

  const loadCurrentLanguage = async () => {
    try {
      const lang = await SpeechTranscriber.getCurrentLanguage();
      setCurrentLanguage(lang);
      setSelectedLanguage(lang);
    } catch (err) {
      console.error('Error loading current language:', err);
    }
  };

  const requestPermissions = async () => {
    try {
      if (Platform.OS === 'ios') {
        const speechPermission = await SpeechTranscriber.requestPermissions();
        if (speechPermission !== 'authorized') {
          Alert.alert('Permission Denied', 'Speech recognition permission is required');
          return false;
        }
      }

      const micPermission = await SpeechTranscriber.requestMicrophonePermissions();
      if (micPermission !== 'granted') {
        Alert.alert('Permission Denied', 'Microphone permission is required');
        return false;
      }

      return true;
    } catch (err) {
      console.error('Error requesting permissions:', err);
      return false;
    }
  };

  const handleLanguageChange = async (language: string) => {
    setSelectedLanguage(language);
    
    // Check if language is available
    const isAvailable = await SpeechTranscriber.isLanguageAvailable(language);
    if (!isAvailable) {
      Alert.alert('Language Not Available', `${language} is not supported on this device`);
      return;
    }

    try {
      await SpeechTranscriber.setLanguage(language);
      setCurrentLanguage(language);
      Alert.alert('Success', `Language set to ${language}`);
    } catch (err) {
      console.error('Error setting language:', err);
      Alert.alert('Error', 'Failed to set language');
    }
  };

  const startRecording = async () => {
    const hasPermissions = await requestPermissions();
    if (!hasPermissions) return;

    try {
      await SpeechTranscriber.recordRealTimeAndTranscribe();
    } catch (err) {
      console.error('Error starting recording:', err);
      Alert.alert('Error', 'Failed to start recording');
    }
  };

  const stopRecording = () => {
    SpeechTranscriber.stopListening();
  };

  const getLanguageName = (code: string): string => {
    const languageNames: { [key: string]: string } = {
      'en-US': 'English (US)',
      'en-GB': 'English (UK)',
      'es-ES': 'Spanish (Spain)',
      'es-MX': 'Spanish (Mexico)',
      'fr-FR': 'French',
      'de-DE': 'German',
      'it-IT': 'Italian',
      'pt-BR': 'Portuguese (Brazil)',
      'ru-RU': 'Russian',
      'zh-CN': 'Chinese (Simplified)',
      'zh-TW': 'Chinese (Traditional)',
      'ja-JP': 'Japanese',
      'ko-KR': 'Korean',
      'ar-SA': 'Arabic',
      'hi-IN': 'Hindi',
      'nl-NL': 'Dutch',
      'pl-PL': 'Polish',
      'tr-TR': 'Turkish',
      'vi-VN': 'Vietnamese',
    };
    return languageNames[code] || code;
  };

  return (
    <ScrollView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Multi-Language Transcription</Text>
        <Text style={styles.subtitle}>
          Current Language: {getLanguageName(currentLanguage)}
        </Text>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Select Language:</Text>
        <Picker
          selectedValue={selectedLanguage}
          onValueChange={handleLanguageChange}
          style={styles.picker}
        >
          {availableLanguages.map((lang) => (
            <Picker.Item 
              key={lang} 
              label={getLanguageName(lang)} 
              value={lang} 
            />
          ))}
        </Picker>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Recording Controls:</Text>
        <View style={styles.buttonContainer}>
          <Button
            title={isRecording ? 'Recording...' : 'Start Recording'}
            onPress={startRecording}
            disabled={isRecording}
            color="#007AFF"
          />
          <View style={styles.buttonSpacer} />
          <Button
            title="Stop Recording"
            onPress={stopRecording}
            disabled={!isRecording}
            color="#FF3B30"
          />
        </View>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Transcription:</Text>
        <View style={styles.transcriptionBox}>
          {text ? (
            <>
              <Text style={styles.transcriptionText}>{text}</Text>
              <Text style={styles.statusText}>
                {isFinal ? '✓ Final' : '⋯ Partial'}
              </Text>
            </>
          ) : (
            <Text style={styles.placeholderText}>
              Select a language and start recording...
            </Text>
          )}
        </View>
        {error && (
          <View style={styles.errorBox}>
            <Text style={styles.errorText}>Error: {error}</Text>
          </View>
        )}
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Available Languages:</Text>
        <ScrollView style={styles.languageList}>
          {availableLanguages.map((lang) => (
            <Text key={lang} style={styles.languageItem}>
              • {getLanguageName(lang)} ({lang})
            </Text>
          ))}
        </ScrollView>
      </View>

      <View style={styles.infoBox}>
        <Text style={styles.infoTitle}>💡 Tips:</Text>
        <Text style={styles.infoText}>
          • Language must be set before starting transcription
        </Text>
        <Text style={styles.infoText}>
          • Speak clearly in the selected language
        </Text>
        <Text style={styles.infoText}>
          • Different devices support different languages
        </Text>
        <Text style={styles.infoText}>
          • Some languages may require model downloads (iOS)
        </Text>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F5F5F5',
  },
  header: {
    backgroundColor: '#007AFF',
    padding: 20,
    paddingTop: 60,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: 'white',
    marginBottom: 5,
  },
  subtitle: {
    fontSize: 14,
    color: 'rgba(255, 255, 255, 0.9)',
  },
  section: {
    backgroundColor: 'white',
    padding: 15,
    marginTop: 10,
    marginHorizontal: 10,
    borderRadius: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 10,
    color: '#333',
  },
  picker: {
    backgroundColor: '#F8F8F8',
    borderRadius: 8,
  },
  buttonContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  buttonSpacer: {
    width: 10,
  },
  transcriptionBox: {
    backgroundColor: '#F8F8F8',
    padding: 15,
    borderRadius: 8,
    minHeight: 100,
  },
  transcriptionText: {
    fontSize: 16,
    color: '#333',
    lineHeight: 24,
  },
  statusText: {
    fontSize: 12,
    color: '#666',
    marginTop: 10,
    fontStyle: 'italic',
  },
  placeholderText: {
    fontSize: 14,
    color: '#999',
    fontStyle: 'italic',
  },
  errorBox: {
    backgroundColor: '#FFEBEE',
    padding: 10,
    borderRadius: 8,
    marginTop: 10,
  },
  errorText: {
    color: '#C62828',
    fontSize: 14,
  },
  languageList: {
    maxHeight: 150,
  },
  languageItem: {
    fontSize: 14,
    color: '#555',
    paddingVertical: 5,
  },
  infoBox: {
    backgroundColor: '#E3F2FD',
    padding: 15,
    margin: 10,
    borderRadius: 10,
    marginBottom: 30,
  },
  infoTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1976D2',
    marginBottom: 10,
  },
  infoText: {
    fontSize: 13,
    color: '#1565C0',
    marginBottom: 5,
    paddingLeft: 5,
  },
});
