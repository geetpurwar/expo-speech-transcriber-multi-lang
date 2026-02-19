require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

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

  # No custom SWIFT_ACTIVE_COMPILATION_CONDITIONS needed.
  # iOS 26 API code is gated by #if swift(>=6.2) directly in Swift source,
  # which is evaluated by the compiler itself and immune to any xcconfig
  # override from Expo, React Native, or EAS build infrastructure.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES'
  }

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
