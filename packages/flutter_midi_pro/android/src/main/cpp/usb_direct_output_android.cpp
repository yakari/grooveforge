// usb_direct_output_android.cpp — Optional direct USB output (streamer side).
//
// See usb_direct_output_android.h for why this exists.
//
// How audio reaches the DAC
// ─────────────────────────
// USB audio is carried by *isochronous* transfers: the host reserves a slot in
// every 1 ms bus frame and sends one packet of samples in it, no retries. The
// Linux kernel exposes this to user space through usbdevfs ("URBs" — USB
// request blocks): the app submits a buffer describing a run of packets, the
// kernel schedules them on consecutive frames, and the app "reaps" each URB
// once its last packet has gone out.
//
// This streamer keeps kUrbsInFlight URBs queued on the device at all times.
// Every time one is reaped, the next kUrbMilliseconds of audio is rendered from
// the bus and submitted behind the others. The queue is the output buffer:
// three 4 ms URBs means a reaped URB leaves 8 ms of audio ahead of the one being
// rendered, which is the slack the render thread has to be woken, render and
// submit before the device runs dry.
//
// Clocking
// ────────
// The DAC's endpoint is synchronous or adaptive (gf_uac refuses asynchronous
// ones): its sample clock follows the stream or the USB frame clock. So the
// host decides the rate simply by how many frames it puts in each packet —
// exactly 48 per millisecond at 48 kHz — and the reap cadence is the bus clock,
// the same role the AAudio callback plays normally.
//
// Threading
// ─────────
// One thread renders, submits and reaps. It is the only renderer of the bus
// while it runs: oboe_stream_begin_external_clock() closes AAudio before the
// first block is rendered, and oboe_stream_end_external_clock() is called only
// after the last one.
// Control calls (start/stop from JNI) are serialised by g_controlMtx.

#include "usb_direct_output_android.h"
#include "oboe_stream_android.h"
#include "gf_uac.h"

#include <android/log.h>
#include <jni.h>
#include <linux/usbdevice_fs.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/resource.h>

#include <atomic>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <thread>

#define LOG_TAG "UsbDirectOutput"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

// ── Tuning ───────────────────────────────────────────────────────────────────

/// Audio carried by one URB, in milliseconds.
///
/// Shorter means lower latency and more thread wake-ups. Four milliseconds is
/// 250 wake-ups a second — the same order as an AAudio stream at a 192-frame
/// burst — and 192 frames per render at 48 kHz, a block size every GFPA
/// effect already handles.
constexpr int kUrbMilliseconds = 4;

/// URBs kept queued on the device.
///
/// The render deadline after each reap is (kUrbsInFlight - 1) * kUrbMilliseconds
/// — 8 ms — which absorbs a late wake-up on a busy phone. Output latency is
/// roughly kUrbsInFlight * kUrbMilliseconds, 12 ms, plus the DAC's own.
constexpr int kUrbsInFlight = 3;

/// usbdevfs rejects URBs with more packets than this.
constexpr int kMaxPacketsPerUrb = 128;

/// The bus renders at most this many frames per call (kMaxFrames in
/// oboe_stream_android.cpp).
constexpr int kMaxRenderFrames = 4096;

/// Nice value for the streaming thread: Android's THREAD_PRIORITY_URGENT_AUDIO.
/// Apps may not use real-time scheduling, but this is what the platform's own
/// audio threads run at when they are not SCHED_FIFO.
constexpr int kUrgentAudioNice = -19;

/// Linux's USB_SPEED_HIGH (enum usb_device_speed).
constexpr int kUsbSpeedHigh = 3;

// ── State ────────────────────────────────────────────────────────────────────

/// One reusable transfer: the usbdevfs request plus the PCM bytes it carries.
struct Transfer {
    usbdevfs_urb* urb    = nullptr;  ///< header + per-packet descriptors
    uint8_t*      buffer = nullptr;  ///< packetsPerUrb * max_packet_bytes bytes
};

/// Everything one streaming session owns. Allocated by start, freed by stop.
struct Session {
    int              fd = -1;
    GfUacPlaybackAlt alt{};
    uint32_t         sampleRate    = 0;
    int              packetsPerSec = 0;
    int              packetsPerUrb = 0;

    /// Carries the fractional frame between packets (44.1 kHz), see
    /// gf_uac_next_packet_frames.
    uint32_t packetAccumulator = 0;

    Transfer transfers[kUrbsInFlight];

    /// Interleaved stereo render scratch, sized for the largest URB.
    float* renderBuffer = nullptr;

    /// Frame count of each packet in the URB being filled.
    int packetFrames[kMaxPacketsPerUrb] = {};

    std::thread       thread;
    std::atomic<bool> stopping{false};
};

