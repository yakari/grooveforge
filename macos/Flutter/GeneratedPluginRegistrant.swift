//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import audio_session
import file_picker
import flutter_midi_command
import flutter_midi_pro
import package_info_plus
import shared_preferences_foundation
import universal_ble

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  AudioSessionPlugin.register(with: registry.registrar(forPlugin: "AudioSessionPlugin"))
  FilePickerPlugin.register(with: registry.registrar(forPlugin: "FilePickerPlugin"))
  SwiftFlutterMidiCommandPlugin.register(with: registry.registrar(forPlugin: "SwiftFlutterMidiCommandPlugin"))
  FlutterMidiProPlugin.register(with: registry.registrar(forPlugin: "FlutterMidiProPlugin"))
  FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
  SharedPreferencesPlugin.register(with: registry.registrar(forPlugin: "SharedPreferencesPlugin"))
  UniversalBlePlugin.register(with: registry.registrar(forPlugin: "UniversalBlePlugin"))
}
