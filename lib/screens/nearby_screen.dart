import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_localizations.dart';
import '../models/rehearsal.dart';
import '../services/rehearsal_protocol.dart';
import '../services/rehearsal_sync_service.dart';
import 'scan_ticket_screen.dart';

/// Shares a rehearsal with the people in the room.
///
/// The QR carries the endpoint itself — address, port, rehearsal id and key —
/// so a joiner standing next to the host connects straight to it. That is the
/// whole reason first contact needs no discovery protocol: the person scanning
/// is right there, and the code they are pointing a camera at already says
/// where to go (REHEARSALS.md §4.2).
///
/// The *link* carries the same weight as the QR rather than being small print
/// underneath it, because desktop has no live scanner at all and plenty of
/// laptops have no camera (decision D11). It is the whole ticket, not a short
/// code: nothing shorter can carry the key and the address, so nothing shorter
/// is enough to join with.
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key, required this.rehearsal});

  final Rehearsal rehearsal;

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RehearsalSyncService>().startHosting(widget.rehearsal);
    });
  }

  @override
  void dispose() {
    // Hosting keeps a socket open; leaving the screen should close it rather
    // than leave the rehearsal quietly shared for the rest of the session.
    _service?.stopHosting();
    super.dispose();
  }

  RehearsalSyncService? _service;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final service = context.watch<RehearsalSyncService>();
    _service = service;
    final ticket = service.ticket;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.nearbyTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (ticket == null)
                  _NotSharing(error: service.lastError)
                else
                  _Sharing(ticket: ticket),
                const SizedBox(height: 24),
                _PeerList(service: service),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotSharing extends StatelessWidget {
  const _NotSharing({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    if (error == 'no-network') {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.nearbyNoNetwork,
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
        ),
      );
    }
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _Sharing extends StatelessWidget {
  const _Sharing({required this.ticket});

  final JoinTicket ticket;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.nearbyShare, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          l10n.nearbyHint,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              // A QR needs a light quiet zone to scan reliably; drawing it on
              // the dark theme's background would make it much harder to read.
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: QrImageView(
              data: ticket.toUri(),
              size: 240,
              backgroundColor: Colors.white,
              // Medium recovery: a rehearsal room is not a clean lab, and the
              // extra redundancy costs only a slightly denser code.
              errorCorrectionLevel: QrErrorCorrectLevel.M,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _LinkBox(ticket: ticket),
        const SizedBox(height: 8),
        Center(
          child: Text(
            l10n.nearbyHostAddress(ticket.host, ticket.port),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// The full join link, for anyone who cannot scan.
///
/// This is the whole ticket — rehearsal id, key, address and port — because
/// nothing shorter is enough on its own: a six-character code carries neither
/// the key nor the address, so there would be no way to find the host or prove
/// you were invited. A short code becomes possible once mDNS lets the app look
/// the host up by name; until then, the link is what travels.
class _LinkBox extends StatelessWidget {
  const _LinkBox({required this.ticket});

  final JoinTicket ticket;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final uri = ticket.toUri();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.nearbyLinkHint,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SelectableText(
            uri,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              // Long, and wrapping is what makes it readable enough to check
              // that the address looks right before sending it.
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: uri));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.nearbyCopied),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: Text(l10n.nearbyCopyLink),
          ),
        ),
      ],
    );
  }
}

class _PeerList extends StatelessWidget {
  const _PeerList({required this.service});

  final RehearsalSyncService service;

  /// Turns a protocol step into something a musician would recognise.
  String _label(AppLocalizations l10n, String status) => switch (status) {
        'handshake' => l10n.syncStepHandshake,
        'manifest' => l10n.syncStepManifest,
        'sending' => l10n.syncStepSending,
        'receiving' => l10n.syncStepReceiving,
        'done' => l10n.syncStepDone,
        'connecting' => l10n.nearbyConnecting,
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (service.peers.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(l10n.nearbyWaiting,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.nearbyPeers(service.peers.length),
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final peer in service.peers)
          ListTile(
            dense: true,
            leading: Icon(
              peer.status == 'done' ? Icons.check_circle : Icons.sync,
              color: peer.status == 'done'
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(peer.address),
            subtitle: Text(_label(l10n, peer.status)),
          ),
      ],
    );
  }
}

/// Joins a rehearsal someone else is sharing.
///
/// Scanning is offered where a live scanner exists; everywhere else — and as a
/// fallback everywhere — the code can be typed. The typed path is not a
/// degraded mode: on desktop it is the only one.
class JoinRehearsalScreen extends StatefulWidget {
  const JoinRehearsalScreen({super.key});

  /// Whether this platform can run a live camera scanner.
  ///
  /// flutter_zxing's reader is built on the official `camera` plugin, which
  /// supports Android and iOS only.
  static bool get canScan => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  State<JoinRehearsalScreen> createState() => _JoinRehearsalScreenState();
}

class _JoinRehearsalScreenState extends State<JoinRehearsalScreen> {
  final _uriController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _uriController.dispose();
    super.dispose();
  }

  /// Opens the camera and joins whatever it reads.
  Future<void> _scan() async {
    final ticket = await Navigator.of(context).push<JoinTicket>(
      MaterialPageRoute(builder: (_) => const ScanTicketScreen()),
    );
    if (ticket == null || !mounted) return;
    await _joinTicket(ticket);
  }

  Future<void> _joinWith(String text) async {
    final l10n = AppLocalizations.of(context)!;
    final trimmed = text.trim();
    final ticket = JoinTicket.parse(trimmed);
    if (ticket == null) {
      setState(() {
        // Someone typing six characters has almost certainly read the short
        // code off the other screen, and deserves to be told that specifically
        // rather than "that did not work".
        _error = RegExp(r'^[A-Za-z0-9]{4,10}$').hasMatch(trimmed)
            ? l10n.nearbyLooksLikeCode
            : l10n.nearbyNotALink;
      });
      return;
    }
    await _joinTicket(ticket);
  }

  /// Connects and syncs. Shared by the scanned and the pasted paths, so the
  /// two cannot drift apart in how they report success or failure.
  Future<void> _joinTicket(JoinTicket ticket) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
    });

    final service = context.read<RehearsalSyncService>();
    final report = await service.join(ticket);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!report.ok) {
      setState(() => _error = l10n.nearbyFailed(report.error ?? ''));
      return;
    }
    Navigator.of(context).pop(report);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.nearbyJoin)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (JoinRehearsalScreen.canScan) ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(l10n.nearbyScanOpen),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(l10n.nearbyScanOr,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 12),
                ] else
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(l10n.nearbyScanUnsupported,
                          style: theme.textTheme.bodySmall),
                    ),
                  ),
                const SizedBox(height: 12),
                // The full ticket text, which is what a scanner produces and
                // what someone can paste from a message.
                TextField(
                  controller: _uriController,
                  autofocus: !JoinRehearsalScreen.canScan,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: l10n.nearbyPasteLink,
                    border: const OutlineInputBorder(),
                    errorText: _error,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste),
                      tooltip: l10n.nearbyPasteFromClipboard,
                      onPressed: () async {
                        final data =
                            await Clipboard.getData(Clipboard.kTextPlain);
                        final text = data?.text;
                        if (text == null || !mounted) return;
                        _uriController.text = text.trim();
                        setState(() => _error = null);
                      },
                    ),
                  ),
                  onSubmitted: _busy ? null : _joinWith,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      _busy ? null : () => _joinWith(_uriController.text),
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: Text(_busy ? l10n.nearbySyncing : l10n.nearbyJoin),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
