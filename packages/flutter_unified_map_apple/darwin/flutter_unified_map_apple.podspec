Pod::Spec.new do |s|
  s.name             = 'flutter_unified_map_apple'
  s.version          = '0.1.0'
  s.summary          = 'Apple MapKit implementation of flutter_unified_map.'
  s.description      = <<-DESC
iOS and macOS implementation of the flutter_unified_map Flutter plugin on MKMapView.
                       DESC
  s.homepage         = 'https://github.com/AlphaByte/flutter_unified_map'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'AlphaByte' => 'clovisgonon@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_unified_map_apple/Sources/flutter_unified_map_apple/**/*.swift'
  s.resource_bundles = {'flutter_unified_map_apple_privacy' => ['flutter_unified_map_apple/Sources/flutter_unified_map_apple/PrivacyInfo.xcprivacy']}
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'
end
