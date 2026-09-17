// gf_uac.c — USB Audio Class 1 playback descriptors and PCM packing.
//
// See gf_uac.h for why this exists and what it deliberately leaves out.

#include "gf_uac.h"

#include <string.h>

// ── Descriptor constants (USB 2.0 §9.4, USB Audio Class 1.0 §4) ──────────────

#define USB_DT_INTERFACE     0x04  ///< standard interface descriptor
#define USB_DT_ENDPOINT      0x05  ///< standard endpoint descriptor
#define USB_DT_CS_INTERFACE  0x24  ///< class-specific interface descriptor
#define USB_DT_CS_ENDPOINT   0x25  ///< class-specific endpoint descriptor

#define USB_CLASS_AUDIO          0x01
#define UAC_SUBCLASS_STREAMING   0x02  ///< audio streaming interface
#define UAC_PROTOCOL_V1          0x00  ///< UAC2 interfaces say 0x20

#define UAC_AS_GENERAL           0x01  ///< streaming interface: format tag
#define UAC_FORMAT_TYPE          0x02  ///< streaming interface: sample layout
#define UAC_EP_GENERAL           0x01  ///< class-specific endpoint: controls
#define UAC_FORMAT_TYPE_I        0x01  ///< plain PCM-style frames
#define UAC_FORMAT_TAG_PCM       0x0001

#define USB_EP_TRANSFER_MASK     0x03
#define USB_EP_TRANSFER_ISO      0x01
#define USB_EP_DIR_IN            0x80

/// Reads a little-endian 3-byte sample rate, the width UAC1 uses for rates.
static uint32_t read_rate24(const uint8_t* p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16);
}

// ── Scan state ───────────────────────────────────────────────────────────────

/// What has been learned so far about the alternate setting being read.
///
/// Descriptors arrive as a flat list: an interface descriptor, then the
/// class-specific and endpoint descriptors that belong to it, until the next
/// interface descriptor starts. So one alternate is accumulated here and
/// committed when the next interface begins, or when the list ends.
typedef struct {
    int in_streaming_alt;   ///< current interface is a UAC1 streaming alternate
    int is_pcm;             ///< AS_GENERAL said PCM
    int has_format;         ///< a Type I FORMAT_TYPE descriptor was read
    int has_endpoint;       ///< an isochronous OUT endpoint was read
    GfUacPlaybackAlt alt;   ///< the alternate being built
} ScanState;

/// Appends the alternate in [st] to [out] if it turned out to be a complete
/// PCM playback format. Returns the new count.
static int commit_alt(const ScanState* st, GfUacPlaybackAlt* out,
                      int count, int max_out)
{
    if (!st->in_streaming_alt) return count;
    if (!st->is_pcm || !st->has_format || !st->has_endpoint) return count;
    if (count >= max_out) return count;
    out[count] = st->alt;
    return count + 1;
}

/// Starts a new alternate from a standard interface descriptor.
static void begin_interface(ScanState* st, const uint8_t* d, int dlen)
{
    memset(st, 0, sizeof(*st));
    if (dlen < 9) return;

    const uint8_t cls = d[5], subclass = d[6], protocol = d[7];
    // Only UAC1 streaming interfaces carry formats this driver can play.
    // The control interface (subclass 1) uses the same class-specific
    // descriptor type for unrelated things, so it must not be parsed as one.
    if (cls != USB_CLASS_AUDIO || subclass != UAC_SUBCLASS_STREAMING ||
        protocol != UAC_PROTOCOL_V1) {
        return;
    }

    st->in_streaming_alt       = 1;
    st->alt.interface_number   = d[2];
    st->alt.alt_setting        = d[3];
}

/// Reads the sample layout: channels, sample width and supported rates.
static void read_format_type(ScanState* st, const uint8_t* d, int dlen)
{
    // bLength, bDescriptorType, bDescriptorSubtype, bFormatType, bNrChannels,
    // bSubframeSize, bBitResolution, bSamFreqType, then the rates.
    if (dlen < 8 || d[3] != UAC_FORMAT_TYPE_I) return;

    GfUacPlaybackAlt* a = &st->alt;
    a->channels       = d[4];
    a->subframe_bytes = d[5];
    a->bit_resolution = d[6];

    const uint8_t freq_type = d[7];
    if (freq_type == 0) {
        // Continuous: a lower and an upper bound, any rate between is fine.
        if (dlen < 14) return;
        a->continuous_rates = 1;
        a->rate_count       = 2;
        a->rates[0]         = read_rate24(d + 8);
        a->rates[1]         = read_rate24(d + 11);
    } else {
        // Discrete: exactly the listed rates, three bytes each.
        int n = freq_type;
        if (8 + n * 3 > dlen) n = (dlen - 8) / 3;   // truncated list
        if (n > GF_UAC_MAX_RATES) n = GF_UAC_MAX_RATES;
        for (int i = 0; i < n; ++i) a->rates[i] = read_rate24(d + 8 + i * 3);
        a->rate_count = (uint8_t)n;
    }
    st->has_format = a->rate_count > 0;
}

