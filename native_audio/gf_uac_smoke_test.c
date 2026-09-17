// gf_uac_smoke_test.c — Offline checks for the direct USB output's device side.
//
// Everything the direct USB output decides before a single byte reaches a DAC
// is checked here, without a phone or a DAC:
//
//   1. a real device — the CS202 DAC built into a USB-C hub, descriptors
//      captured from a Galaxy Z Fold 6 with `dumpsys usb dump-descriptors
//      -dump-raw` — yields exactly its one playback format, and its headset
//      microphone (same class, IN endpoint) is not mistaken for one;
//   2. formats the streamer cannot drive are refused: UAC2, asynchronous
//      endpoints, rates the DAC does not list, packets too big to fit;
//   3. stereo and higher resolution win when a device offers a choice;
//   4. 44.1 kHz spreads over 1 ms packets with an exact long-run rate;
//   5. PCM bytes come out little-endian, clipped, left-aligned, and averaged
//      for a mono DAC;
//   6. a truncated or corrupt descriptor list ends the scan instead of being
//      read past.
//
// Build: see CMakeLists.txt — target "gf_uac_smoke_test".
// Run  : ./scripts/run_smoke_tests.sh uac

#include "gf_uac.h"

#include <stdio.h>
#include <string.h>

static int g_fails = 0;

/// Records one expectation and prints it, so a failure names itself.
static void check(int cond, const char* what)
{
    printf("  %s %s\n", cond ? "ok  " : "FAIL", what);
    if (!cond) g_fails++;
}

// ── Real device: CS202 USB-C hub DAC (VID 0x0020, PID 0x0B21) ────────────────
//
// UAC1, 48 kHz / 16-bit / stereo playback on interface 1 alternate 1 through a
// synchronous isochronous OUT endpoint 0x03, plus a stereo microphone on
// interface 2 and a HID interface for the headset buttons.
static const uint8_t kCs202[] = {
    0x12, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x40, 0x20, 0x00, 0x21, 0x0B, 0x00, 0x01, 0x01, 0x02,
    0x03, 0x01, 0x09, 0x02, 0xEF, 0x00, 0x04, 0x01, 0x00, 0x80, 0x32, 0x09, 0x04, 0x00, 0x00, 0x00,
    0x01, 0x01, 0x00, 0x00, 0x0A, 0x24, 0x01, 0x00, 0x01, 0x55, 0x00, 0x02, 0x01, 0x02, 0x0C, 0x24,
    0x02, 0x01, 0x01, 0x01, 0x00, 0x02, 0x03, 0x00, 0x00, 0x00, 0x0D, 0x24, 0x04, 0x06, 0x02, 0x05,
    0x05, 0x02, 0x03, 0x00, 0x00, 0x00, 0x00, 0x0A, 0x24, 0x06, 0x02, 0x01, 0x01, 0x01, 0x02, 0x02,
    0x00, 0x09, 0x24, 0x03, 0x03, 0x01, 0x03, 0x00, 0x02, 0x00, 0x0C, 0x24, 0x02, 0x04, 0x01, 0x02,
    0x00, 0x02, 0x03, 0x00, 0x00, 0x00, 0x0A, 0x24, 0x06, 0x05, 0x04, 0x01, 0x03, 0x00, 0x00, 0x00,
    0x09, 0x24, 0x03, 0x06, 0x01, 0x01, 0x00, 0x05, 0x00, 0x09, 0x04, 0x01, 0x00, 0x00, 0x01, 0x02,
    0x00, 0x00, 0x09, 0x04, 0x01, 0x01, 0x01, 0x01, 0x02, 0x00, 0x00, 0x07, 0x24, 0x01, 0x01, 0x01,
    0x01, 0x00, 0x0B, 0x24, 0x02, 0x01, 0x02, 0x02, 0x10, 0x01, 0x80, 0xBB, 0x00, 0x09, 0x05, 0x03,
    0x0D, 0x80, 0x01, 0x01, 0x00, 0x00, 0x07, 0x25, 0x01, 0x01, 0x01, 0x01, 0x00, 0x09, 0x04, 0x02,
    0x00, 0x00, 0x01, 0x02, 0x00, 0x00, 0x09, 0x04, 0x02, 0x01, 0x01, 0x01, 0x02, 0x00, 0x00, 0x07,
    0x24, 0x01, 0x06, 0x01, 0x01, 0x00, 0x0B, 0x24, 0x02, 0x01, 0x02, 0x02, 0x10, 0x01, 0x80, 0xBB,
    0x00, 0x09, 0x05, 0x83, 0x0D, 0xD0, 0x00, 0x01, 0x00, 0x00, 0x07, 0x25, 0x01, 0x01, 0x00, 0x00,
    0x00, 0x09, 0x04, 0x03, 0x00, 0x02, 0x03, 0x00, 0x00, 0x00, 0x09, 0x21, 0x01, 0x02, 0x00, 0x01,
    0x22, 0x2F, 0x00, 0x07, 0x05, 0x82, 0x03, 0x20, 0x00, 0x01, 0x07, 0x05, 0x02, 0x03, 0x20, 0x00,
    0x01,
};

