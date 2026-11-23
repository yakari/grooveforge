// gfpa_riff.cpp — The pool of Riff guitars and their render functions.
// See gfpa_riff_pool.h for why it is a pool, and native_audio/gf_riff.h for
// the guitar itself.

#include "gfpa_riff_pool.h"
#include "gf_riff.h"

#include <atomic>
#include <cstring>
#include <mutex>

namespace {

/// One MIDI event on its way to the audio thread.
struct RiffEvent {
    enum Type : uint8_t { NoteOn, NoteOff, Bend, Cc };
    Type    type;
    int16_t a;      ///< Note, or controller number.
    int16_t b;      ///< Velocity, or controller value.
    float   f;      ///< Bend, -1..1.
};

/// Ring size: far more events than a block can carry from a hand.
constexpr uint32_t kQueue = 256;

/// Samples rendered per call into the guitar: the mono scratch buffer.
constexpr int kPiece = 256;

/// One pool slot. Everything the Dart side writes is atomic or published
/// through [inUse] with release ordering.
struct RiffSlot {
    /// Taken by a rack slot. The audio thread renders silence while false.
    std::atomic<bool> inUse{false};
    /// Bumped on every acquire; the audio thread resets the guitar when it
    /// sees a new value, so a reused slot does not ring with old notes.
    std::atomic<uint32_t> generation{0};
    /// Events pushed before this index belong to a previous owner.
    std::atomic<uint32_t> discardBefore{0};
    uint32_t seenGeneration = 0;   ///< Audio thread only.

    gf_riff* riff = nullptr;       ///< Allocated once, never freed.
    float rate = 0.0f;             ///< Audio thread: the rate the guitar runs at.

    RiffEvent queue[kQueue];
    std::atomic<uint32_t> head{0};   ///< Next write (Dart isolate).
    std::atomic<uint32_t> tail{0};   ///< Next read (audio thread).