/// Reads the data endpoint the audio will be sent to.
static void read_endpoint(ScanState* st, const uint8_t* d, int dlen)
{
    if (dlen < 7 || st->has_endpoint) return;   // first data endpoint wins

    const uint8_t address = d[2], attributes = d[3];
    // Playback needs an isochronous endpoint pointing away from the host.
    // An IN endpoint in a playback alternate is the async feedback channel.
    if ((attributes & USB_EP_TRANSFER_MASK) != USB_EP_TRANSFER_ISO) return;
    if (address & USB_EP_DIR_IN) return;

    GfUacPlaybackAlt* a = &st->alt;
    a->endpoint_address = address;
    a->sync_type        = (uint8_t)((attributes >> 2) & 0x03);
    // The top bits of wMaxPacketSize are a high-speed transaction multiplier,
    // not part of the size.
    a->max_packet_bytes = (uint16_t)((d[4] | (d[5] << 8)) & 0x07FF);
    a->interval         = d[6];
    st->has_endpoint    = 1;
}

/// Dispatches one descriptor that belongs to the current streaming alternate.
static void read_streaming_descriptor(ScanState* st, const uint8_t* d, int dlen)
{
    const uint8_t type = d[1];
    const uint8_t subtype = dlen >= 3 ? d[2] : 0;

    if (type == USB_DT_CS_INTERFACE && subtype == UAC_AS_GENERAL && dlen >= 7) {
        st->is_pcm = (uint16_t)(d[5] | (d[6] << 8)) == UAC_FORMAT_TAG_PCM;
    } else if (type == USB_DT_CS_INTERFACE && subtype == UAC_FORMAT_TYPE) {
        read_format_type(st, d, dlen);
    } else if (type == USB_DT_ENDPOINT) {
        read_endpoint(st, d, dlen);
    } else if (type == USB_DT_CS_ENDPOINT && subtype == UAC_EP_GENERAL &&
               dlen >= 4 && st->has_endpoint) {
        // Bit 0: the endpoint has a sampling-frequency control, i.e. the rate
        // must (or at least may) be set with SET_CUR before streaming.
        st->alt.has_freq_control = (uint8_t)(d[3] & 0x01);
    }
}

// ── Public API ───────────────────────────────────────────────────────────────

int gf_uac_find_playback_alts(const uint8_t* raw, int len,
                              GfUacPlaybackAlt* out, int max_out)
{
    if (raw == NULL || out == NULL || max_out <= 0) return 0;

    ScanState st;
    memset(&st, 0, sizeof(st));
    int count = 0;

    for (int pos = 0; pos + 2 <= len;) {
        const int dlen = raw[pos];
        // A zero or overlong length would loop forever or read past the end;
        // either way the rest of the list cannot be trusted.
        if (dlen < 2 || pos + dlen > len) break;

        const uint8_t* d = raw + pos;
        if (d[1] == USB_DT_INTERFACE) {
            count = commit_alt(&st, out, count, max_out);
            begin_interface(&st, d, dlen);
        } else if (st.in_streaming_alt) {
            read_streaming_descriptor(&st, d, dlen);
        }
        pos += dlen;
    }
    return commit_alt(&st, out, count, max_out);
}

int gf_uac_alt_supports_rate(const GfUacPlaybackAlt* alt, uint32_t sample_rate)
{
    if (alt == NULL) return 0;
    if (alt->continuous_rates) {
        return alt->rate_count >= 2 && sample_rate >= alt->rates[0] &&
               sample_rate <= alt->rates[1];
    }
    for (int i = 0; i < alt->rate_count; ++i) {
        if (alt->rates[i] == sample_rate) return 1;
    }
    return 0;
}

