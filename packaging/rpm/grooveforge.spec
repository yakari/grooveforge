# RPM spec for GrooveForge — packages a pre-built Flutter bundle.
# The binary is built on Ubuntu CI and is glibc-compatible with Fedora.

Name:           grooveforge
Version:        %{_version}
Release:        1%{?dist}
Summary:        Cross-platform MIDI synthesizer and VST3 host

License:        MIT
URL:            https://grooveforge.music

# Disable debug-info generation — the Flutter bundle has no debuginfo to extract.
%global debug_package %{nil}

# Runtime dependencies — verified on packages.fedoraproject.org.
Requires:       gtk3
Requires:       alsa-lib
Requires:       pipewire-jack-audio-connection-kit-libs
Requires:       libX11
Requires:       fluidsynth-libs
Requires:       pulseaudio-libs
Requires:       mpv-libs
Recommends:     pipewire
Recommends:     pipewire-alsa
Recommends:     pipewire-pulseaudio
Recommends:     wireplumber

%description
GrooveForge connects to physical MIDI keyboards, hosts VST3 plugins,
and features a built-in multi-timbral synthesizer with vocoder support
and real-time Jam Mode with scale locking across multiple plugin slots.

# No source archive — files are copied into the buildroot directly by CI.
%install
# CI populates BUILDROOT before rpmbuild --noclean runs.

%files
%{_bindir}/grooveforge
%{_datadir}/grooveforge/
%{_datadir}/applications/grooveforge.desktop
%{_datadir}/icons/hicolor/512x512/apps/grooveforge.png
%{_datadir}/metainfo/com.grooveforge.grooveforge.metainfo.xml
