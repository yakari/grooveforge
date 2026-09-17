// usb_direct_output_android.h — Optional direct USB output (streamer side).
//
// The problem it solves: Android keeps a single USB audio device. With a USB
// microphone and a USB DAC on the same hub, whichever enumerated last wins and
// the other is dropped from the audio system entirely — the DAC falls silent
// and GrooveForge ends up on the phone speaker. The platform offers no switch
// for this on most phones (ro.audio.multi_usb_mode is an OEM property).
//
// The DAC is still a perfectly good USB device though, and Android lets an app
// open a USB device it has permission for. This module streams the bus to such
// a DAC directly over USB isochronous transfers, bypassing the Android audio
// stack for playback while the microphone keeps using it for capture.
//
// Division of labour:
//   - Kotlin (UsbDirectOutput.kt) decides *whether* to engage — the user opted
//     in, Android is not already routing to a USB output, a suitable DAC is
//     attached — asks for USB permission, claims the streaming interface,
//     selects the alternate setting and sets the sample rate.
//   - This module owns the stream: it takes the bus over from AAudio
//     (oboe_stream_begin_external_clock), keeps a few transfers queued on the
//     device, renders the next one each time one completes, and hands the bus
//     back to AAudio when it stops for any reason.
//   - gf_uac.c (native_audio/) holds the parts that need no device: descriptor
//     parsing, packet sizing, PCM encoding. Tested by gf_uac_smoke_test.
//
// Off by default. Nothing in this module runs unless the user enables the
// preference, so the normal AAudio path is untouched for everyone else.
#pragma once

#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

/// Result codes of usb_direct_output_start(). Mirrored in UsbDirectOutput.kt.
enum UsbDirectResult {
    USB_DIRECT_OK               =  0,
    USB_DIRECT_ALREADY_RUNNING  = -1,  ///< a stream is active; stop it first
    USB_DIRECT_NO_FORMAT        = -2,  ///< no UAC1 playback alternate at the bus rate
    USB_DIRECT_ALLOC_FAILED     = -3,  ///< could not allocate transfer buffers
    USB_DIRECT_SUBMIT_FAILED    = -4,  ///< the kernel refused the first transfers
};

/// Starts streaming the bus to a USB DAC.
///
/// [fd]        — file descriptor of an open UsbDeviceConnection. The caller
///               keeps the connection open until usb_direct_output_stop().
/// [raw]       — the connection's raw descriptors (getRawDescriptors()).
/// [rawLen]    — byte count of [raw].
/// [sampleRate]— rate to stream at; must be the bus rate.
///
/// The streaming interface must already be claimed, its alternate selected
/// and its sampling frequency set. Returns a UsbDirectResult.
int usb_direct_output_start(int fd, const uint8_t* raw, int rawLen,
                            int32_t sampleRate);

/// Stops the stream, waits for its thread, and hands the bus back to AAudio.
/// Safe to call when nothing is running, and after the stream stopped itself.
void usb_direct_output_stop(void);

/// Whether the stream is running. Becomes false by itself when the device is
/// unplugged or a transfer fails, which is how Kotlin notices.
bool usb_direct_output_is_running(void);

#ifdef __cplusplus
}
#endif