static void test_real_cs202(void)
{
    GfUacPlaybackAlt alts[GF_UAC_MAX_ALTS];
    const int n = gf_uac_find_playback_alts(kCs202, sizeof(kCs202), alts, GF_UAC_MAX_ALTS);
    check(n == 1, "exactly one playback alternate (the microphone is not one)");
    if (n != 1) return;

    const GfUacPlaybackAlt* a = &alts[0];
    check(a->interface_number == 1 && a->alt_setting == 1, "interface 1, alternate 1");
    check(a->endpoint_address == 0x03, "OUT endpoint 0x03");
    check(a->sync_type == GF_UAC_SYNC_SYNCHRONOUS, "synchronous endpoint");
    check(a->channels == 2 && a->subframe_bytes == 2 && a->bit_resolution == 16,
          "stereo, 2-byte, 16-bit");
    check(a->rate_count == 1 && a->rates[0] == 48000 && !a->continuous_rates,
          "one discrete rate: 48000 Hz");
    check(a->max_packet_bytes == 384, "wMaxPacketSize 384");
    check(a->has_freq_control == 1, "sampling-frequency control present");

    check(gf_uac_pick_playback_alt(alts, n, 48000) == 0, "picked at 48 kHz");
    check(gf_uac_pick_playback_alt(alts, n, 44100) == -1, "refused at 44.1 kHz");
}

// ── Synthetic descriptors ────────────────────────────────────────────────────

/// Appends a standard interface descriptor.
static int put_interface(uint8_t* p, uint8_t number, uint8_t alt, uint8_t num_ep,
                         uint8_t subclass, uint8_t protocol)
{
    const uint8_t d[9] = {9, 0x04, number, alt, num_ep, 0x01, subclass, protocol, 0};
    memcpy(p, d, sizeof(d));
    return sizeof(d);
}

/// Appends AS_GENERAL (PCM) plus a Type I format with one discrete rate.
static int put_pcm_format(uint8_t* p, uint8_t channels, uint8_t subframe,
                          uint8_t bits, uint32_t rate)
{
    const uint8_t general[7] = {7, 0x24, 0x01, 0x01, 0x01, 0x01, 0x00};
    const uint8_t format[11] = {11, 0x24, 0x02, 0x01, channels, subframe, bits, 1,
                                (uint8_t)rate, (uint8_t)(rate >> 8), (uint8_t)(rate >> 16)};
    memcpy(p, general, sizeof(general));
    memcpy(p + sizeof(general), format, sizeof(format));
    return sizeof(general) + sizeof(format);
}

/// Appends an isochronous endpoint descriptor.
static int put_iso_endpoint(uint8_t* p, uint8_t address, uint8_t sync, uint16_t max_packet)
{
    const uint8_t d[9] = {9, 0x05, address, (uint8_t)(0x01 | (sync << 2)),
                          (uint8_t)max_packet, (uint8_t)(max_packet >> 8), 1, 0, 0};
    memcpy(p, d, sizeof(d));
    return sizeof(d);
}

