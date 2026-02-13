import React, { useState } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, Alert, ScrollView } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as SpeechTranscriber from 'expo-speech-transcriber';
import { AudioManager, AudioRecorder } from 'react-native-audio-api';

const BufferTranscriptionExample = () => {
  const { text, isFinal, error } = SpeechTranscriber.useRealTimeTranscription();
  const [isTranscribing, setIsTranscribing] = useState(false);
  const [permissionsGranted, setPermissionsGranted] = useState(false);
  const [recorder, setRecorder] = useState<AudioRecorder | null>(null);

  const initializeRecorder = () => {
    const audioRecorder = new AudioRecorder({
      sampleRate: 16000,
      bufferLengthInSamples: 1600,
    });

    AudioManager.setAudioSessionOptions({
      iosCategory: 'playAndRecord',
      iosMode: 'spokenAudio',
      iosOptions: ['allowBluetooth', 'defaultToSpeaker'],
    });

    audioRecorder.onAudioReady(({ buffer }) => {
      const channelData = buffer.getChannelData(0);
      
      SpeechTranscriber.realtimeBufferTranscribe(
        channelData,
        16000
      );
    });

    setRecorder(audioRecorder);
  };

  const requestAllPermissions = async () => {
    try {
      const speechPermission = await SpeechTranscriber.requestPermissions();
      const micPermission = await AudioManager.requestRecordingPermissions();
      
      if (speechPermission === 'authorized' && micPermission) {
        initializeRecorder();
        setPermissionsGranted(true);
        Alert.alert('Permissions Granted', 'All permissions are now available.');
      } else {
        Alert.alert('Permissions Required', 'Speech and microphone permissions are needed.');
      }
    } catch (err) {
      Alert.alert('Error', 'Failed to request permissions');
    }
  };

  const handleStartTranscribing = async () => {
    if (!permissionsGranted || !recorder) {
      await requestAllPermissions();
      return;
    }

    if (isTranscribing) {
      return;
    }

    setIsTranscribing(true);
    try {
      recorder.start();
    } catch (e) {
      console.error('Transcription failed', e);
      Alert.alert('Error', 'Failed to start transcription');
      setIsTranscribing(false);
    }
  };

  const handleStopTranscribing = () => {
    if (!isTranscribing || !recorder) {
      return;
    }

    recorder.stop();
    SpeechTranscriber.stopBufferTranscription();
    setIsTranscribing(false);
  };

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text style={styles.title}>Buffer Transcription Demo</Text>
      <Text style={styles.subtitle}>Using react-native-audio-api</Text>

      {!permissionsGranted && (
        <TouchableOpacity onPress={requestAllPermissions} style={[styles.button, styles.permissionButton]}>
          <Ionicons name="key" size={24} color="#FFF" />
          <Text style={styles.buttonText}>Request Permissions</Text>
        </TouchableOpacity>
      )}

      <Text style={styles.sectionTitle}>Buffer-Based Transcription</Text>
      
      <TouchableOpacity
        onPress={handleStartTranscribing}
        disabled={isTranscribing}
        style={[styles.button, styles.recordButton, isTranscribing && styles.disabled]}
      >
        <Ionicons name="mic" size={24} color="#FFF" />
        <Text style={styles.buttonText}>Start Buffer Transcription</Text>
      </TouchableOpacity>

      <TouchableOpacity
        onPress={handleStopTranscribing}
        disabled={!isTranscribing}
        style={[styles.button, styles.stopButton, !isTranscribing && styles.disabled]}
      >
        <Ionicons name="stop-circle" size={24} color="#FFF" />
        <Text style={styles.buttonText}>Stop Buffer Transcription</Text>
      </TouchableOpacity>

      {isTranscribing && (
        <View style={styles.recordingIndicator}>
          <Ionicons name="radio-button-on" size={20} color="#dc3545" />
          <Text style={styles.recordingText}>Transcribing from buffer...</Text>
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

      {!isTranscribing && !text && (
        <Text style={styles.hintText}>
          Request permissions, then start buffer transcription to stream audio data for real-time speech recognition.
        </Text>
      )}
    </ScrollView>
  );
};

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
    marginBottom: 4,
    color: '#333',
  },
  subtitle: {
    fontSize: 16,
    color: '#666',
    marginBottom: 20,
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
});

export default BufferTranscriptionExample;
