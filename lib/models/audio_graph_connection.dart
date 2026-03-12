import 'package:flutter/material.dart';
import 'audio_port_id.dart';

/// A directed edge in the audio graph, connecting one output port on a source
/// slot to a compatible input port on a destination slot.
///
/// Only **MIDI** and **Audio** connections are stored here.
/// **Data** connections (chord/scale routing for Jam Mode) are derived from
/// [RackState]'s `masterSlotId` / `targetSlotIds` fields and are not
/// persisted in [AudioGraphConnection].
///
/// The [id] is a canonical composite key built from the endpoint identifiers,
/// guaranteeing uniqueness without requiring a UUID library:
/// ```
/// "$fromSlotId:${fromPort.name}>$toSlotId:${toPort.name}"
/// ```
class AudioGraphConnection {
  /// Unique identifier for this connection (canonical composite key).
  final String id;

  /// The slot that originates the signal (output jack side).
  final String fromSlotId;

  /// The output port on [fromSlotId].
  final AudioPortId fromPort;

  /// The slot that receives the signal (input jack side).
  final String toSlotId;

  /// The input port on [toSlotId].
  final AudioPortId toPort;

  /// Optional user-chosen cable colour override.
  /// When null the default colour for the port family is used.
  final Color? cableColorOverride;

  const AudioGraphConnection._({
    required this.id,
    required this.fromSlotId,
    required this.fromPort,
    required this.toSlotId,
    required this.toPort,
    this.cableColorOverride,
  });

  /// Creates a connection and derives its canonical [id] automatically.
  ///
  /// Throws [ArgumentError] if:
  ///   - [fromPort] is not an output port
  ///   - [toPort] is not an input port
  ///   - the ports are not type-compatible (see [AudioPortIdX.compatibleWith])
  ///   - either port is a data-family port (those are managed by [RackState])
  factory AudioGraphConnection.create({
    required String fromSlotId,
    required AudioPortId fromPort,
    required String toSlotId,
    required AudioPortId toPort,
    Color? cableColorOverride,
  }) {
    if (!fromPort.isOutput) {
      throw ArgumentError('fromPort must be an output port, got $fromPort');
    }
    if (!toPort.isInput) {
      throw ArgumentError('toPort must be an input port, got $toPort');
    }
    if (!fromPort.compatibleWith(toPort)) {
      throw ArgumentError(
        'Incompatible port types: $fromPort → $toPort',
      );
    }
    if (fromPort.isDataPort || toPort.isDataPort) {
      throw ArgumentError(
        'Data-family ports are managed by RackState, not AudioGraph. '
        'Use RackState.setJamModeMaster / addJamModeTarget instead.',
      );
    }
    return AudioGraphConnection._(
      id: '$fromSlotId:${fromPort.name}>$toSlotId:${toPort.name}',
      fromSlotId: fromSlotId,
      fromPort: fromPort,
      toSlotId: toSlotId,
      toPort: toPort,
      cableColorOverride: cableColorOverride,
    );
  }

  // ── JSON persistence ────────────────────────────────────────────────────

  /// Deserialises a connection from its JSON representation in a .gf file.
  factory AudioGraphConnection.fromJson(Map<String, dynamic> json) {
    final fromSlotId = json['fromSlotId'] as String;
    final fromPort = AudioPortId.values.byName(json['fromPort'] as String);
    final toSlotId = json['toSlotId'] as String;
    final toPort = AudioPortId.values.byName(json['toPort'] as String);

    // Reconstruct the colour override if present.
    final colorValue = json['cableColor'] as int?;
    final color = colorValue != null ? Color(colorValue) : null;

    return AudioGraphConnection._(
      id: '$fromSlotId:${fromPort.name}>$toSlotId:${toPort.name}',
      fromSlotId: fromSlotId,
      fromPort: fromPort,
      toSlotId: toSlotId,
      toPort: toPort,
      cableColorOverride: color,
    );
  }

  /// Serialises this connection to a JSON-compatible map for .gf project files.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'fromSlotId': fromSlotId,
      'fromPort': fromPort.name,
      'toSlotId': toSlotId,
      'toPort': toPort.name,
    };
    if (cableColorOverride != null) {
      map['cableColor'] = cableColorOverride!.toARGB32();
    }
    return map;
  }

  /// Returns a copy with an updated [cableColorOverride].
  AudioGraphConnection withColor(Color? color) => AudioGraphConnection._(
        id: id,
        fromSlotId: fromSlotId,
        fromPort: fromPort,
        toSlotId: toSlotId,
        toPort: toPort,
        cableColorOverride: color,
      );

  @override
  bool operator ==(Object other) =>
      other is AudioGraphConnection && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'AudioGraphConnection($fromSlotId:$fromPort → $toSlotId:$toPort)';
}