    // Knobs, in the units gf_riff_params takes.
    std::atomic<float> palmMute{0.0f}, pickPos{0.35f}, tone{0.7f};
    std::atomic<float> sustain{0.7f}, attack{0.7f}, bendRange{2.0f}, levelDb{0.0f};
    std::atomic<int>   pickup{GF_RIFF_PICKUP_BRIDGE}, humbucker{1};
    std::atomic<bool>  muted{false};
};

RiffSlot g_slots[kRiffSlots];
std::mutex g_poolMutex;   ///< Serialises acquire/release (Dart isolate only).

bool validSlot(int slot) { return slot >= 0 && slot < kRiffSlots; }

/// Queues [ev] for slot [s]; dropped when the ring is full (the audio thread
/// has stalled — losing a note beats blocking the UI).
void push(RiffSlot& s, const RiffEvent& ev) {
    const uint32_t h = s.head.load(std::memory_order_relaxed);
    if (h - s.tail.load(std::memory_order_acquire) >= kQueue) return;
    s.queue[h % kQueue] = ev;
    s.head.store(h + 1, std::memory_order_release);
}

/// Applies one controller: the sustain pedal, the mod wheel as vibrato, and
/// the two "all notes off" messages.
void applyCc(gf_riff* r, int cc, int value) {
    switch (cc) {
        case 1:   gf_riff_vibrato(r, (float)value / 127.0f); break;
        case 64:  gf_riff_sustain_pedal(r, value >= 64); break;
        case 120:
        case 123: gf_riff_all_notes_off(r); break;
        default: break;
    }
}

/// Audio thread: plays every queued event.
void drain(RiffSlot& s) {
    uint32_t t = s.tail.load(std::memory_order_relaxed);
    const uint32_t h = s.head.load(std::memory_order_acquire);
    for (; t != h; ++t) {
        const RiffEvent& ev = s.queue[t % kQueue];
        switch (ev.type) {
            case RiffEvent::NoteOn:  gf_riff_note_on(s.riff, ev.a, ev.b); break;
            case RiffEvent::NoteOff: gf_riff_note_off(s.riff, ev.a); break;
            case RiffEvent::Bend:    gf_riff_pitch_bend(s.riff, ev.f); break;
            case RiffEvent::Cc:      applyCc(s.riff, ev.a, ev.b); break;
        }
    }
    s.tail.store(t, std::memory_order_release);
}

/// Audio thread: hands the knobs to the guitar (it smooths them itself).
void pushParams(RiffSlot& s) {
    gf_riff_params p;
    p.palm_mute = s.palmMute.load(std::memory_order_relaxed);
    p.pick_pos = s.pickPos.load(std::memory_order_relaxed);
    p.pickup = s.pickup.load(std::memory_order_relaxed);
    p.humbucker = s.humbucker.load(std::memory_order_relaxed);
    p.tone = s.tone.load(std::memory_order_relaxed);
    p.sustain = s.sustain.load(std::memory_order_relaxed);
    p.attack = s.attack.load(std::memory_order_relaxed);
    p.bend_range = s.bendRange.load(std::memory_order_relaxed);
    p.level_db = s.levelDb.load(std::memory_order_relaxed);
    gf_riff_set_params(s.riff, &p);
}

/// Audio thread: a freshly acquired slot starts silent, without the events
/// its previous owner left behind.
void adoptGeneration(RiffSlot& s) {
    const uint32_t g = s.generation.load(std::memory_order_acquire);
    if (g == s.seenGeneration) return;
    s.seenGeneration = g;
    s.tail.store(s.discardBefore.load(std::memory_order_acquire),
                 std::memory_order_release);
    gf_riff_reset(s.riff);
}

/// Audio thread: follows the stream when it reopens at another rate.
void followRate(RiffSlot& s) {
    const float live = gfpa_stream_sample_rate();
    if (live <= 0.0f || live == s.rate) return;
    s.rate = live;
    gf_riff_set_sample_rate(s.riff, live);
}

/// Renders [n] frames of pool slot [slot] into [outL]/[outR]. A free slot,
/// or a muted one, writes silence (a muted guitar keeps ringing underneath,
/// so unmuting mid-note does not restart anything).
void renderSlot(int slot, float* outL, float* outR, int32_t n) {
    RiffSlot& s = g_slots[slot];
    if (!s.inUse.load(std::memory_order_acquire) || !s.riff) {
        std::memset(outL, 0, sizeof(float) * (size_t)n);
        std::memset(outR, 0, sizeof(float) * (size_t)n);
        return;
    }
    adoptGeneration(s);
    followRate(s);
    drain(s);
    pushParams(s);
    const bool muted = s.muted.load(std::memory_order_relaxed);
    float mono[kPiece];
    for (int32_t done = 0; done < n; done += kPiece) {
        const int len = (n - done < kPiece) ? (int)(n - done) : kPiece;
        gf_riff_process(s.riff, mono, len);
        for (int i = 0; i < len; ++i) {
            const float v = muted ? 0.0f : mono[i];
            outL[done + i] = v;
            outR[done + i] = v;
        }
    }
}

// One trampoline per slot: the desktop render signature carries no user data.
template <int N> void renderDesktop(float* l, float* r, int32_t n) { renderSlot(N, l, r, n); }
template <int N> void renderBus(float* l, float* r, int n, void*) { renderSlot(N, l, r, n); }

using DesktopFn = void (*)(float*, float*, int32_t);
using BusFn = void (*)(float*, float*, int, void*);

const DesktopFn kDesktopFns[kRiffSlots] = {
    renderDesktop<0>, renderDesktop<1>, renderDesktop<2>, renderDesktop<3>};
const BusFn kBusFns[kRiffSlots] = {
    renderBus<0>, renderBus<1>, renderBus<2>, renderBus<3>};

/// Default knob values, matching assets/plugins/riff.gfpd.
void resetKnobs(RiffSlot& s) {
    gf_riff_params p;
    gf_riff_default_params(&p);
    s.palmMute.store(p.palm_mute);
    s.pickPos.store(p.pick_pos);
    s.pickup.store(p.pickup);
    s.humbucker.store(p.humbucker);
    s.tone.store(p.tone);
    s.sustain.store(p.sustain);
    s.attack.store(p.attack);
    s.bendRange.store(p.bend_range);
    s.levelDb.store(p.level_db);
    s.muted.store(false);
}

} // namespace

