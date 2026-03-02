# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.3] - 2026-03-02
### Fixed
- **Virtual Piano Artifacts**: Fixed a bug where Virtual Piano shading did not update immediately when Jam Mode was started or stopped.
- **Scroll Interference**: Prevented the main screen from scrolling vertically when performing gestures on the Virtual Piano keys.

## [1.4.2] - 2026-03-02
### Added
- **Reactive Jam Mode Sync**: Scale tags and virtual piano visuals (grayed-out keys) now update in real-time when the jam master scale changes or when slave channel configurations are modified.

### Changed
- **Virtual Piano Scalability**: Slave channels now visually gray out keys that do not belong to the master channel's current scale.
- **Improved UI Performance**: Fixed complex widget nesting issues in `ChannelCard` to guarantee clean and reactive UI builds.

### Fixed
- **Glissando Behavior**: Notes outside the current scale continue to sound if they are part of an ongoing glissando gesture instead of being stopped abruptly.
- **Virtual Piano Artifacts**: Resolved keyboard transparency artifacts by using solid colors for disabled keys.

## [1.4.1] - 2026-02-28
### Added
- **Configurable Expressive Gestures**: Users can now independently assign actions (None, Pitch Bend, Vibrato, Glissando) to Vertical and Horizontal key gestures.
- **Unified Gesture Preferences**: High-level configuration in the Preferences screen with new axis-specific dropdown menus.
- **Android Permission Optimization**: Decoupled Bluetooth from Location for Android 12+. Location access is no longer required on modern devices.
- **Improved UI Responsiveness**: Refactored the Preferences screen with an adaptive layout to prevent text crushing on narrow mobile devices.

### Changed
- **Performance Optimization**: Chord detection in Jam mode is now asynchronous, significantly reducing UI latency during heavy performance tracking.

### Fixed
- Resolved a runtime `Provider` crash on application startup.
- Fixed a minor linting warning in the `VirtualPiano` logic.

## [1.4.0] - 2026-02-28
### Added
- **Expressive Gestures**: Introduced vertical Pitch Bend and horizontal Vibrato on the Virtual Piano.
- **Gesture-Locked Scrolling**: Automatic suppression of piano list scrolling while expressive gestures are in progress to prevent accidental movement.
- **Independent Jam Chords**: Every channel now detects and displays its own chord independently in Jam mode.
- **Dynamic Slave Visibility**: Slave channel chord names now hide automatically when they are not actively playing.

### Changed
- Refined Jam mode chord badges by removing the "JAM:" prefix for a cleaner aesthetic.
- Scale names across all channels correctly reference the Master's chord context for synchronized performance feedback.

## [1.3.6] - 2026-02-28
### Added
- New "About" section in Preferences screen.
- Integrated Changelog viewer to see the history of changes directly in the app.

## [1.3.5] - 2026-02-28
### Added
- Maximized vertical real estate for the Virtual Piano keys. Reduced padding and margins across the main screen and channel cards to improve playability on mobile/tablet devices.

## [1.3.4] - 2026-02-28
### Changed
- Virtual Piano "Glissando" (Drag to Play) is now enabled by default for new installations and preference resets.

## [1.3.3] - 2026-02-28
### Added
- Unified "boxed" styling for Jam Master, Slaves, and Scale controls in both horizontal and vertical layouts.
- Centered vertical layout for the Jam sidebar with a more compact footprint (95px width).
- New interactive icons for dropdowns to clearly signal clickability.

### Fixed
- Flutter assertion error when `itemHeight` was set too low in Jam dropdowns.
- Vertical sidebar now correctly centers vertically on the left edge.

## [1.3.2] - 2026-02-27

### Added
- **Dual-Mode Jam UI:** Overhauled the Jam Session widget with strict layout isolation. Mobile landscape now features a premium, labeled vertical sidebar, while portrait/narrow displays use an ultra-compact, correctly ordered horizontal bar.
- **Subtle Labels:** Added high-contrast, tiny labels to both horizontal and vertical Jam UI modes for improved clarity during performance.

