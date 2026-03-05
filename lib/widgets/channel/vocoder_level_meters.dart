import 'dart:async';
import 'package:flutter/material.dart';
import 'package:grooveforge/services/audio_input_ffi.dart';

class VocoderLevelMeters extends StatefulWidget {
  const VocoderLevelMeters({super.key});

  @override
  State<VocoderLevelMeters> createState() => _VocoderLevelMetersState();
}

class _VocoderLevelMetersState extends State<VocoderLevelMeters> {
  Timer? _timer;
  double _inputLevel = 0.0;
  double _outputLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted) {
        setState(() {
          _inputLevel = AudioInputFFI().getInputPeakLevel();
          _outputLevel = AudioInputFFI().getOutputPeakLevel();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _buildMeter(String label, double level, Color color) {
    final clampedLevel = level.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white12),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: clampedLevel,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 2,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMeter('MIC', _inputLevel * 4.0, Colors.blue[400]!),
        _buildMeter('OUT', _outputLevel, Colors.green[400]!),
      ],
    );
  }
}