static void test_refusals(void)
{
    uint8_t buf[256];
    int len = 0;

    // Alternate A: UAC2 (protocol 0x20) — must be ignored entirely.
    len += put_interface(buf + len, 1, 1, 1, 0x02, 0x20);
    len += put_pcm_format(buf + len, 2, 3, 24, 48000);
    len += put_iso_endpoint(buf + len, 0x01, GF_UAC_SYNC_ADAPTIVE, 600);

    // Alternate B: UAC1 but asynchronous — found, never picked.
    len += put_interface(buf + len, 2, 1, 2, 0x02, 0x00);
    len += put_pcm_format(buf + len, 2, 3, 24, 48000);
    len += put_iso_endpoint(buf + len, 0x02, GF_UAC_SYNC_ASYNC, 600);
    len += put_iso_endpoint(buf + len, 0x82, 0, 3);   // its feedback endpoint

    // Alternate C: adaptive, but the packet cannot hold 48 stereo 3-byte frames.
    len += put_interface(buf + len, 3, 1, 1, 0x02, 0x00);
    len += put_pcm_format(buf + len, 2, 3, 24, 48000);
    len += put_iso_endpoint(buf + len, 0x03, GF_UAC_SYNC_ADAPTIVE, 200);

    GfUacPlaybackAlt alts[GF_UAC_MAX_ALTS];
    const int n = gf_uac_find_playback_alts(buf, len, alts, GF_UAC_MAX_ALTS);
    check(n == 2, "UAC2 alternate ignored, the two UAC1 ones found");
    check(n >= 1 && alts[0].sync_type == GF_UAC_SYNC_ASYNC &&
          alts[0].endpoint_address == 0x02,
          "async alternate keeps its OUT endpoint, not the feedback one");
    check(gf_uac_pick_playback_alt(alts, n, 48000) == -1,
          "nothing picked: async refused, oversized packet refused");
}

static void test_preferences(void)
{
    uint8_t buf[256];
    int len = 0;

    // Mono 24-bit, stereo 16-bit, stereo 24-bit — stereo 24-bit must win.
    len += put_interface(buf + len, 1, 1, 1, 0x02, 0x00);
    len += put_pcm_format(buf + len, 1, 3, 24, 48000);
    len += put_iso_endpoint(buf + len, 0x01, GF_UAC_SYNC_ADAPTIVE, 300);

    len += put_interface(buf + len, 1, 2, 1, 0x02, 0x00);
    len += put_pcm_format(buf + len, 2, 2, 16, 48000);
    len += put_iso_endpoint(buf + len, 0x01, GF_UAC_SYNC_ADAPTIVE, 300);

    len += put_interface(buf + len, 1, 3, 1, 0x02, 0x00);
    len += put_pcm_format(buf + len, 2, 3, 24, 48000);
    len += put_iso_endpoint(buf + len, 0x01, GF_UAC_SYNC_ADAPTIVE, 300);

    GfUacPlaybackAlt alts[GF_UAC_MAX_ALTS];
    const int n = gf_uac_find_playback_alts(buf, len, alts, GF_UAC_MAX_ALTS);
    const int pick = gf_uac_pick_playback_alt(alts, n, 48000);
    check(n == 3, "three alternates found");
    check(pick == 2 && alts[pick].alt_setting == 3, "stereo 24-bit preferred");

    // A continuous range covers any rate between its bounds.
    GfUacPlaybackAlt range;
    memset(&range, 0, sizeof(range));
    range.continuous_rates = 1;
    range.rate_count = 2;
    range.rates[0] = 8000;
    range.rates[1] = 96000;
    check(gf_uac_alt_supports_rate(&range, 44100) &&
          !gf_uac_alt_supports_rate(&range, 192000),
          "continuous range: 44.1 kHz in, 192 kHz out");
}