/// The active session, or null. Only touched under g_controlMtx, apart from the
/// streaming thread's own pointer to it.
Session* g_session = nullptr;

/// Serialises start and stop.
std::mutex g_controlMtx;

/// Whether the streaming thread is alive and feeding the device. Cleared by
/// the thread itself when it exits for any reason.
std::atomic<bool> g_running{false};

// ── Transfers ────────────────────────────────────────────────────────────────

/// Allocates a session's transfers and render scratch. Returns false on
/// allocation failure, leaving whatever was allocated for freeSession().
bool allocateSession(Session* s)
{
    const size_t urbBytes = sizeof(usbdevfs_urb) +
            static_cast<size_t>(s->packetsPerUrb) * sizeof(usbdevfs_iso_packet_desc);
    const size_t dataBytes =
            static_cast<size_t>(s->packetsPerUrb) * s->alt.max_packet_bytes;

    for (Transfer& t : s->transfers) {
        t.urb    = static_cast<usbdevfs_urb*>(calloc(1, urbBytes));
        t.buffer = static_cast<uint8_t*>(calloc(1, dataBytes));
        if (t.urb == nullptr || t.buffer == nullptr) return false;
    }

    s->renderBuffer = static_cast<float*>(
            calloc(static_cast<size_t>(kMaxRenderFrames) * 2, sizeof(float)));
    return s->renderBuffer != nullptr;
}

/// Frees a session and everything it allocated.
void freeSession(Session* s)
{
    if (s == nullptr) return;
    for (Transfer& t : s->transfers) {
        free(t.urb);
        free(t.buffer);
    }
    free(s->renderBuffer);
    delete s;
}

/// Renders the next URB's worth of audio from the bus into [t] and fills in
/// its usbdevfs header. Real-time safe: no allocation, no locks, no logging.
void fillTransfer(Session* s, Transfer* t)
{
    // Decide each packet's frame count first: at 48 kHz every packet carries
    // 48 frames, at 44.1 kHz one packet in ten carries an extra frame.
    int totalFrames = 0;
    for (int p = 0; p < s->packetsPerUrb; ++p) {
        const int frames = gf_uac_next_packet_frames(
                &s->packetAccumulator, s->sampleRate, s->packetsPerSec);
        s->packetFrames[p] = frames;
        totalFrames += frames;
    }
    if (totalFrames > kMaxRenderFrames) totalFrames = kMaxRenderFrames;

    // Render the whole URB in one block, then pack it as the DAC's PCM.
    oboe_stream_render_external(s->renderBuffer, totalFrames);
    gf_uac_encode_pcm(s->renderBuffer, totalFrames, s->alt.channels,
                      s->alt.subframe_bytes, s->alt.bit_resolution, t->buffer);

    // Describe the packets: the kernel sends buffer[0..] in order, each
    // packet taking its own length.
    const int bytesPerFrame = s->alt.channels * s->alt.subframe_bytes;
    usbdevfs_urb* urb = t->urb;
    for (int p = 0; p < s->packetsPerUrb; ++p) {
        urb->iso_frame_desc[p].length        = static_cast<unsigned>(s->packetFrames[p] * bytesPerFrame);
        urb->iso_frame_desc[p].actual_length = 0;
        urb->iso_frame_desc[p].status        = 0;
    }

    urb->type              = USBDEVFS_URB_TYPE_ISO;
    urb->endpoint          = s->alt.endpoint_address;
    urb->status            = 0;
    // ISO_ASAP: schedule right behind whatever is already queued on the
    // endpoint rather than at a specific frame number.
    urb->flags             = USBDEVFS_URB_ISO_ASAP;
    urb->buffer            = t->buffer;
    urb->buffer_length     = totalFrames * bytesPerFrame;
    urb->actual_length     = 0;
    urb->start_frame       = 0;
    urb->number_of_packets = s->packetsPerUrb;
    urb->error_count       = 0;
    urb->signr             = 0;
    urb->usercontext       = t;
}

/// Hands [t] to the kernel. Returns 0 or an errno value.
int submitTransfer(Session* s, Transfer* t)
{
    if (ioctl(s->fd, USBDEVFS_SUBMITURB, t->urb) == 0) return 0;
    return errno;
}

/// Cancels every transfer still queued, so a blocked reap returns promptly.
/// Transfers that already completed just make the kernel answer EINVAL.
void discardTransfers(Session* s)
{
    for (Transfer& t : s->transfers) {
        ioctl(s->fd, USBDEVFS_DISCARDURB, t.urb);
    }
}

// ── Streaming thread ─────────────────────────────────────────────────────────

