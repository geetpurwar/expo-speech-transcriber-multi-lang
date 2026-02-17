package expo.modules.speechtranscriber

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.util.Locale

class ExpoSpeechTranscriberModule : Module() {
  private var speechRecognizer: SpeechRecognizer? = null
  private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
  
  private var isRecording = false
  private var permissionPromise: Promise? = null
  private val PERMISSION_REQUEST_CODE = 1001
  private var currentLocale: Locale = Locale.getDefault() // Default to device language

  override fun definition() = ModuleDefinition {
    Name("ExpoSpeechTranscriber")
    Events("onTranscriptionProgress", "onTranscriptionError")

    AsyncFunction("recordRealTimeAndTranscribe") { promise: Promise ->
      mainHandler.post {
        startListening(promise)
      }
    }

    AsyncFunction("stopListening") {
      mainHandler.post {
        stopListening()
      }
    }

    Function("isRecording") {
      return@Function isRecording
    }

    AsyncFunction("requestMicrophonePermissions") { promise: Promise ->
      mainHandler.post {
        requestMicrophonePermissionsInternal(promise)
      }
    }
    
    AsyncFunction("setLanguage") { localeCode: String, promise: Promise ->
      mainHandler.post {
        setLanguage(localeCode, promise)
      }
    }
    
    AsyncFunction("getAvailableLanguages") { promise: Promise ->
      mainHandler.post {
        getAvailableLanguages(promise)
      }
    }
    
    AsyncFunction("getCurrentLanguage") { promise: Promise ->
      mainHandler.post {
        getCurrentLanguage(promise)
      }
    }
    
    AsyncFunction("isLanguageAvailable") { localeCode: String, promise: Promise ->
      mainHandler.post {
        isLanguageAvailable(localeCode, promise)
      }
    }
    
    // Stubs for buffer-based transcription (Not supported on Android's standard SpeechRecognizer)
    AsyncFunction("realtimeBufferTranscribe") { _: Any, _: Double, promise: Promise ->
        promise.reject("ERR_NOT_SUPPORTED", "Android SpeechRecognizer does not support external audio buffers. Use startActiveListening() to use the internal microphone.")
    }

    AsyncFunction("realtimeBufferTranscribeBase64") { _: String, _: Double, promise: Promise ->
        promise.reject("ERR_NOT_SUPPORTED", "Android SpeechRecognizer does not support external audio buffers. Use startActiveListening() to use the internal microphone.")
    }
    
    Function("stopBufferTranscription") { 
        // No-op on Android
    }

    OnDestroy {
      mainHandler.post {
        cleanup()
      }
    }
  }

  private fun startListening(promise: Promise) {
    val context = appContext.reactContext ?: run {
      sendEvent("onTranscriptionError", mapOf("message" to "Context is not available"))
      promise.resolve(false)
      return
    }

    if (!SpeechRecognizer.isRecognitionAvailable(context)) {
      val message = "Speech recognition is not available on this device."
      Log.e("ExpoSpeechTranscriber", message)
      sendEvent("onTranscriptionError", mapOf("message" to message))
      promise.resolve(false)
      return
    }

    if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
      sendEvent("onTranscriptionError", mapOf("message" to "Missing RECORD_AUDIO permission."))
      promise.resolve(false)
      return
    }

    speechRecognizer?.destroy()
    speechRecognizer = null

    speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context)
    
    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
      putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
      putExtra(RecognizerIntent.EXTRA_LANGUAGE, currentLocale.toString())
      putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
      putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
    }

    speechRecognizer?.setRecognitionListener(createRecognitionListener())
    speechRecognizer?.startListening(intent)
    isRecording = true
    promise.resolve(true)
  }

  private fun stopListening() {
    try {
      speechRecognizer?.stopListening()
      speechRecognizer?.destroy()
    } catch (e: Exception) {
      Log.e("ExpoSpeechTranscriber", "Error stopping recognizer: ${e.message}")
    } finally {
      speechRecognizer = null
      isRecording = false
    }
  }

  private fun cleanup() {
    stopListening()
  }

  private fun createRecognitionListener(): RecognitionListener {
    return object : RecognitionListener {
      override fun onReadyForSpeech(params: Bundle?) {
        Log.d("ExpoSpeechTranscriber", "Ready for speech")
      }

      override fun onBeginningOfSpeech() {
        Log.d("ExpoSpeechTranscriber", "Speech started")
      }

      override fun onRmsChanged(rmsdB: Float) {}
      override fun onBufferReceived(buffer: ByteArray?) {}

      override fun onEndOfSpeech() {
        Log.d("ExpoSpeechTranscriber", "Speech ended")
      }

      override fun onPartialResults(partialResults: Bundle?) {
        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (!matches.isNullOrEmpty()) {
          Log.d("ExpoSpeechTranscriber", "Text: ${matches[0]}")
          sendEvent("onTranscriptionProgress", mapOf(
            "text" to matches[0],
            "isFinal" to false
          ))
        }
      }

      override fun onResults(results: Bundle?) {
        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (!matches.isNullOrEmpty()) {
           Log.d("ExpoSpeechTranscriber", "Text: ${matches[0]}")
          sendEvent("onTranscriptionProgress", mapOf(
            "text" to matches[0],
            "isFinal" to true
          ))
        }
        stopListening()
      }

      override fun onError(error: Int) {
        val errorMessage = getErrorMessage(error)
        sendEvent("onTranscriptionError", mapOf("message" to errorMessage))
        stopListening()
      }

      override fun onEvent(eventType: Int, params: Bundle?) {}
    }
  }

  private fun getErrorMessage(errorCode: Int): String {
    return when (errorCode) {
      SpeechRecognizer.ERROR_AUDIO -> "Audio recording error"
      SpeechRecognizer.ERROR_CLIENT -> "Client side error"
      SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Insufficient permissions"
      SpeechRecognizer.ERROR_NETWORK -> "Network error"
      SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Network timeout"
      SpeechRecognizer.ERROR_NO_MATCH -> "No match found"
      SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Recognizer is busy"
      SpeechRecognizer.ERROR_SERVER -> "Error from server"
      SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech input"
      else -> "An unknown error occurred"
    }
  }

  private fun requestMicrophonePermissionsInternal(promise: Promise) {
    val context = appContext.reactContext ?: run {
      promise.resolve("denied")
      return
    }

    if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) 
        == PackageManager.PERMISSION_GRANTED) {
      promise.resolve("granted")
      return
    }

    val activity = appContext.currentActivity
    if (activity != null) {
      permissionPromise = promise
      ActivityCompat.requestPermissions(
        activity,
        arrayOf(Manifest.permission.RECORD_AUDIO),
        PERMISSION_REQUEST_CODE
      )
    } else {
      promise.resolve("denied")
    }
  }
  
  // Language Management Functions
  
  private fun setLanguage(localeCode: String, promise: Promise) {
    try {
      val localeParts = localeCode.replace("-", "_").split("_")
      val locale = when (localeParts.size) {
        1 -> Locale(localeParts[0])
        2 -> Locale(localeParts[0], localeParts[1])
        else -> Locale(localeParts[0], localeParts[1], localeParts[2])
      }
      
      currentLocale = locale
      promise.resolve(null)
    } catch (e: Exception) {
      Log.e("ExpoSpeechTranscriber", "Error setting language: ${e.message}")
      promise.reject("LANGUAGE_ERROR", "Failed to set language: ${e.message}")
    }
  }
  
  private fun getAvailableLanguages(promise: Promise) {
    val context = appContext.reactContext ?: run {
      promise.resolve(emptyList<String>())
      return
    }
    
    try {
      val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
      val availableLanguages = intent.getStringArrayListExtra(RecognizerIntent.EXTRA_SUPPORTED_LANGUAGES)
      
      if (availableLanguages != null) {
        promise.resolve(availableLanguages)
      } else {
        // Fallback: return common languages that are typically supported
        val commonLanguages = listOf(
          "en-US", "en-GB", "es-ES", "es-MX", "fr-FR", "de-DE", "it-IT", 
          "pt-BR", "pt-PT", "ru-RU", "zh-CN", "zh-TW", "ja-JP", "ko-KR",
          "ar-SA", "hi-IN", "nl-NL", "pl-PL", "tr-TR", "vi-VN"
        )
        promise.resolve(commonLanguages)
      }
    } catch (e: Exception) {
      Log.e("ExpoSpeechTranscriber", "Error getting available languages: ${e.message}")
      promise.resolve(emptyList<String>())
    }
  }
  
  private fun getCurrentLanguage(promise: Promise) {
    promise.resolve(currentLocale.toString().replace("_", "-"))
  }
  
  private fun isLanguageAvailable(localeCode: String, promise: Promise) {
    val context = appContext.reactContext ?: run {
      promise.resolve(false)
      return
    }
    
    try {
      val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
      val availableLanguages = intent.getStringArrayListExtra(RecognizerIntent.EXTRA_SUPPORTED_LANGUAGES)
      
      if (availableLanguages != null) {
        val normalized = localeCode.replace("_", "-")
        promise.resolve(availableLanguages.contains(normalized))
      } else {
        // If we can't get the list, assume it's available
        promise.resolve(true)
      }
    } catch (e: Exception) {
      Log.e("ExpoSpeechTranscriber", "Error checking language availability: ${e.message}")
      promise.resolve(false)
    }
  }
}
