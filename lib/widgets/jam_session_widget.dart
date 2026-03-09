import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:grooveforge/l10n/app_localizations.dart';
import 'package:grooveforge/services/audio_engine.dart';

/// The control center for configuring Jam Mode parameters.
///
/// This widget provides toggles and dropdowns to assign the Master channel,
/// select Slave channels, choose the target mapping scale (e.g., Minor Pentatonic),
/// and quickly start/stop the feature.
///
/// It dynamically adapts its layout (horizontal bar vs. vertical sidebar)
/// based on available screen width and orientation, ensuring the controls
/// remain accessible but unobtrusive.
class JamSessionWidget extends StatelessWidget {
  final bool? forceVertical;
  const JamSessionWidget({super.key, this.forceVertical});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AudioEngine>();
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final isNarrow = MediaQuery.of(context).size.width < 800;

    // Use forced orientation if provided, otherwise fallback to responsive logic
    final useVertical = forceVertical ?? (isLandscape && isNarrow);

    if (useVertical) {
      return _buildVerticalSidebar(context, engine);
    } else {
      return _buildHorizontalHeader(context, engine);
    }
  }

  Widget _buildHorizontalHeader(BuildContext context, AudioEngine engine) {
    return Align(
      alignment: Alignment.center,
      child: Card(
        elevation: 4,
        margin: const EdgeInsets.only(bottom: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                Colors.deepPurple.withValues(alpha: 0.1),
                Colors.blue.withValues(alpha: 0.1),
              ],
            ),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildStartStopButton(engine),
              _buildScaleDropdown(engine),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalSidebar(BuildContext context, AudioEngine engine) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Container(
          width: 95,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.deepPurple.withValues(alpha: 0.15),
                Colors.blue.withValues(alpha: 0.15),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              _buildStartStopButton(engine, isVertical: true),
              const Divider(height: 16, indent: 8, endIndent: 8),
              _buildScaleDropdown(engine, isVertical: true),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStartStopButton(AudioEngine engine, {bool isVertical = false}) {
    return ValueListenableBuilder<bool>(
      valueListenable: engine.jamEnabled,
      builder: (context, enabled, _) {
        return ElevatedButton.icon(
          onPressed: () {
            engine.jamEnabled.value = !engine.jamEnabled.value;
            engine.toastNotifier.value = AppLocalizations.of(
              context,
            )!.jamModeToast(
              engine.jamEnabled.value
                  ? AppLocalizations.of(context)!.jamStarted
                  : AppLocalizations.of(context)!.jamStopped,
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: enabled ? Colors.redAccent : Colors.greenAccent,
            foregroundColor: Colors.black87,
            elevation: isVertical ? 2 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(isVertical ? 12 : 8),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: isVertical ? 12 : 12,
              vertical: isVertical ? 16 : 8,
            ),
          ),
          icon: Icon(
            enabled ? Icons.stop : Icons.play_arrow,
            size: isVertical ? 18 : 18,
          ),
          label: Text(
            enabled
                ? AppLocalizations.of(context)!.jamStop
                : AppLocalizations.of(context)!.jamStart,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: isVertical ? 12 : 13,
              letterSpacing: isVertical ? 1.0 : null,
            ),
          ),
        );
      },
    );
  }

  Widget _buildScaleDropdown(AudioEngine engine, {bool isVertical = false}) {
    return ValueListenableBuilder<ScaleType>(
      valueListenable: engine.jamScaleType,
      builder: (context, scale, _) {
        final dropdown = DropdownButton<ScaleType>(
          value: scale,
          underline: const SizedBox(),
          isExpanded: isVertical,
          itemHeight: null, // Avoid assertion error
          isDense: true,
          padding: EdgeInsets.zero,
          alignment: isVertical ? Alignment.center : Alignment.centerLeft,
          dropdownColor: Theme.of(context).cardColor,
          icon: const SizedBox(), // Hide default icon
          items:
              ScaleType.values
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      alignment:
                          isVertical ? Alignment.center : Alignment.centerLeft,
                      child: Text(
                        s.name.toUpperCase(),
                        textAlign:
                            isVertical ? TextAlign.center : TextAlign.start,
                        style: TextStyle(
                          fontSize: isVertical ? 10 : 12,
                          fontWeight: FontWeight.bold,
                          color: isVertical ? null : Colors.blueAccent,
                        ),
                      ),
                    ),
                  )
                  .toList(),
          onChanged: (val) {
            if (val != null) engine.jamScaleType.value = val;
          },
        );

        final content = _buildBoxedContainer(
          isVertical: isVertical,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isVertical) Expanded(child: dropdown) else dropdown,
              const Icon(
                Icons.arrow_drop_down,
                size: 14,
                color: Colors.blueAccent,
              ),
            ],
          ),
        );

        return _buildLabeledControl(
          AppLocalizations.of(context)!.jamScale,
          content,
          isVertical: isVertical,
        );
      },
    );
  }

  Widget _buildLabeledControl(
    String label,
    Widget control, {
    required bool isVertical,
  }) {
    if (isVertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [_buildLabel(label), control],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${label.toUpperCase()}:',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: Colors.blueAccent.withValues(alpha: 0.6),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        control,
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: Colors.blueAccent.withValues(alpha: 0.7),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildBoxedContainer({
    required bool isVertical,
    required Widget child,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isVertical ? 6 : 10,
        vertical: isVertical ? 2 : 4,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
        color: Colors.blueAccent.withValues(alpha: 0.05),
      ),
      child: child,
    );
  }
}
