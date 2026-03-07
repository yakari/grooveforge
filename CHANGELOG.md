# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.7.1] - 2026-03-07
### Added
- **Vocoder Feedback Warning**: Implemented a safety modal that warns users about potential audio feedback (Larsen effect) when using the vocoder with internal microphones and speakers. The warning is shown once and can be dismissed permanently.

### Fixed
- **Android Audio Input Regression**: Fixed a critical issue where internal and external microphones were not working on Android due to missing runtime permissions and incorrect device ID handling in the native layer.

## [1.7.0] - 2026-03-07
### Added
- **Absolute Pitch Vocoder (Natural Mode)**: A complete redesign of the vocoder's high-fidelity mode using **PSOLA (Pitch Synchronous Overlap and Add)** grain synthesis. It now captures your voice cycle and triggers fixed-duration grains at the **exact MIDI frequency**. This preserves your natural vocal formants and vowel character, eliminating the "accelerated" feeling and ensuring perfect pitch locking even if you sing out of tune.
- **Audio Device Persistence Fix (Linux)**: Resolved an issue where the preferred audio input device was not correctly initialized on startup. All vocoder settings (Waveform, Noise Mix, Gain, etc.) are now correctly persistent and applied before the audio stream starts.
- **Improved Vocoder Volume**: Integrated RMS-based normalization into the PSOLA engine to ensure the Natural mode matches the perceived loudness of the other vocoder modes.
- **Vocoder Noise Gate**: Added a dedicated "GATE" control to the vocoder panel to eliminate background noise and feedback hum during quiet passages.
- **Zoomed Knob Preview**: Added a zoomed knob preview that appears on interaction (200ms hold or instant drag), providing clear visual feedback on the current value.
- **Autoscroll Toggle**: Added a user preference to enable or disable automatic channel list scrolling when MIDI notes are played (disabled by default).
- **Audio Output Device Selection**: Added an output device selector in Preferences, alongside the existing mic selector, for routing vocoder output to a specific speaker or headset.
- **AAudio Jitter Mitigation**: Integrated a background health watcher that monitors audio stream stability and triggers a silent engine restart if persistent glitches are detected.
- **DSP Inner-Loop Optimization**: Significantly reduced per-sample processing overhead by refactoring core audio synthesis logic, enhancing real-time performance on mobile devices.
- **Engine Stability & Audio Decoupling**: Massive improvement in overall app stability and sound quality by decoupling the low-level audio lifecycle from the Flutter UI thread. This eliminates the "chopped sound" and UI lag that previously occurred after extended use.

### Changed
- **Vocoder Mode Rename**: "Neutral" mode is now **"Natural"** to better reflect its high-fidelity vocal character.
- **Knob Responsiveness**: Enhanced `RotaryKnob` sizing and layout for narrow/mobile screens to improve touch accuracy and visibility.
- **Adaptive Vocoder Layout**: Optimized the vocoder row with smart icon/label switching to maintain accessibility on small screens.
- **Mic automatically restarts on device change**: Changing the input or output device in Preferences now automatically restarts the audio capture engine without requiring a manual "Refresh Mic" tap.

### Fixed
- **Absolute MIDI Locking**: Fixed the issue where the vocoder would follow the singer's pitch inaccuracies instead of the keyboard notes.
- **Optimized Vocoder Latency**: Achieved near-real-time performance by decoupling microphone capture from the main playback thread using a lock-free ring buffer. This eliminates the significant (400ms+) onset delay caused by Android's duplex clock synchronization.
- **Squelch Gate Precision**: Bypassed the noise gate when notes are active to prevent sound occlusion at the start of vocal phrases.
- **USB Audio Device Enumeration**: Switched Android audio device queries to `GET_DEVICES_ALL` with capability-based filtering, ensuring USB microphones and wired headsets are always listed even when sharing a USB-C hub.
- **Duplicate device in input list**: Bidirectional USB headsets (e.g. a USB headset with both mic and speaker) no longer appear twice in the mic selector — only the source/mic side is listed.
- **Stale device ID after reconnect**: Selecting a USB mic or headset and then unplugging/replugging the hub (which reassigns device IDs) no longer shows "Disconnected" — the selection automatically resets to the system default.
- **Auto-fallback on device disconnect**: The app now listens to Android `AudioDeviceCallback` events. When a previously selected input or output device is removed, the selection resets to the system default automatically.
- **Audio engine restart loop**: Added a re-entrancy guard (`_isRestartingCapture`) with a 500 ms cooldown on `restartCapture()` to prevent Fluidsynth's Oboe disconnect-recovery events from cascading into an infinite restart loop.

## [1.6.1] - 2026-03-06
### Added
- **Revamped User Guide**: Reorganized tabs (Features, MIDI Connectivity, Soundfonts, Musical Tips).
- **Vocoder Documentation**: Added detailed instructions on how to use the new vocoder features.
- **Musical Improvisation Tips**: Added a new section with theory bits to help beginners improvise using scales.
- **Auto-Welcome**: The user guide now appears automatically on first launch or after a major update to highlight new features.

## [1.6.0] - 2026-03-05
### Added
- **Vocoder Overhaul**: 32-band polyphonic vocoder with carrier waveform selection (including new 'Neutral' mode).
- **Native Audio Input**: High-performance audio capture via miniaudio + FFI.
- **Rotary UI Control**: New `RotaryKnob` custom widget for a more tactile experience.
- **Advanced Vocoder Controls**: Added Bandwidth and Sibilance injection parameters.
- **Audio Session Management**: Integration with `audio_session` for improved Bluetooth and routing support.
- **Enhanced Level Meters**: Real-time visual feedback for vocoder input and output levels.

### Changed
- **Performance Optimizations**: Low-latency audio profile and optimized note release tails.

## [1.5.2] - 2026-03-04
### Fixed
- **Chord Release Stabilization**: Optimized the chord release logic in Jam Mode by implementing a robust 50ms debounced stabilization window, preventing chord identity "flickering" during natural finger lift-offs.

## [1.5.1] - 2026-03-04
### Added
- **Instant Device Connection**: When a new MIDI device is plugged in while on the main synthesizer screen, an automatic prompt appears allowing instant connection.
- **Improved Auto-Reconnect**: MIDI devices now reliably auto-reconnect even if unplugged and replugged while the app is running.

## [1.5.0] - 2026-03-04
### Added
- **Internationalization (i18n)**: Added full support for application localization.
- **French Language**: Translated the entire application UI and provided a French changelog (`CHANGELOG.fr.md`).
- **Language Preferences**: Users can now dynamically switch the application language from the Preferences screen (System Default, English, French).

## [1.4.5] - 2026-03-04
### Added
- **Jam Mode Borders Toggle**: Added a user-configurable preference to toggle the visibility of the visual borders around scale-mapped key groups in Jam Mode.
- **Jam Mode Wrong Note Highlighting**: Pressing an out-of-scale physical key in Jam Mode now colors the originally pressed wrong key in red and highlights the correctly mapped target note in blue, with a user preference to optionally toggle the red coloring.

## [1.4.4] - 2026-03-03
### Added
- **Jam Mode Click Zones**: Virtual Piano keys in Jam Mode are now grouped with the valid keys they snap to, forming unified clickable zones enclosed in subtle colored borders.

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
