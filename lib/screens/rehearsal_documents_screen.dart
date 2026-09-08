import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/rehearsal.dart';
import '../services/file_picker_service.dart';
import '../services/rehearsal_engine.dart';
import '../services/rehearsal_library.dart';
import '../services/rehearsal_sync_service.dart';

/// The tune's shared vault: scores, charts, lyric sheets, photos of a part.
///
/// The same store-and-forward shape as everything else here — a document is
/// added on one device and reaches the others the next time they meet. It is
/// deliberately the simplest structure in the document: a file never changes,
/// so there is no revision, no conflict, and no editing. Replacing a score
/// means adding the new one and removing the old.
class RehearsalDocumentsScreen extends StatefulWidget {
  const RehearsalDocumentsScreen({super.key, required this.rehearsalId});

  final String rehearsalId;

  @override
  State<RehearsalDocumentsScreen> createState() =>
      _RehearsalDocumentsScreenState();
}

class _RehearsalDocumentsScreenState extends State<RehearsalDocumentsScreen> {
  bool _busy = false;

  Rehearsal? get _rehearsal => context
      .read<RehearsalLibrary>()
      .rehearsals
      .where((r) => r.id == widget.rehearsalId)
      .firstOrNull;

  Future<void> _add() async {
    final rehearsal = _rehearsal;
    if (rehearsal == null) return;

    final path = await FilePickerService.pickFile(
      context: context,
      // No extension filter. A band shares whatever it has — a PDF from the
      // publisher, a photo of a page, a chord chart someone typed — and a
      // filter here would only get in the way of that.
      dialogTitle: AppLocalizations.of(context)!.rehearsalDocumentAdd,
    );
    if (path == null || !mounted) return;

    final library = context.read<RehearsalLibrary>();
    final engine = context.read<RehearsalEngine>();
    final sync = context.read<RehearsalSyncService>();

    setState(() => _busy = true);
    try {
      await library.addDocument(
        rehearsal,
        sourcePath: path,
        // Attributed so a page nobody can read has someone to ask about.
        addedBy: engine.localState.selfMemberId ?? '',
      );
      // Straight out to the room rather than waiting for the next poll: the
      // usual reason for adding a score is that somebody is asking for it.
      unawaited(sync.syncNow());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(RehearsalDocument doc) async {
    final rehearsal = _rehearsal;
    if (rehearsal == null) return;
    final l10n = AppLocalizations.of(context)!;
    final path = await context.read<RehearsalLibrary>()
        .documentPath(rehearsal.id, doc);
    if (!mounted) return;

    // A scan is drawn in the app, because that is the common case and a
    // full-screen page is exactly what somebody at a music stand wants.
    if (doc.isImage) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _ImagePage(title: doc.sourceName, path: path),
      ));
      return;
    }

    // Everything else goes to whatever the device already uses for it. A PDF
    // viewer of our own would be worse than the one already installed, and on
    // Android this hands over a content URI rather than a bare path, which is
    // the only kind another app is allowed to open.
    final result = await OpenFilex.open(path);
    if (!mounted || result.type == ResultType.done) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.rehearsalDocumentNoViewer)),
    );
  }

  Future<void> _remove(RehearsalDocument doc) async {
    final rehearsal = _rehearsal;
    if (rehearsal == null) return;
    final l10n = AppLocalizations.of(context)!;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.rehearsalDocumentRemoveConfirm(doc.sourceName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.rehearsalCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.rehearsalDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final library = context.read<RehearsalLibrary>();
    final sync = context.read<RehearsalSyncService>();
    await library.removeDocument(rehearsal, doc);
    unawaited(sync.syncNow());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final library = context.watch<RehearsalLibrary>();
    final rehearsal = library.rehearsals
        .where((r) => r.id == widget.rehearsalId)
        .firstOrNull;
    final docs = rehearsal?.documents ?? const <RehearsalDocument>[];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.rehearsalDocuments)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'rehearsal-docs-fab',
        onPressed: _busy ? null : _add,
        icon: const Icon(Icons.note_add_outlined),
        label: Text(l10n.rehearsalDocumentAdd),
      ),
      body: SafeArea(
        top: false,
        child: docs.isEmpty
            ? _EmptyVault()
            : LayoutBuilder(
                builder: (context, constraints) {
                  // A grid once there is room: scores are browsed by
                  // recognising a name, and a single 1600 px-wide row is a
                  // poor way to do that on a laptop.
                  final columns = constraints.maxWidth >= 1000
                      ? 3
                      : constraints.maxWidth >= 640
                          ? 2
                          : 1;
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: 84,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: docs.length,
                    itemBuilder: (_, i) => _DocumentCard(
                      rehearsalId: widget.rehearsalId,
                      rehearsal: rehearsal!,
                      doc: docs[i],
                      onOpen: () => _open(docs[i]),
                      onRemove: () => _remove(docs[i]),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// One score in the vault.
class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.rehearsalId,
    required this.rehearsal,
    required this.doc,
    required this.onOpen,
    required this.onRemove,
  });

  final String rehearsalId;
  final Rehearsal rehearsal;
  final RehearsalDocument doc;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  IconData get _icon => switch (doc.extension) {
        'pdf' => Icons.picture_as_pdf_outlined,
        'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'bmp' =>
          Icons.image_outlined,
        'txt' || 'md' => Icons.article_outlined,
        _ => Icons.insert_drive_file_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final library = context.read<RehearsalLibrary>();
    final who = rehearsal.members
        .where((m) => m.id == doc.addedBy)
        .firstOrNull
        ?.displayName;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<String>(
        future: library.documentPath(rehearsalId, doc),
        builder: (context, snapshot) {
          // A document that is listed but whose file has not arrived yet is a
          // real state, not an error: the manifest merges before the bytes
          // move. Saying so beats a card that does nothing when tapped.
          final path = snapshot.data;
          final here = path != null && File(path).existsSync();
          return ListTile(
            leading: Icon(_icon, color: theme.colorScheme.primary),
            title: Text(
              doc.sourceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              here
                  ? [
                      l10n.rehearsalDocumentSize((doc.bytes / 1024).round()),
                      if (who != null && who.isNotEmpty)
                        l10n.rehearsalDocumentAddedBy(who),
                    ].join('   ·   ')
                  : l10n.rehearsalDocumentWaiting,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: here
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error,
              ),
            ),
            onTap: here ? onOpen : null,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.rehearsalDocumentRemove,
              onPressed: onRemove,
            ),
          );
        },
      ),
    );
  }
}

/// Full-screen scan, zoomable.
///
/// A photographed page is often taken at an angle and read at arm's length, so
/// being able to push into a corner of it matters more than it would for a
/// generated PDF.
class _ImagePage extends StatelessWidget {
  const _ImagePage({required this.title, required this.path});

  final String title;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: InteractiveViewer(
          maxScale: 6,
          child: Image.file(File(path), fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _EmptyVault extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.library_books_outlined,
                  size: 64,
                  color: theme.colorScheme.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(l10n.rehearsalDocumentsEmpty,
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                l10n.rehearsalDocumentsEmptyHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