int gfpa_riff_acquire(float sampleRate) {
    std::lock_guard<std::mutex> lock(g_poolMutex);
    for (int i = 0; i < kRiffSlots; ++i) {
        RiffSlot& s = g_slots[i];
        if (s.inUse.load(std::memory_order_acquire)) continue;
        if (!s.riff) {
            // The audio thread never touches a slot before inUse publishes
            // it, so creating the guitar here is safe.
            const float live = gfpa_stream_sample_rate();
            const float rate = live > 0.0f ? live : sampleRate;
            s.riff = gf_riff_create(rate);
            if (!s.riff) return -1;
            s.rate = rate;
        }
        resetKnobs(s);
        s.discardBefore.store(s.head.load(std::memory_order_relaxed),
                              std::memory_order_release);
        s.generation.fetch_add(1, std::memory_order_acq_rel);
        s.inUse.store(true, std::memory_order_release);
        return i;
    }
    return -1;
}

void gfpa_riff_release(int slot) {
    if (!validSlot(slot)) return;
    std::lock_guard<std::mutex> lock(g_poolMutex);
    g_slots[slot].inUse.store(false, std::memory_order_release);
}

void gfpa_riff_slot_set_param(int slot, const char* id, float v) {
    if (!validSlot(slot) || !id) return;
    RiffSlot& s = g_slots[slot];
    // Percent knobs arrive as 0-100; the guitar takes 0-1.
    if      (std::strcmp(id, "palm_mute") == 0) s.palmMute.store(v / 100.0f);
    else if (std::strcmp(id, "pick_pos") == 0)  s.pickPos.store(v / 100.0f);
    else if (std::strcmp(id, "tone") == 0)      s.tone.store(v / 100.0f);
    else if (std::strcmp(id, "sustain") == 0)   s.sustain.store(v / 100.0f);
    else if (std::strcmp(id, "attack") == 0)    s.attack.store(v / 100.0f);
    else if (std::strcmp(id, "pickup") == 0)    s.pickup.store((int)(v + 0.5f));
    else if (std::strcmp(id, "pickup_type") == 0) s.humbucker.store(v >= 0.5f ? 1 : 0);
    else if (std::strcmp(id, "bend_range") == 0) s.bendRange.store(v);
    else if (std::strcmp(id, "level") == 0)     s.levelDb.store(v);
}

void gfpa_riff_slot_set_muted(int slot, bool muted) {
    if (validSlot(slot)) g_slots[slot].muted.store(muted);
}

void gfpa_riff_slot_note_on(int slot, int note, int velocity) {
    if (!validSlot(slot)) return;
    push(g_slots[slot], {RiffEvent::NoteOn, (int16_t)note, (int16_t)velocity, 0.0f});
}

void gfpa_riff_slot_note_off(int slot, int note) {
    if (!validSlot(slot)) return;
    push(g_slots[slot], {RiffEvent::NoteOff, (int16_t)note, 0, 0.0f});
}

void gfpa_riff_slot_pitch_bend(int slot, float bend) {
    if (!validSlot(slot)) return;
    push(g_slots[slot], {RiffEvent::Bend, 0, 0, bend});
}

void gfpa_riff_slot_control_change(int slot, int cc, int value) {
    if (!validSlot(slot)) return;
    push(g_slots[slot], {RiffEvent::Cc, (int16_t)cc, (int16_t)value, 0.0f});
}

void* gfpa_riff_slot_render_fn(int slot) {
    return validSlot(slot) ? reinterpret_cast<void*>(kDesktopFns[slot]) : nullptr;
}

void* gfpa_riff_slot_bus_render_fn(int slot) {
    return validSlot(slot) ? reinterpret_cast<void*>(kBusFns[slot]) : nullptr;
}
