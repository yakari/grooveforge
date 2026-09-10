import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
/// The rehearsal tab keeps its own [Navigator]. Opening a tune used to push
/// over the whole shell, which hid the tabs and meant leaving a rehearsal to
/// glance at the rack — losing the open tune, its transport and its engine.
/// Nested, the tune is a route *inside* the tab: switching to the rack leaves
/// it standing, and coming back lands on it exactly as it was.
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

  /// The rehearsal tab's own navigation stack.
  ///
  /// Held here so the system back button can pop a tune before it reaches the
  /// shell — without this, back from an open tune would leave the app.
  final GlobalKey<NavigatorState> _rehearsalNav = GlobalKey<NavigatorState>();

  /// Handles a system back gesture.
  ///
  /// A tune open in the rehearsal tab is popped first. Otherwise the app goes
  /// to the background, which is what back does at the root of an Android app
  /// — and what `Navigator.pop` cannot do, since the shell *is* the root route
  /// and popping it does nothing at all.
  void _handleBack() {
    if (_index == 1) {
      final nav = _rehearsalNav.currentState;
      if (nav != null && nav.canPop()) {
        nav.pop();
        return;
      }
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final destinations = [
      (
        icon: Icons.view_agenda_outlined,
        selected: Icons.view_agenda,
        label: l10n.rackTabLabel,
      ),
      (
        icon: Icons.groups_outlined,
        selected: Icons.groups,
        label: l10n.rehearsalsTabLabel,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isPhonePortrait =
            width < 600 &&
            MediaQuery.of(context).orientation == Orientation.portrait;

        final body = IndexedStack(
          index: _index,
          children: [
            const RackScreen(),
            Navigator(
              key: _rehearsalNav,
              onGenerateRoute:
                  (settings) => MaterialPageRoute<void>(
                    settings: settings,
                    builder: (_) => const RehearsalsScreen(),
                  ),
            ),
          ],
        );

        if (isPhonePortrait) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _handleBack();
            },
            child: Scaffold(
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
            ),
          );
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _handleBack();
          },
          child: Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType:
                      width >= 1280
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
          ),
        );
      },
    );
  }
}
