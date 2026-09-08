import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_localizations.dart';
import '../services/rehearsal_protocol.dart';

/// Reads a rehearsal's QR code with the camera.
///
/// Pops with the scanned [JoinTicket], or null if the user backed out.
///
/// Decoding is `flutter_zxing` — ZXing-C++ over FFI, MIT licensed. Deliberately
/// not `mobile_scanner`, which decodes with Google ML Kit: a proprietary blob
/// that would fail F-Droid's inclusion policy (decision D5).
///
/// Only reachable on Android and iOS. `flutter_zxing`'s reader is built on the
/// official `camera` plugin, which supports nothing else, and plenty of laptops
/// have no camera anyway — desktop pastes the link instead (D11).
class ScanTicketScreen extends StatefulWidget {
  const ScanTicketScreen({super.key});

  @override
  State<ScanTicketScreen> createState() => _ScanTicketScreenState();
}

class _ScanTicketScreenState extends State<ScanTicketScreen> {
  /// Set once a ticket has been read, so the camera's continuous stream cannot
  /// pop the route a second time while the first pop is still in flight.
  bool _handled = false;

  /// Null while the permission request is in flight.
  bool? _granted;

  @override
  void initState() {
    super.initState();
    _requestCamera();
  }

  Future<void> _requestCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() => _granted = status.isGranted);
  }

  void _onScan(Code code) {
    if (_handled) return;
    final text = code.text;
    debugPrint('ScanTicket: decoded ${code.format} '
        'valid=${code.isValid} len=${text?.length}');
    if (text == null) return;

    // The camera sees every code in front of it, including whatever else is on
    // the table. Anything that is not one of ours is ignored rather than
    // reported, so the scanner simply keeps looking.
    final ticket = JoinTicket.parse(text.trim());
    if (ticket == null) {
      debugPrint('ScanTicket: not one of ours — ${text.substring(0,
          text.length < 40 ? text.length : 40)}');
      return;
    }

    _handled = true;
    Navigator.of(context).pop(ticket);
  }

  /// Logged, not shown. A failure here means "no code in this frame", which
  /// happens many times a second and is not something to tell the user about.
  void _onScanFailure(Code code) {
    if (code.error?.isNotEmpty ?? false) {
      debugPrint('ScanTicket: decode error ${code.error}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.nearbyScanTitle)),
      body: switch (_granted) {
        null => const Center(child: CircularProgressIndicator()),
        false => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                l10n.nearbyScanPermission,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        true => Column(
            children: [
              Expanded(
                child: ReaderWidget(
                  onScan: _onScan,
                  onScanFailure: _onScanFailure,
                  // Only QR codes: narrowing the formats keeps the decoder from
                  // spending its time on barcode types that could never carry a
                  // ticket.
                  codeFormat: Format.qrCode,
                  // A rehearsal room is not a clean lab — the code may be on a
                  // dim screen, at an angle, behind a fingerprint.
                  tryHarder: true,
                  tryRotate: true,
                  tryInverted: true,
                  // The default crops to the middle 50% of the frame, so a code
                  // has to be both centred and large to be seen at all. A join
                  // ticket is a dense code on someone else's screen, held at
                  // arm's length; searching almost the whole frame is what
                  // makes that work.
                  cropPercent: 0.9,
                  // 720p leaves a dense code's modules only a pixel or two
                  // wide at a comfortable distance.
                  resolution: ResolutionPreset.veryHigh,
                  tryDownscale: true,
                  // A quarter of a second, not a second: pointing a camera at
                  // a code and waiting is the whole interaction, and it should
                  // feel immediate.
                  scanDelay: const Duration(milliseconds: 250),
                  showGallery: false,
                  showToggleCamera: false,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.nearbyScanHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
      },
    );
  }
}
