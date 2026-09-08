import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'rack_screen.dart';
import 'rehearsals_screen.dart';

/// Hosts GrooveForge's main destinations: the rack and the rehearsal library.
///
/// The two are kept alive together in an [IndexedStack] rather than swapped.
/// [RackScreen] owns live audio state, per-slot FluidSynth instances and VST
/// plugin handles; disposing it on a tab switch would tear the audio graph down
/// every time someone glanced at the other tab.
///
/// Navigation chrome follows CLAUDE.md Rule 1:
///   - phone portrait  — a bottom [NavigationBar]
///   - phone landscape — a collapsed [NavigationRail]; the rack is already
///     vertically starved there, so 56 px of width costs less than 80 px of
///     height
///   - 900 px and up   — a [NavigationRail], with labels from 1280 px
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final destinations = [
      (icon: Icons.view_agenda_outlined,
       selected: Icons.view_agenda,
       label: l10n.rackTabLabel),
      (icon: Icons.groups_outlined,
       selected: Icons.groups,
       label: l10n.rehearsalsTabLabel),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isPhonePortrait =
            width < 600 && MediaQuery.of(context).orientation == Orientation.portrait;

        final body = IndexedStack(
          index: _index,
          children: const [RackScreen(), RehearsalsScreen()],
        );

        if (isPhonePortrait) {
          return Scaffold(
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: d.label,
                  ),
              ],
            ),
          );
        }

        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: width >= 1280
                    ? NavigationRailLabelType.all
                    : NavigationRailLabelType.none,
                destinations: [
                  for (final d in destinations)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selected),
                      label: Text(d.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}