/// Keeps the device fed until asked to stop or until the device goes away.
///
/// [inFlight] — transfers queued when the thread starts (all of them).
void streamLoop(Session* s, int inFlight)
{
    prctl(PR_SET_NAME, "GF-UsbOut", 0, 0, 0);
    // Apps cannot have SCHED_FIFO, but they may raise their own threads to
    // urgent-audio priority. A failure only costs scheduling margin.
    if (setpriority(PRIO_PROCESS, 0, kUrgentAudioNice) != 0) {
        LOGW("Could not raise the streaming thread's priority (errno %d)", errno);
    }

    while (inFlight > 0) {
        // Block until the kernel reports one completed transfer.
        usbdevfs_urb* done = nullptr;
        if (ioctl(s->fd, USBDEVFS_REAPURB, &done) != 0) {
            if (errno == EINTR) continue;
            // ENODEV: unplugged. Nothing more will ever complete.
            LOGW("Reap failed (errno %d) — the DAC is gone", errno);
            break;
        }
        --inFlight;

        // A transfer the kernel killed means the device or the endpoint is no
        // longer usable (unplugged, interface released). Stop feeding it.
        // Per-packet errors (a missed frame) are not in done->status and are
        // not fatal: isochronous audio simply loses that millisecond.
        if (done->status == -ENODEV || done->status == -ESHUTDOWN) {
            s->stopping.store(true, std::memory_order_relaxed);
        }
        if (s->stopping.load(std::memory_order_relaxed)) continue;

        auto* t = static_cast<Transfer*>(done->usercontext);
        fillTransfer(s, t);
        const int err = submitTransfer(s, t);
        if (err != 0) {
            // Never logged from the loop in steady state; this is its exit.
            LOGE("Submitting a transfer failed (errno %d) — stopping", err);
            s->stopping.store(true, std::memory_order_relaxed);
            discardTransfers(s);
            continue;
        }
        ++inFlight;
    }

    // The last block has been rendered: AAudio may have the bus back.
    oboe_stream_end_external_clock();
    g_running.store(false, std::memory_order_relaxed);
    LOGI("Streaming thread finished");
}

/// Queues the first transfers on the calling thread. Returns 0 or an errno
/// value; on failure every transfer that did get queued has been reaped.
int primeTransfers(Session* s)
{
    int queued = 0;
    int err = 0;
    for (Transfer& t : s->transfers) {
        fillTransfer(s, &t);
        err = submitTransfer(s, &t);
        if (err != 0) break;
        ++queued;
    }
    if (err == 0) return 0;

    // Take back what was queued so the buffers can be freed safely.
    discardTransfers(s);
    for (; queued > 0; --queued) {
        usbdevfs_urb* done = nullptr;
        if (ioctl(s->fd, USBDEVFS_REAPURB, &done) != 0 && errno != EINTR) break;
    }
    return err;
}

/// Reads whether the device enumerated at high speed. Old kernels without
/// USBDEVFS_GET_SPEED are assumed full speed, where UAC1 DACs live.
bool isHighSpeed(int fd)
{
    const int speed = ioctl(fd, USBDEVFS_GET_SPEED);
    if (speed < 0) {
        LOGW("USBDEVFS_GET_SPEED unavailable (errno %d) — assuming full speed", errno);
        return false;
    }
    return speed == kUsbSpeedHigh;
}

/// Picks the playback format for [sampleRate] from [raw]. Returns false when
/// the device has none this streamer can drive.
bool pickFormat(const uint8_t* raw, int rawLen, int32_t sampleRate,
                GfUacPlaybackAlt* out)
{
    GfUacPlaybackAlt alts[GF_UAC_MAX_ALTS];
    const int count = gf_uac_find_playback_alts(raw, rawLen, alts, GF_UAC_MAX_ALTS);
    const int pick  = gf_uac_pick_playback_alt(alts, count,
                                               static_cast<uint32_t>(sampleRate));
    if (pick < 0) return false;
    *out = alts[pick];
    return true;
}

}  // namespace

// ── Public API ───────────────────────────────────────────────────────────────

