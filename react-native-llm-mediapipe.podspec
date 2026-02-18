require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))
folly_compiler_flags = '-DFOLLY_NO_CONFIG -DFOLLY_MOBILE=1 -DFOLLY_USE_LIBCPP=1 -Wno-comma -Wno-shorten-64-to-32'

Pod::Spec.new do |s|
  s.name         = "react-native-llm-mediapipe"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/Shake-Escrow/react-native-llm-mediapipe.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift}"

  # Swift language version
  s.swift_version = '5.9'

  # Disable explicit Swift module compilation for this pod only.
  # Xcode 16+ fails with "Unable to find module dependency: '_DarwinFoundation3'"
  # when SPM packages (MLX) are included alongside static CocoaPods and the explicit
  # module scanner encounters the internal Foundation cross-import overlay.
  # Scoping this to pod_target_xcconfig avoids interfering with the app target's
  # module resolution (which Expo requires to be enabled for `import Expo` to work).
  s.pod_target_xcconfig = {
    'SWIFT_ENABLE_EXPLICIT_MODULES' => 'NO'
  }

  # MLX Swift dependencies via Swift Package Manager.
  # spm_dependency is available since React Native 0.75 (react_native_pods.rb).
  spm_dependency(s,
    url: 'https://github.com/ml-explore/mlx-swift',
    requirement: { kind: 'upToNextMajorVersion', minimumVersion: '0.21.0' },
    products: ['MLX', 'MLXRandom']
  )

  spm_dependency(s,
    url: 'https://github.com/ml-explore/mlx-swift-examples',
    requirement: { kind: 'upToNextMajorVersion', minimumVersion: '2.21.0' },
    products: ['MLXLM']
  )

  # Note: Android uses MediaPipe (configured in build.gradle)

  # Use install_modules_dependencies helper to install the dependencies if React Native version >=0.71.0.
  # See https://github.com/facebook/react-native/blob/febf6b7f33fdb4904669f99d795eba4c0f95d7bf/scripts/cocoapods/new_architecture.rb#L79.
  if respond_to?(:install_modules_dependencies, true)
    install_modules_dependencies(s)
  else
    s.dependency "React-Core"

    # Don't install the dependencies when we run `pod install` in the old architecture.
    if ENV['RCT_NEW_ARCH_ENABLED'] == '1' then
      s.compiler_flags = folly_compiler_flags + " -DRCT_NEW_ARCH_ENABLED=1"
      s.pod_target_xcconfig = {
        "HEADER_SEARCH_PATHS" => "\"$(PODS_ROOT)/boost\"",
        "OTHER_CPLUSPLUSFLAGS" => "-DFOLLY_NO_CONFIG -DFOLLY_MOBILE=1 -DFOLLY_USE_LIBCPP=1",
        "CLANG_CXX_LANGUAGE_STANDARD" => "c++17"
      }
      s.dependency "React-Codegen"
      s.dependency "RCT-Folly"
      s.dependency "RCTRequired"
      s.dependency "RCTTypeSafety"
      s.dependency "ReactCommon/turbomodule/core"
    end
  end
end
