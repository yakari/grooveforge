import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the overdub round trip measures, per way of listening.
///
/// Device-wide, deliberately. Latency belongs to the gear: the same headset
/// has the same delay whichever tune is open, and measuring it once should
/// answer for all of them. Keeping the table inside a rehearsal meant
/// calibrating in one tune and being told the headset was unknown in the next.
///
/// Keyed as [AudioRoute.key] — `speaker`, `wired`, or a named Bluetooth
/// headset, because somebody may own several and each is its own delay.
class LatencyCalibration extends ChangeNotifier {
  /// The table, as JSON, in shared preferences.
  static const String tableKey = 'gf.rehearsal.compensationByRoute';

  /// The single figure this replaced, still written so an older build — and
  /// the rehearsal engine's own fallback — keeps working.
  static const String legacyKey = 'gf.rehearsal.compensationFrames';

  final Map<String, int> _byRoute = {};

  /// Last measurement taken on this device, whatever it was measured on.
  int _fallback = 0;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Reads what has been measured so far. Safe to call more than once.
  Future<void> load() async {
    if (_loaded) return;
    await _read();
  }

  /// Reads again, after somebody else has written.
  ///
  /// The probe runs on its own screen and saves there, so the engine has to be
  /// told to look again rather than trust what it read when the tune opened.
  Future<void> reload() async {
    _byRoute.clear();
    await _read();
  }

  Future<void> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _fallback = prefs.getInt(legacyKey) ?? 0;
      final raw = prefs.getString(tableKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _byRoute.addAll(decoded.map((k, v) => MapEntry(k, (v as num).toInt())));
      }
    } catch (e) {
      // Preferences being unavailable must not stop anyone recording; without
      // a measurement the take is late, which is worse than nothing but a lot
      // better than a rehearsal that will not open.
      debugPrint('LatencyCalibration: could not read — $e');
    }
    _loaded = true;
    notifyListeners();
  }


  /// Compensation to apply on [routeKey], in frames.
  ///
  /// Falls back to the last measurement rather than to zero: a wrong-but-close
  /// figure from another route beats no compensation at all, which is a take a
  /// whole round trip behind the beat.
  int forRoute(String? routeKey) {
    if (routeKey == null) return _fallback;
    return _byRoute[routeKey] ?? _fallback;
  }

  /// Whether [routeKey] has ever been measured.
  ///
  /// Deliberately not the same question as [forRoute] returning something:
  /// falling back is not knowing, and the difference is what the warning on
  /// the tune screen reads.
  bool hasRoute(String? routeKey) =>
      routeKey != null && _byRoute.containsKey(routeKey);

  /// Files a fresh measurement against the route it was taken on.
  Future<void> record(String? routeKey, int frames) async {
    if (frames <= 0) return;
    _fallback = frames;
    if (routeKey != null) _byRoute[routeKey] = frames;
    notifyListeners();
    await _save();
  }

  /// Takes in measurements a rehearsal recorded before the table was
  /// device-wide.
  ///
  /// Anything already known here wins: the device table is the newer, better
  /// source, and a stale per-tune figure should not overwrite it.
  Future<void> adoptFromRehearsal(Map<String, int> perRoute, int single) async {
    var changed = false;
    for (final entry in perRoute.entries) {
      if (_byRoute.containsKey(entry.key)) continue;
      _byRoute[entry.key] = entry.value;
      changed = true;
    }
    if (_fallback == 0 && single > 0) {
      _fallback = single;
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(tableKey, jsonEncode(_byRoute));
      if (_fallback > 0) await prefs.setInt(legacyKey, _fallback);
    } catch (e) {
      debugPrint('LatencyCalibration: could not save — $e');
    }
  }

  /// What has been measured, for tests and for a settings screen to list.
  Map<String, int> get byRoute => Map.unmodifiable(_byRoute);
}
