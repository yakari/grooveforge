import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A wrapper service around [FlutterMidiCommand] to manage hardware connections.
class MidiService {
  final MidiCommand _midiCommand = MidiCommand();
  StreamSubscription<MidiPacket>? _rxSubscription;
  StreamSubscription<String>? _setupSubscription;

  Function(MidiPacket)? onMidiDataReceived;

  final Set<String> _knownDeviceIds = {};
  final Set<String> _blacklistedDeviceNames = {}; // Session-local blacklist
  final StreamController<MidiDevice> _newDeviceController =
      StreamController<MidiDevice>.broadcast();

  Stream<MidiDevice> get onNewDeviceDetected => _newDeviceController.stream;

  Timer? _pollingTimer;

  /// Guards against concurrent [connect] calls
  bool _isConnecting = false;

  /// Backoff to avoid rapid reconnection loops for problematic hardware
  DateTime? _lastConnectAttemptTime;
  String? _lastConnectAttemptDevice;

  MidiService() {
    debugPrint('MidiService: Initializing...');

    // On Linux, the native stream listener can sometimes cause conflicts with the ALSA driver during connection.
    // We prefer the polling strategy for stability on Linux/Windows/macOS.
    final setupStream = _midiCommand.onMidiSetupChanged;
    if (!kIsWeb && setupStream != null && !Platform.isLinux) {
      debugPrint('MidiService: Subscribing to onMidiSetupChanged');
      _setupSubscription = setupStream.listen((event) {
        debugPrint('MidiService: onMidiSetupChanged event: $event');
        _handleSetupChanged();
      });
    }

    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      debugPrint('MidiService: Starting 2s polling timer for ${Platform.operatingSystem}');
      _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _handleSetupChanged();
      });
    }

    _midiCommand.onMidiDataReceived?.listen((packet) {
      if (onMidiDataReceived != null) {
        onMidiDataReceived!(packet);
      }
    });
    
    _tryAutoConnect();
  }

  void _setHangFlagSync(bool value) {
    if (kIsWeb) return;  // No filesystem on web; hang-detection is native-only.
    try {
      final path = '/tmp/grooveforge_midi_hang.flag';
      final file = File(path);
      if (value) {
        file.writeAsStringSync('hanging', flush: true);
      } else {
        if (file.existsSync()) file.deleteSync();
      }
    } catch (e) {
      debugPrint('MidiService: Failed to set hang flag: $e');
    }
  }

  bool _isHangFlagSetSync() {
    if (kIsWeb) return false;  // No filesystem on web.
    try {
      return File('/tmp/grooveforge_midi_hang.flag').existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleSetupChanged() async {
    if (kIsWeb) return;  // No MIDI device scanning on web.
    if (_isConnecting) {
      debugPrint('MidiService: Scan ignored, connection already in progress.');
      return;
    }

    // Debounce: don't scan too often
    final now = DateTime.now();
    if (_lastConnectAttemptTime != null && 
        now.difference(_lastConnectAttemptTime!) < const Duration(seconds: 2)) {
      debugPrint('MidiService: Scan debounced.');
      return;
    }

    debugPrint('MidiService: Checking for device changes...');
    final devs = await _midiCommand.devices;
    if (devs == null) return;

    final currentDeviceIds = devs.map((e) => e.id).toSet();
    
    // Remove disconnected devices from known list
    _knownDeviceIds.removeWhere((id) {
      bool removed = !currentDeviceIds.contains(id);
      if (removed) debugPrint('MidiService: Removed $id from known devices');
      return removed;
    });

    final prefs = await SharedPreferences.getInstance();
    final lastDeviceName = prefs.getString('last_midi_device_name');

    for (var device in devs) {
      final isLastDevice = (lastDeviceName != null && device.name == lastDeviceName);
      
      if (!_knownDeviceIds.contains(device.id)) {
        debugPrint('MidiService: New device found: ${device.id} (${device.name})');
        _knownDeviceIds.add(device.id);

        if (isLastDevice && !_blacklistedDeviceNames.contains(device.name)) {
          // Additional safety: don't auto-reconnect if we just tried recently
          if (_lastConnectAttemptDevice == device.name && 
              now.difference(_lastConnectAttemptTime!) < const Duration(seconds: 15)) {
            debugPrint('MidiService: Skipping rapid auto-reconnect for ${device.name} (backoff)');
            continue;
          }

          if (device.connected) {
            debugPrint('MidiService: Device ${device.name} already connected, skipping auto-reconnect.');
            continue;
          }

          try {
            debugPrint('MidiService: Attempting auto-reconnect to ${device.name}...');
            await connect(device);
          } catch (e) {
            debugPrint('MidiService: Failed to auto-reconnect to ${device.name}: $e');
          }
        } else if (!device.connected) {
          debugPrint('MidiService: Prompting for new device: ${device.name}');
          _newDeviceController.add(device);
        }
      }
    }
  }

  Future<void> _tryAutoConnect() async {
    if (kIsWeb) return;  // No MIDI hardware on web.
    debugPrint('MidiService: INITIAL _tryAutoConnect');
    final prefs = await SharedPreferences.getInstance();
    final lastDeviceName = prefs.getString('last_midi_device_name');
    
    if (lastDeviceName == null) {
      debugPrint('MidiService: No last device saved.');
      return;
    }

    // Check if the last session likely hung during a MIDI connection attempt
    if (_isHangFlagSetSync()) {
      debugPrint('MidiService: WARNING: Last session appears to have hung! Blacklisting $lastDeviceName.');
      _blacklistedDeviceNames.add(lastDeviceName);
      _setHangFlagSync(false);
      return;
    }

    if (_isConnecting) return;

    final devs = await _midiCommand.devices;
    if (devs == null || devs.isEmpty) return;

    for (var device in devs) {
      _knownDeviceIds.add(device.id);
      if (device.name == lastDeviceName && !_blacklistedDeviceNames.contains(device.name)) {
        try {
          // Tight timeout for boot attempt
          await connect(device).timeout(const Duration(seconds: 4));
        } catch (e) {
          debugPrint('MidiService: Initial auto-connect failed or timed out: $e');
        }
        break;
      }
    }
  }

  Stream<List<MidiDevice>>? get devicesStream =>
      _midiCommand.onMidiSetupChanged?.map((_) => []);

  Future<List<MidiDevice>> get devices async {
    if (kIsWeb) return [];  // flutter_midi_command has no web implementation.
    final devs = await _midiCommand.devices;
    return devs ?? [];
  }

  Future<void> connect(MidiDevice device) async {
    if (_isConnecting) {
      debugPrint('MidiService: connect IGNORED, another connection in progress');
      return;
    }

    _isConnecting = true;
    _lastConnectAttemptTime = DateTime.now();
    _lastConnectAttemptDevice = device.name;

    try {
      _setHangFlagSync(true);
      debugPrint('MidiService: connect START for ${device.name}');
      // If it truly blocks the thread, the timer won't fire. 
      // But we wrap it in a secondary guard to prevent recursion if Alsa fires events.
      await _midiCommand.connectToDevice(device).timeout(const Duration(seconds: 8));
      debugPrint('MidiService: connect SUCCESS for ${device.name}');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_midi_device_id', device.id);
      await prefs.setString('last_midi_device_name', device.name);
      
      _setHangFlagSync(false);
    } catch (e) {
      debugPrint('MidiService: connect ERROR for ${device.name}: $e');
      _setHangFlagSync(false);
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  void disconnect(MidiDevice device) async {
    _midiCommand.disconnectDevice(device);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_midi_device_id');
    await prefs.remove('last_midi_device_name');
  }

  void dispose() {
    _pollingTimer?.cancel();
    _rxSubscription?.cancel();
    _setupSubscription?.cancel();
    _newDeviceController.close();
    _midiCommand.teardown();
  }
}
