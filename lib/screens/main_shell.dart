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

  /// Whether the rack is showing its back panel.
  ///
  /// Owned here rather than inside the rack so a system back gesture can close
  /// the patch view. Leaving it took finding the same small icon again, which
  /// is the one thing every other screen lets you do with a swipe.
  final ValueNotifier<bool> _rackPatchView = ValueNotifier(false);

  /// Rebuilds the shell when the rehearsal tab pushes or pops, so [_canPop]
  /// is never stale.
  late final _NestedStackObserver _rehearsalObserver =
      _NestedStackObserver(onChanged: _refreshAfterFrame);

  /// Whether the system may handle a back gesture itself.
  ///
  /// Only the *visible* tab is consulted. Everything in an [IndexedStack] stays
  /// mounted whether or not it is on screen, so a rack in its back panel would
  /// otherwise answer for a back gesture made in the rehearsal tab — closing
  /// something the user cannot even see.
  ///
  /// True in the ordinary case, which matters more than it looks: the system
  /// then pops whatever route is actually on top. A route pushed above the
  /// shell — Preferences, the latency probe, a document — is popped by the
  /// navigator that owns it, and this shell never hears about it. Answering
  /// "never pop me" instead made the shell take a hand in gestures that were
  /// none of its business.
  bool get _canPop {
    if (_index == 0) return !_rackPatchView.value;
    return !(_rehearsalNav.currentState?.canPop() ?? false);
  }

  /// Handles a system back gesture.
  ///
  /// A tune open in the rehearsal tab is popped first. Otherwise the app goes
  /// to the background, which is what back does at the root of an Android app
  /// — and what `Navigator.pop` cannot do, since the shell *is* the root route
  /// and popping it does nothing at all.
  /// Closes whatever the visible tab has open.
  ///
  /// Only ever reached when [_canPop] said there was something to close, so it
  /// never has to decide whether to leave the app — the system does that when
  /// [_canPop] is true.
  void _handleBack() {
    if (_index == 0) {
      // The rack's back panel is a view, not a route, so nothing else would
      // pop it.
      if (_rackPatchView.value) _rackPatchView.value = false;
      return;
    }
    _rehearsalNav.currentState?.maybePop();
  }

  @override
  void initState() {
    super.initState();
    // The patch view is a value, not a route, so nothing else would rebuild
    // the shell when it changes — and [_canPop] would go stale.
    _rackPatchView.addListener(_onPatchViewChanged);
  }

  void _onPatchViewChanged() => _refreshAfterFrame();

  /// Rebuilds after the current frame rather than inside it.
  ///
  /// Both callers fire during a build: a navigator pushes its first route
  /// while it is being built, and the rack flips the patch view from a
  /// listener. Calling setState there marks an element that is not yet in the
  /// tree, which trips `_elements.contains(element)` and paints the screen
  /// red. One frame of staleness in [_canPop] costs nothing — no back gesture
  /// arrives inside a single frame.
  void _refreshAfterFrame() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _rackPatchView.removeListener(_onPatchViewChanged);
    _rackPatchView.dispose();
    super.dispose();
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
            RackScreen(patchViewVisible: _rackPatchView),
            Navigator(
              key: _rehearsalNav,
              observers: [_rehearsalObserver],
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
            canPop: _canPop,
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
          canPop: _canPop,
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

/// Tells the shell when a nested navigator's stack changes.
///
/// The shell's [PopScope] has to know whether the rehearsal tab has a tune
/// open, and a navigator gives no notification of its own.
class _NestedStackObserver extends NavigatorObserver {
  _NestedStackObserver({required this.onChanged});

  final VoidCallback onChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previous) => onChanged();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previous) => onChanged();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previous) => onChanged();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      onChanged();
}
