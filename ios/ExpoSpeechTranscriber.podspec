require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

# Detect whether we're building with Xcode 26+ (which ships the iOS 26 SDK
# that includes SpeechAnalyzer, SpeechTranscriber, AnalyzerInput, AssetInventory).
# On older Xcode versions these types don't exist in the SDK at all, so we gate
# compilation of all iOS 26 code behind the SPEECH_ANALYZER_AVAILABLE flag.
xcode_version = `xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}'`.strip.to_f
speech_analyzer_available = xcode_version >= 26.0

Pod::Spec.new do |s|
  s.name           = 'ExpoSpeechTranscriber'
  s.version        = package['version']
  s.summary        = package['description']
  s.description    = package['description']
  s.license        = package['license']
  s.author         = package['author']
  s.homepage       = package['homepage']
  s.platforms      = {
    :ios => '15.1',
    :tvos => '15.1'
  }
  s.swift_version  = '5.9'
  s.source         = { git: 'https://github.com/DaveyEke/expo-speech-transcriber' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  # Build active compilation conditions.
  # SPEECH_ANALYZER_AVAILABLE is set only when Xcode 26+ (iOS 26 SDK) is present,
  # ensuring all SpeechAnalyzer/SpeechTranscriber/AnalyzerInput/AssetInventory
  # references are excluded from compilation on older toolchains.
  #
  # IMPORTANT: We always prepend $(inherited) so we never clobber compilation
  # conditions set by ExpoModulesCore or Expo's own build system.
  extra_flag = speech_analyzer_available ? ' SPEECH_ANALYZER_AVAILABLE' : ''

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => "$(inherited)#{extra_flag}"
  }

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