### Fixed
- **Splash Screen Cropping:** Changed splash screen image scaling to prevent cropping on portrait displays.
- **Jam Bar Restoration:** Restored the legacy widget order (Jam, Master, Slaves, Scale) and compact container sizing in the horizontal header.
- **Label Redundancy:** Removed duplicate labels in the vertical sidebar for a cleaner aesthetic.

## [1.3.1] - 2026-02-27

### Added
- **Interactive User Guide:** A comprehensive, multi-tabbed in-app guide replacing the legacy CC help modal. It covers connectivity, soundfonts, CC mapping, and Jam Mode.
- **Exhaustive System Actions:** All 8 system-level MIDI CC actions (1001-1008) are now fully implemented and documented, including Absolute Patch/Bank sweeps.

### Changed
- **System Action Renaming:** "Toggle Scale Lock" (1007) has been renamed to "Start/Stop Jam Mode" to better reflect its primary performance role.
- **Improved Action Descriptions:** Descriptions in the CC mapping service and Guide are now more descriptive and accurate.

## [1.3.0] - 2026-02-27

### Added
- **Musical Scale Names:** Real descriptive names (e.g., Dorian, Mixolydian, Altered Scale) are now displayed in the UI instead of generic labels.
- **Smart Jam Mode:** Significant overhaul of the Jam Mode engine to support multi-channel scale locking and dynamic mode calculation based on the Master's chord.
- **Improved UI Propagation:** Descriptive scale names are now propagated to all UI components, offering better musical feedback during performance.

### Changed
- **Default Lock Mode:** "Jam Mode" is now the default scale-locking preference.

### Fixed
- **Chord Release Stabilization:** Implemented a peak-preservation logic with a 30ms grace period to prevent chord identity "flickering" during release transitions.
## [1.2.1] - 2026-02-27

### Added
- **Reset Preferences:** Added a "Reset All Preferences" feature in the Preferences screen with a confirmation dialog to restore factory settings.
- **Improved Soundfont UI:** The Default soundfont now displays as "Default soundfont", appears first in lists, and is protected from deletion.

### Fixed
- **Linux Stability:** Resolved a crash and duplicated soundfont entries caused by logic errors in the soundfont loading state.
- **macOS Audio Pipeline:** Complete refactor of the macOS audio engine to use a single shared `AVAudioEngine` with 16 mixer buses, providing better performance and fixing "no sound" issues.
- **macOS Custom Soundfonts:** Removed a redundant file-copying loop that caused `PathNotFoundException` and added an automatic bank fallback (MSB 0) to fix load error `-10851`.
- **Audio Improvements:** Boosted default audio volume on macOS by 15dB for better parity with other platforms.
- **Path Migration:** Implemented a robust migration layer to automatically move legacy soundfont paths to the new secure internal storage.


## [1.2.0] - 2026-02-26

### Added
- Implemented a custom application icon for all platforms.
- Added a native splash screen (Android, iOS) for a seamless startup experience.
- Created a dynamic, fullscreen Flutter splash screen that shows initialization progress (loading preferences, starting backends, etc.).

## [1.1.0] - 2026-02-26

### Added
- Bundled a default, lightweight General MIDI Soundfont (`TimGM6mb.sf2`) so the app produces sound out-of-the-box on all platforms without requiring a manual download.
- Added a horizontal scrollbar to the virtual piano.
- Added a preference to customize the default number of piano keys visible on screen.

### Changed
- The virtual piano now initializes centered on Middle C (C4) instead of the far left.
- Re-architected virtual piano auto-scrolling to track active notes robustly.
- Synthesizer view gracefully adapts to ultra-wide/short aspect ratios (e.g., landscape mobile phones) by displaying a single channel vertically.

## [1.0.1] - 2026-02-26

### Changed
- Replaced the channel configuration modal with interactive dropdowns for Soundfont, Patch, and Bank right on the `ChannelCard`.
- Made the dropdown layout responsive to different screen widths.

## [1.0.0] - 2026-02-26

### Added
- Initial project release.
- Core capability to parse MIDI.
- Bluetooth LE compatibility.
- Virtual piano interactable via mouse/touch.
- Real-time chord parsing and identification.
- User Preferences screen to select output MIDI devices or internal Soundfonts.
- Automatic channel parsing and UI component architecture `ChannelCard`.
- Scale-locking chord functionality to constraint the played keys.
