import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Opens the Direct USB output explanation: a bottom sheet on phones, a
/// dialog on wider screens (Rule 1).
void showUsbDirectOutputHelp(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= 600;
  if (wide) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: const UsbDirectOutputHelp(),
        ),
      ),
    );
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          UsbDirectOutputHelp(scrollController: controller),
    ),
  );
}

/// Plain-language explanation of the Direct USB output.
///
/// Written for musicians, not audio engineers: what goes wrong without it,
/// what it does about it, when it acts, how to set it up, and the few things
/// that behave differently while it is active.
class UsbDirectOutputHelp extends StatelessWidget {
  /// Scroll controller of the enclosing bottom sheet, when there is one.
  final ScrollController? scrollController;
  const UsbDirectOutputHelp({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: ListView(
            controller: scrollController,
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            children: [
              Row(
                children: [
                  const Icon(Icons.usb, color: Colors.pinkAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      loc.usbDirectOutputTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              _HelpSection(
                icon: Icons.report_problem_outlined,
                title: loc.usbDirectOutputHelpProblemTitle,
                body: loc.usbDirectOutputHelpProblemBody,
              ),
              _HelpSection(
                icon: Icons.lightbulb_outline,
                title: loc.usbDirectOutputHelpSolutionTitle,
                body: loc.usbDirectOutputHelpSolutionBody,
              ),
              _HelpSection(
                icon: Icons.schedule,
                title: loc.usbDirectOutputHelpWhenTitle,
                body: loc.usbDirectOutputHelpWhenBody,
              ),
              _HelpSection(
                icon: Icons.checklist,
                title: loc.usbDirectOutputHelpStepsTitle,
                items: [
                  loc.usbDirectOutputHelpStep1,
                  loc.usbDirectOutputHelpStep2,
                  loc.usbDirectOutputHelpStep3,
                  loc.usbDirectOutputHelpStep4,
                ],
                numbered: true,
              ),
              _HelpSection(
                icon: Icons.info_outline,
                title: loc.usbDirectOutputHelpTipsTitle,
                items: [
                  loc.usbDirectOutputHelpTipVolume,
                  loc.usbDirectOutputHelpTipCompat,
                  loc.usbDirectOutputHelpTipOtherApps,
                  loc.usbDirectOutputHelpTipGiveBack,
                  loc.usbDirectOutputHelpTipCharger,
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(loc.usbDirectOutputHelpClose),
            ),
          ),
        ),
      ],
    );
  }
}

/// One titled block of the help sheet: either a paragraph ([body]) or a
/// list of [items], numbered for steps and bulleted otherwise.
class _HelpSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final List<String> items;
  final bool numbered;

  const _HelpSection({
    required this.icon,
    required this.title,
    this.body,
    this.items = const [],
    this.numbered = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.pinkAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (body != null) Text(body!, style: theme.textTheme.bodyMedium),
          for (var i = 0; i < items.length; i++)
            _HelpItem(
              marker: numbered ? '${i + 1}.' : '•',
              text: items[i],
            ),
        ],
      ),
    );
  }
}

/// A single step or tip, with its number or bullet hanging on the left.
class _HelpItem extends StatelessWidget {
  final String marker;
  final String text;
  const _HelpItem({required this.marker, required this.text});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 22, child: Text(marker, style: style)),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