/// Whether GrooveForge's streamer can drive [alt] at [sample_rate] at all.
static int alt_is_usable(const GfUacPlaybackAlt* alt, uint32_t sample_rate)
{
    if (!gf_uac_alt_supports_rate(alt, sample_rate)) return 0;

    // Asynchronous DACs need the feedback endpoint this driver lacks: without
    // it the host sends at its own rate and the DAC's buffer drifts until it
    // over- or underflows.
    if (alt->sync_type == GF_UAC_SYNC_ASYNC) return 0;

    if (alt->channels < 1 || alt->channels > 2) return 0;
    if (alt->subframe_bytes < 2 || alt->subframe_bytes > 4) return 0;
    if (alt->bit_resolution < 8 || alt->bit_resolution > alt->subframe_bytes * 8) {
        return 0;
    }

    // The largest packet at this rate is ceil(rate / 1000) frames on a
    // full-speed bus, the worst case (high speed packets are smaller).
    const uint32_t frames = (sample_rate + 999u) / 1000u;
    const uint32_t bytes  = frames * alt->channels * alt->subframe_bytes;
    return bytes <= alt->max_packet_bytes;
}

int gf_uac_pick_playback_alt(const GfUacPlaybackAlt* alts, int count,
                             uint32_t sample_rate)
{
    int best = -1;
    int best_score = -1;
    for (int i = 0; i < count; ++i) {
        if (!alt_is_usable(&alts[i], sample_rate)) continue;
        // Stereo first (a mono DAC loses the stereo image), then resolution.
        const int score = alts[i].channels * 100 + alts[i].bit_resolution;
        if (score > best_score) {
            best = i;
            best_score = score;
        }
    }
    return best;
}

int gf_uac_packets_per_second(int high_speed, uint8_t interval)
{
    // Full speed: one packet per 1 ms frame, whatever bInterval says — UAC1
    // requires it to be 1 there.
    if (!high_speed) return 1000;

    // High speed: 8000 microframes per second, one packet every
    // 2^(bInterval-1) of them.
    int exponent = interval < 1 ? 0 : interval - 1;
    if (exponent > 12) exponent = 12;
    const int pps = 8000 >> exponent;
    return pps < 1 ? 1 : pps;
}

int gf_uac_next_packet_frames(uint32_t* accumulator, uint32_t sample_rate,
                              int packets_per_second)
{
    if (accumulator == NULL || packets_per_second <= 0) return 0;
    // Bresenham-style: add one packet's worth of samples, emit the whole
    // frames, keep the fraction for the next packet.
    *accumulator += sample_rate;
    const uint32_t frames = *accumulator / (uint32_t)packets_per_second;
    *accumulator -= frames * (uint32_t)packets_per_second;
    return (int)frames;
}

/// Converts one float sample to a signed integer of [bits] bits, clipped.
static int32_t float_to_int(float s, int bits)
{
    if (s > 1.0f) s = 1.0f;
    if (s < -1.0f) s = -1.0f;
    const double full_scale = (double)((1u << (bits - 1)) - 1u);
    const double v = (double)s * full_scale;
    return (int32_t)(v >= 0.0 ? v + 0.5 : v - 0.5);   // round to nearest
}

/// Writes [value] left-aligned into [subframe_bytes] little-endian bytes.
static void write_sample(uint8_t* dst, int32_t value, int bits, int subframe_bytes)
{
    // Left alignment: a 24-bit sample in a 4-byte slot is shifted up one byte
    // so the DAC reads it at the right magnitude. Done on the unsigned bit
    // pattern because shifting a negative signed value is undefined in C.
    const int shift = subframe_bytes * 8 - bits;
    const uint32_t word = (uint32_t)value << shift;
    for (int b = 0; b < subframe_bytes; ++b) {
        dst[b] = (uint8_t)(word >> (8 * b));
    }
}

void gf_uac_encode_pcm(const float* stereo, int frames, int out_channels,
                       int subframe_bytes, int bit_resolution, uint8_t* dst)
{
    if (stereo == NULL || dst == NULL || frames <= 0) return;
    if (bit_resolution > subframe_bytes * 8) bit_resolution = subframe_bytes * 8;

    uint8_t* p = dst;
    for (int i = 0; i < frames; ++i) {
        const float left = stereo[i * 2], right = stereo[i * 2 + 1];
        if (out_channels == 1) {
            write_sample(p, float_to_int(0.5f * (left + right), bit_resolution),
                         bit_resolution, subframe_bytes);
            p += subframe_bytes;
            continue;
        }
        write_sample(p, float_to_int(left, bit_resolution),
                     bit_resolution, subframe_bytes);
        p += subframe_bytes;
        write_sample(p, float_to_int(right, bit_resolution),
                     bit_resolution, subframe_bytes);
        p += subframe_bytes;
    }
}
