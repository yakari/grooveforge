# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