static void test_packet_sizing(void)
{
    uint32_t acc = 0;
    int total = 0, forty_fives = 0;
    for (int i = 0; i < 1000; ++i) {
        const int f = gf_uac_next_packet_frames(&acc, 44100, 1000);
        total += f;
        if (f == 45) forty_fives++;
        if (f != 44 && f != 45) { total = -1; break; }
    }
    check(total == 44100, "44.1 kHz: 1000 packets carry exactly 44100 frames");
    check(forty_fives == 100, "44.1 kHz: one 45-frame packet in ten");

    acc = 0;
    int all48 = 1;
    for (int i = 0; i < 100; ++i) {
        if (gf_uac_next_packet_frames(&acc, 48000, 1000) != 48) all48 = 0;
    }
    check(all48, "48 kHz: every packet is 48 frames");

    check(gf_uac_packets_per_second(0, 1) == 1000, "full speed: 1000 packets/s");
    check(gf_uac_packets_per_second(1, 1) == 8000, "high speed, bInterval 1: 8000 packets/s");
    check(gf_uac_packets_per_second(1, 4) == 1000, "high speed, bInterval 4: 1000 packets/s");
}

static void test_pcm_encoding(void)
{
    const float stereo[] = {1.0f, -1.0f, 2.0f, -2.0f, 0.5f, 0.0f};
    uint8_t out[32];

    // 16-bit in 2 bytes: full scale is 0x7FFF; out-of-range input clips.
    gf_uac_encode_pcm(stereo, 3, 2, 2, 16, out);
    check(out[0] == 0xFF && out[1] == 0x7F, "16-bit +1.0 -> 0x7FFF little-endian");
    check(out[2] == 0x01 && out[3] == 0x80, "16-bit -1.0 -> 0x8001");
    check(out[4] == 0xFF && out[5] == 0x7F && out[6] == 0x01 && out[7] == 0x80,
          "+/-2.0 clipped to full scale");
    check(out[8] == 0x00 && out[9] == 0x40, "16-bit +0.5 -> 0x4000 (rounded)");

    // 24-bit in a 4-byte slot is left-aligned: +1.0 -> 0x7FFFFF00.
    gf_uac_encode_pcm(stereo, 1, 2, 4, 24, out);
    check(out[0] == 0x00 && out[1] == 0xFF && out[2] == 0xFF && out[3] == 0x7F,
          "24-bit in 4 bytes left-aligned");

    // Mono DAC: left and right averaged.
    const float lr[] = {0.5f, -0.5f, 1.0f, 0.0f};
    gf_uac_encode_pcm(lr, 2, 1, 2, 16, out);
    check(out[0] == 0x00 && out[1] == 0x00, "mono: +0.5 and -0.5 average to silence");
    check(out[2] == 0x00 && out[3] == 0x40, "mono: 1.0 and 0.0 average to 0.5");
}

static void test_corrupt_input(void)
{
    GfUacPlaybackAlt alts[GF_UAC_MAX_ALTS];

    // The real device cut off in the middle of its playback format.
    check(gf_uac_find_playback_alts(kCs202, 160, alts, GF_UAC_MAX_ALTS) == 0,
          "truncated list: incomplete alternate not reported");

    // A zero-length descriptor would loop forever if it were trusted.
    const uint8_t zero[] = {9, 0x04, 1, 1, 1, 0x01, 0x02, 0x00, 0, 0, 0x24, 0x01};
    check(gf_uac_find_playback_alts(zero, sizeof(zero), alts, GF_UAC_MAX_ALTS) == 0,
          "zero-length descriptor ends the scan");

    check(gf_uac_find_playback_alts(NULL, 10, alts, GF_UAC_MAX_ALTS) == 0,
          "null input is harmless");
}

int main(void)
{
    printf("gf_uac_smoke_test — direct USB output, device side\n\n");

    printf("1. a real hub DAC (CS202)\n");
    test_real_cs202();

    printf("\n2. formats the streamer cannot drive\n");
    test_refusals();

    printf("\n3. choosing between formats\n");
    test_preferences();

    printf("\n4. packet sizing\n");
    test_packet_sizing();

    printf("\n5. PCM encoding\n");
    test_pcm_encoding();

    printf("\n6. corrupt descriptors\n");
    test_corrupt_input();

    printf("\n");
    if (g_fails == 0) {
        printf("OK — all USB audio checks passed.\n");
        return 0;
    }
    printf("FAILED — %d check(s).\n", g_fails);
    return 1;
}
