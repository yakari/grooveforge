/// A single MIDI event timestamped in PPQ (pulses per quarter-note).
///
/// Used by [GFMidiFxPlugin] to process event streams in a block-processing
/// model. Positions are relative to the start of the current audio block.
class TimestampedMidiEvent {
  final double ppqPosition;
  final int status; // raw MIDI status byte (includes channel in low nibble)
  final int data1;
  final int data2;

  const TimestampedMidiEvent({
    required this.ppqPosition,
    required this.status,
    required this.data1,
    required this.data2,
  });

  bool get isNoteOn => (status & 0xF0) == 0x90 && data2 > 0;
  bool get isNoteOff =>
      (status & 0xF0) == 0x80 ||
      ((status & 0xF0) == 0x90 && data2 == 0);
  int get midiChannel => status & 0x0F;

  Map<String, dynamic> toJson() => {
    'ppq': ppqPosition,
    'status': status,
    'data1': data1,
    'data2': data2,
  };

  factory TimestampedMidiEvent.fromJson(Map<String, dynamic> json) =>
      TimestampedMidiEvent(
        ppqPosition: (json['ppq'] as num).toDouble(),
        status: json['status'] as int,
        data1: json['data1'] as int,
        data2: json['data2'] as int,
      );
}
