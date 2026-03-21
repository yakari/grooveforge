Pod::Spec.new do |s|
  s.name             = 'dart_vst_host'
  s.version          = '0.1.0'
  s.summary          = 'Native VST3 host for GrooveForge (GFPA effects + plugin loading).'
  s.description      = <<-DESC
    Minimal VST3 host library compiled via CMake, wrapped by Dart FFI.
    Provides: VST3 plugin loading, GFPA built-in DSP effects, and macOS
    CoreAudio + Cocoa integration for plugin editor windows.
  DESC
  s.homepage         = 'https://github.com/grooveforge'
  s.license          = { :type => 'MIT' }
  s.author           = { 'GrooveForge' => 'dev@grooveforge.com' }
  s.source           = { :path => '.' }

  # Minimum macOS version matching the GrooveForge app target (see macos/Podfile).
  s.platform = :osx, '10.15'

  # ── Native library ───────────────────────────────────────────────────────────
  #
  # We ship a pre-built libdart_vst_host.dylib alongside this podspec.
  # CocoaPods will embed it in the app bundle's Frameworks directory and
  # codesign it automatically.
  #
  # To rebuild the library from source (e.g. after SDK changes), run:
  #   cmake -B build -S ../native -DCMAKE_BUILD_TYPE=Release \
  #         -DVST3_SDK_DIR=$(pwd)/../vst3sdk
  #   cmake --build build --target dart_vst_host
  #   cp build/libdart_vst_host.dylib libdart_vst_host.dylib
  s.vendored_libraries = 'libdart_vst_host.dylib'

  # Stub ObjC source so CocoaPods produces a valid module that Swift can import.
  # The actual functionality is in libdart_vst_host.dylib (loaded via Dart FFI).
  s.source_files = 'Classes/**/*'

  # Required macOS frameworks (same as CMakeLists.txt target_link_libraries).
  s.frameworks = 'Cocoa', 'CoreFoundation', 'AudioToolbox'
  s.weak_frameworks = 'Carbon'

  # Dependency on the Flutter engine so the pod integrates correctly.
  s.dependency 'FlutterMacOS'
end
