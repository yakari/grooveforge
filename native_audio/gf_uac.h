// gf_uac.h — USB Audio Class 1 (UAC1) playback descriptors and PCM packing.
//
// Why this exists: Android keeps only one USB audio device at a time. Plug a
// USB microphone into a hub that has its own DAC and Android silently drops
// the DAC — the phone falls back to its speaker even though the DAC is still
// electrically there. GrooveForge's optional "direct USB output" talks to such
// a dropped DAC itself, through the raw USB device Android still exposes, and
// this file is the part of that driver that does not need a device at all:
//
//   - reading the device's descriptors (the self-description every USB device
//     returns) to find a playback format GrooveForge can feed;
//   - deciding how many sample frames go into each 1 ms USB packet;
//   - converting the engine's float samples into the integer PCM bytes the
//     DAC expects.
//
// Keeping it free of Android and of any I/O is what lets
// gf_uac_smoke_test.c check it against real descriptors on a desktop.
//
// Scope, deliberately narrow:
//   - UAC1 only (interface protocol 0). UAC2 devices are ignored.
//   - PCM (format tag 1), Type I format, 1 or 2 channels, 2–4 byte samples.
//   - Synchronous and adaptive endpoints only. An asynchronous DAC runs on its
//     own clock and needs a feedback endpoint to tell the host how fast to
//     send; that is not implemented, so those alternates are reported but
//     never picked.
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Most discrete sample rates one alternate setting may list. UAC1 devices
/// rarely list more than four; extra entries are ignored.
#define GF_UAC_MAX_RATES 8

/// Most playback alternates collected from one device.
#define GF_UAC_MAX_ALTS 16

/// How a playback endpoint's sample clock relates to the host.
///
/// The USB spec's "synchronisation type", bits 2–3 of bmAttributes.
typedef enum {
    /// No synchronisation declared — treated like adaptive by most hosts.
    GF_UAC_SYNC_NONE = 0,
    /// The DAC runs its own clock and reports its rate through a feedback
    /// endpoint. Not supported here.
    GF_UAC_SYNC_ASYNC = 1,
    /// The DAC locks its clock onto the stream it receives.
    GF_UAC_SYNC_ADAPTIVE = 2,
    /// The DAC derives its clock from the USB frame clock (1 kHz start-of-frame).
    GF_UAC_SYNC_SYNCHRONOUS = 3,
} GfUacSyncType;

/// One playback alternate setting of a USB Audio streaming interface.
///
/// A USB audio interface exposes several "alternate settings" of the same
/// interface: alternate 0 has no endpoint (the silent, zero-bandwidth state)
/// and each further alternate is one format the device can play.
typedef struct {
    uint8_t  interface_number;   ///< bInterfaceNumber of the streaming interface
    uint8_t  alt_setting;        ///< bAlternateSetting to select before streaming
    uint8_t  endpoint_address;   ///< isochronous OUT endpoint (bit 7 clear)
    uint8_t  sync_type;          ///< a GfUacSyncType
    uint8_t  interval;           ///< bInterval, as found in the descriptor
    uint8_t  channels;           ///< bNrChannels
    uint8_t  subframe_bytes;     ///< bSubframeSize: bytes per sample on the wire
    uint8_t  bit_resolution;     ///< bBitResolution: significant bits per sample
    uint16_t max_packet_bytes;   ///< wMaxPacketSize: most bytes one packet may carry
    uint8_t  has_freq_control;   ///< endpoint accepts a SET_CUR sampling frequency
    uint8_t  continuous_rates;   ///< 1: rates[0]..rates[1] is a range, 0: a list
    uint8_t  rate_count;         ///< entries used in rates[]
    uint32_t rates[GF_UAC_MAX_RATES];
} GfUacPlaybackAlt;

/// Collects every UAC1 PCM playback alternate described in [raw].
///
/// [raw] is the device's concatenated descriptors as returned by Android's
/// UsbDeviceConnection.getRawDescriptors() — the device descriptor followed by
/// the active configuration and everything inside it. Malformed or truncated
/// descriptors end the scan rather than being read past.
///
/// Returns how many alternates were written to [out] (at most [max_out]).
int gf_uac_find_playback_alts(const uint8_t* raw, int len,
                              GfUacPlaybackAlt* out, int max_out);

/// Whether [alt] can play at [sample_rate] Hz.
int gf_uac_alt_supports_rate(const GfUacPlaybackAlt* alt, uint32_t sample_rate);

/// Picks the best alternate GrooveForge can stream at [sample_rate] Hz.
///
/// Requirements: the rate is supported, the endpoint is synchronous or
/// adaptive, 1 or 2 channels, 2–4 byte samples, and a 1 ms packet at that rate
/// fits in wMaxPacketSize. Among those, stereo beats mono and more bits beat
/// fewer.
///
/// Returns the index into [alts], or -1 when nothing qualifies.
int gf_uac_pick_playback_alt(const GfUacPlaybackAlt* alts, int count,
                             uint32_t sample_rate);

/// USB packets per second for an isochronous endpoint.
///
/// A full-speed bus sends one packet per 1 ms frame. A high-speed bus divides
/// each frame into eight 125 µs microframes and the endpoint's bInterval picks
/// one packet every 2^(bInterval-1) of them.
///
/// [high_speed] — 1 when the device enumerated at high speed.
/// [interval]   — the endpoint's bInterval.
int gf_uac_packets_per_second(int high_speed, uint8_t interval);

/// Distributes a sample rate over whole-frame packets.
///
/// 48 kHz at 1000 packets/s is exactly 48 frames every packet. 44.1 kHz is
/// not a whole number of frames per millisecond, so nine packets carry 44
/// frames and the tenth carries 45 — the remainder is carried forward in
/// [*accumulator] so the long-run rate is exact.
///
/// [accumulator] — caller-owned state, start at 0.
/// Returns the frame count for the next packet.
int gf_uac_next_packet_frames(uint32_t* accumulator, uint32_t sample_rate,
                              int packets_per_second);

/// Converts interleaved stereo floats into the DAC's integer PCM bytes.
///
/// Samples are clipped to [-1, 1], scaled to [bit_resolution] bits, then
/// left-aligned in a [subframe_bytes]-wide little-endian slot (USB audio is
/// little-endian; a 24-bit sample in a 4-byte slot occupies the top 3 bytes).
/// A mono device receives the average of left and right.
///
/// [stereo]         — frames * 2 interleaved samples.
/// [out_channels]   — 1 or 2.
/// [dst]            — receives frames * out_channels * subframe_bytes bytes.
void gf_uac_encode_pcm(const float* stereo, int frames, int out_channels,
                       int subframe_bytes, int bit_resolution, uint8_t* dst);

#ifdef __cplusplus
}
#endif
