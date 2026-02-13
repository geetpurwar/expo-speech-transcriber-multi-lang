import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ScrollView, Platform, Alert } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as SpeechTranscriber from 'expo-speech-transcriber';

/**
 * RecordRealTimeAndTranscribe Example
 * 
 * Demonstrates real-time speech transcription using expo-speech-transcriber.
 * This example follows the API documented in README.md.
 * 
 * Requirements:
 * - Android 13+ (API 33) for Android
 * - iOS 13+ for iOS
 * - Microphone and speech recognition permissions
 */
export default function RecordRealTimeAndTranscribe() {
  const [permissionStatus, setPermissionStatus] = useState({
    speech: 'notDetermined',
    microphone: 'denied',
  });

  // Use the built-in hook for real-time transcription
  const { text, isFinal, error, isRecording } = SpeechTranscriber.useRealTimeTranscription();

    /**
   * Request all necessary permissions
   */
  const requestAllPermissions = async () => {
    try {
      console.log('🔐 Requesting permissions...');
      
      let speechPermission = 'notDetermined';
      
      // Request speech recognition permission only on iOS
      if (Platform.OS === 'ios') {
        speechPermission = await SpeechTranscriber.requestPermissions();
        console.log('Speech permission:', speechPermission);
      }
      
      // Request microphone permission
      const micPermission = await SpeechTranscriber.requestMicrophonePermissions();
      console.log('Microphone permission:', micPermission);
      
      // Both `requestPermissions` and `requestMicrophonePermissions` return
      // string union types (e.g. 'authorized' | 'denied'), not objects with
      // `.status` or `.granted` properties. Store them directly and check
      // their values accordingly.
      setPermissionStatus({
        speech: speechPermission,
        microphone: micPermission,
      });

      if (Platform.OS === 'ios' && speechPermission !== 'authorized') {
        Alert.alert('Permission Denied', 'Speech recognition permission is required.');
      } else if (micPermission !== 'granted') {
        Alert.alert('Permission Denied', 'Microphone permission is required.');
      }
    } catch (err) {
      console.error('❌ Permission error:', err);
      Alert.alert('Error', `Failed to request permissions: ${err}`);
    }
  };

  /**
   * Start real-time transcription
   */
  const startTranscription = async () => {
    try {
      console.log('🎤 Starting transcription...');
      await SpeechTranscriber.recordRealTimeAndTranscribe();
      console.log('✅ Transcription started');
    } catch (err) {
      console.error('❌ Start error:', err);
      Alert.alert('Error', `Failed to start transcription: ${err}`);
    }
  };

  /**
   * Stop real-time transcription
   */
  const stopTranscription = () => {
    try {
      console.log('⏹️ Stopping transcription...');
      SpeechTranscriber.stopListening();
      console.log('✅ Transcription stopped');
    } catch (err) {
      console.error('❌ Stop error:', err);
      Alert.alert('Error', `Failed to stop transcription: ${err}`);
    }
  };

  // Check permissions on mount
  useEffect(() => {
    requestAllPermissions();
  }, []);

  const hasPermissions = Platform.OS === 'ios' 
    ? permissionStatus.speech === 'authorized' && permissionStatus.microphone === 'granted'
    : permissionStatus.microphone === 'granted';

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text style={styles.title}>Real-Time Transcription</Text>
      <Text style={styles.subtitle}>Platform: {Platform.OS}</Text>

      {!hasPermissions && (
        <TouchableOpacity onPress={requestAllPermissions} style={[styles.button, styles.permissionButton]}>
          <Ionicons name="key" size={24} color="#FFF" />
          <Text style={styles.buttonText}>Request Permissions</Text>
        </TouchableOpacity>
      )}

      <Text style={styles.sectionTitle}>Recording Controls</Text>
      
      <TouchableOpacity
        onPress={startTranscription}
        disabled={isRecording || !hasPermissions}
        style={[styles.button, styles.recordButton, (isRecording || !hasPermissions) && styles.disabled]}
      >
        <Ionicons name="mic" size={24} color="#FFF" />
        <Text style={styles.buttonText}>Start Transcription</Text>
      </TouchableOpacity>

      <TouchableOpacity
        onPress={stopTranscription}
        disabled={!isRecording}
        style={[styles.button, styles.stopButton, !isRecording && styles.disabled]}
      >
        <Ionicons name="stop-circle" size={24} color="#FFF" />
        <Text style={styles.buttonText}>Stop Transcription</Text>
      </TouchableOpacity>

      {isRecording && (
        <View style={styles.recordingIndicator}>
          <Ionicons name="radio-button-on" size={20} color="#dc3545" />
          <Text style={styles.recordingText}>Recording and Transcribing...</Text>
        </View>
      )}

      {error && (
        <View style={styles.errorContainer}>
          <Text style={styles.errorText}>Error: {error}</Text>
        </View>
      )}

      {text && (
        <View style={styles.transcriptionContainer}>
          <Text style={styles.transcriptionTitle}>Transcription:</Text>
          <Text style={styles.transcriptionText}>{text}</Text>
          {isFinal && <Text style={styles.finalText}>Final!</Text>}
        </View>
      )}

      {!isRecording && !text && hasPermissions && (
        <Text style={styles.hintText}>
          Press "Start Transcription" to begin real-time speech recognition.
        </Text>
      )}

      <View style={styles.instructionsContainer}>
        <Text style={styles.instructionsTitle}>How to use:</Text>
        <Text style={styles.instructionText}>1. Grant permissions when prompted</Text>
        <Text style={styles.instructionText}>2. Press "Start Transcription" to begin</Text>
        <Text style={styles.instructionText}>3. Speak clearly into your device</Text>
        <Text style={styles.instructionText}>4. Watch the transcription appear in real-time</Text>
        <Text style={styles.instructionText}>5. Press "Stop Transcription" when finished</Text>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flexGrow: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
    backgroundColor: '#f5f5f5',
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    marginBottom: 8,
    color: '#333',
  },
  subtitle: {
    fontSize: 14,
    color: '#999',
    marginBottom: 10,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    marginTop: 20,
    marginBottom: 10,
    color: '#333',
  },
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 15,
    paddingHorizontal: 30,
    borderRadius: 12,
    marginVertical: 8,
    minWidth: 280,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  permissionButton: {
    backgroundColor: '#6c757d',
  },
  recordButton: {
    backgroundColor: '#007bff',
  },
  stopButton: {
    backgroundColor: '#dc3545',
  },
  disabled: {
    backgroundColor: '#ccc',
    opacity: 0.6,
  },
  buttonText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
    marginLeft: 10,
  },
  recordingIndicator: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 20,
    padding: 15,
    backgroundColor: '#fff',
    borderRadius: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  recordingText: {
    fontSize: 16,
    color: '#dc3545',
    marginLeft: 10,
    fontWeight: '600',
  },
  errorContainer: {
    marginTop: 20,
    padding: 15,
    backgroundColor: '#f8d7da',
    borderRadius: 12,
    width: '100%',
    maxWidth: 400,
  },
  errorText: {
    fontSize: 16,
    color: '#721c24',
  },
  transcriptionContainer: {
    marginTop: 30,
    padding: 20,
    backgroundColor: '#fff',
    borderRadius: 12,
    width: '100%',
    maxWidth: 400,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 5,
  },
  transcriptionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 12,
    color: '#333',
  },
  transcriptionText: {
    fontSize: 16,
    color: '#555',
    lineHeight: 24,
  },
  finalText: {
    fontSize: 14,
    color: '#28a745',
    fontWeight: 'bold',
    marginTop: 10,
  },
  hintText: {
    fontSize: 14,
    color: '#999',
    marginTop: 20,
    textAlign: 'center',
  },
  instructionsContainer: {
    marginTop: 30,
    padding: 20,
    backgroundColor: '#e7f3ff',
    borderRadius: 12,
    width: '100%',
    maxWidth: 400,
  },
  instructionsTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 12,
    color: '#333',
  },
  instructionText: {
    fontSize: 14,
    color: '#555',
    marginBottom: 6,
    lineHeight: 20,
  },
});