extern "C" int usb_direct_output_start(int fd, const uint8_t* raw, int rawLen,
                                       int32_t sampleRate)
{
    std::lock_guard<std::mutex> lock(g_controlMtx);
    if (g_session != nullptr) return USB_DIRECT_ALREADY_RUNNING;

    auto* s = new Session();
    s->fd         = fd;
    s->sampleRate = static_cast<uint32_t>(sampleRate);
    if (!pickFormat(raw, rawLen, sampleRate, &s->alt)) {
        delete s;
        return USB_DIRECT_NO_FORMAT;
    }

    // Packet cadence from the bus speed, then as many packets as fit in one
    // URB's worth of milliseconds.
    s->packetsPerSec = gf_uac_packets_per_second(isHighSpeed(fd), s->alt.interval);
    s->packetsPerUrb = s->packetsPerSec * kUrbMilliseconds / 1000;
    if (s->packetsPerUrb < 1) s->packetsPerUrb = 1;
    if (s->packetsPerUrb > kMaxPacketsPerUrb) s->packetsPerUrb = kMaxPacketsPerUrb;

    if (!allocateSession(s)) {
        freeSession(s);
        return USB_DIRECT_ALLOC_FAILED;
    }

    // From here the bus is ours: AAudio is closed before the first render.
    oboe_stream_begin_external_clock(sampleRate);

    const int err = primeTransfers(s);
    if (err != 0) {
        LOGE("The DAC refused the first transfers (errno %d)", err);
        oboe_stream_end_external_clock();
        freeSession(s);
        return USB_DIRECT_SUBMIT_FAILED;
    }

    g_session = s;
    g_running.store(true, std::memory_order_relaxed);
    s->thread = std::thread(streamLoop, s, kUrbsInFlight);

    LOGI("Streaming to USB DAC: %u Hz, %d ch, %d-bit, endpoint 0x%02X, "
         "%d packets/s, %d packets x %d transfers (~%d ms buffer)",
         s->sampleRate, s->alt.channels, s->alt.bit_resolution,
         s->alt.endpoint_address, s->packetsPerSec, s->packetsPerUrb,
         kUrbsInFlight, kUrbsInFlight * kUrbMilliseconds);
    return USB_DIRECT_OK;
}

extern "C" void usb_direct_output_stop(void)
{
    std::lock_guard<std::mutex> lock(g_controlMtx);
    Session* s = g_session;
    if (s == nullptr) return;

    // Stop resubmitting, cancel what is queued, and wait: the loop exits once
    // every transfer has been reaped — at most one URB's duration.
    s->stopping.store(true, std::memory_order_relaxed);
    discardTransfers(s);
    if (s->thread.joinable()) s->thread.join();

    // Normally done by the thread already; idempotent.
    oboe_stream_end_external_clock();

    g_session = nullptr;
    freeSession(s);
    LOGI("Direct USB output stopped");
}

extern "C" bool usb_direct_output_is_running(void)
{
    return g_running.load(std::memory_order_relaxed);
}

// ── JNI bridge (UsbDirectOutput.kt) ──────────────────────────────────────────

/// Describes the playback format the streamer would use, so Kotlin can select
/// it on the device before starting.
///
/// Returns [interfaceNumber, altSetting, endpointAddress, hasFreqControl,
/// channels, bitResolution], or null when the device has no usable format at
/// [sampleRate].
extern "C" JNIEXPORT jintArray JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_UsbDirectOutput_nativeDescribe(
        JNIEnv* env, jclass /*clazz*/, jbyteArray raw, jint sampleRate)
{
    const jsize len = env->GetArrayLength(raw);
    jbyte* bytes = env->GetByteArrayElements(raw, nullptr);

    GfUacPlaybackAlt alt{};
    const bool found = pickFormat(reinterpret_cast<const uint8_t*>(bytes), len,
                                  sampleRate, &alt);
    env->ReleaseByteArrayElements(raw, bytes, JNI_ABORT);
    if (!found) return nullptr;

    const jint fields[] = {alt.interface_number, alt.alt_setting,
                           alt.endpoint_address, alt.has_freq_control,
                           alt.channels, alt.bit_resolution};
    jintArray result = env->NewIntArray(6);
    env->SetIntArrayRegion(result, 0, 6, fields);
    return result;
}

/// The rate the bus renders at — the only rate the DAC may be opened at.
extern "C" JNIEXPORT jint JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_UsbDirectOutput_nativeBusSampleRate(
        JNIEnv* /*env*/, jclass /*clazz*/)
{
    return oboe_stream_get_sample_rate();
}

extern "C" JNIEXPORT jint JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_UsbDirectOutput_nativeStart(
        JNIEnv* env, jclass /*clazz*/, jint fd, jbyteArray raw, jint sampleRate)
{
    const jsize len = env->GetArrayLength(raw);
    jbyte* bytes = env->GetByteArrayElements(raw, nullptr);
    const int result = usb_direct_output_start(
            fd, reinterpret_cast<const uint8_t*>(bytes), len, sampleRate);
    env->ReleaseByteArrayElements(raw, bytes, JNI_ABORT);
    return result;
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_UsbDirectOutput_nativeStop(
        JNIEnv* /*env*/, jclass /*clazz*/)
{
    usb_direct_output_stop();
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_UsbDirectOutput_nativeIsRunning(
        JNIEnv* /*env*/, jclass /*clazz*/)
{
    return usb_direct_output_is_running() ? JNI_TRUE : JNI_FALSE;
}
