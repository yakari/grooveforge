import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/rehearsal.dart';
import '../screens/rehearsals_screen.dart' show instrumentLabel;

/// Name and instrument, collected when a device needs a player of its own.
class RehearsalIdentity {
  const RehearsalIdentity(this.name, this.instrument);

  final String name;
  final String instrument;
}

/// Asks who is playing on this device.
///
/// Needed in two places, which is why it is here rather than beside either of
/// them. The obvious one is joining someone else's tune. The other is being
/// *removed* from one: the tombstone reaches the removed device too, which
/// clears its identity, and without a way to answer this question again it
/// could sync forever while being unable to record a note.
///
/// Not dismissible: a device with no identity cannot do anything useful in a
/// rehearsal, so backing out of the question leaves the user somewhere with no
/// exit. Answering it is the cheapest way out.
class RehearsalIdentityDialog extends StatefulWidget {
  const RehearsalIdentityDialog({super.key});

  @override
  State<RehearsalIdentityDialog> createState() =>
      _RehearsalIdentityDialogState();
}

class _RehearsalIdentityDialogState extends State<RehearsalIdentityDialog> {
  final _name = TextEditingController();
  String _instrument = 'guitar';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.joinIdentityTitle),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.joinIdentityHint,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              decoration:
                  InputDecoration(labelText: l10n.rehearsalFieldYourName),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _instrument,
              decoration:
                  InputDecoration(labelText: l10n.rehearsalFieldInstrument),
              items: [
                for (final id in kInstruments)
                  DropdownMenuItem(
                      value: id, child: Text(instrumentLabel(l10n, id))),
              ],
              onChanged: (v) => setState(() => _instrument = v ?? 'other'),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            RehearsalIdentity(
              _name.text.trim().isEmpty ? '?' : _name.text.trim(),
              _instrument,
            ),
          ),
          child: Text(l10n.joinIdentityConfirm),
        ),
      ],
    );
  }
}
