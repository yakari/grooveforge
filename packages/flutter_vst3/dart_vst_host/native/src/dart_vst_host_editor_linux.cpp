// Linux-only: opens a VST3 plugin's native editor UI in a standalone X11 window.
//
// dvh_open_editor  — creates a window, attaches IPlugView, starts an event loop.
// dvh_close_editor — tears everything down cleanly.
//
// IRunLoop support: many Linux VST3 plugins (Surge XT, JUCE-based, etc.) require
// the host to provide Steinberg::Linux::IRunLoop so they can register file
// descriptors and idle timers. Without it they return null from createView().

#ifdef __linux__

#include "dart_vst_host.h"
#include "dart_vst_host_internal.h"

#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "base/source/fobject.h"

// X11
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <poll.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <future>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

using namespace Steinberg;
using namespace Steinberg::Vst;
using namespace Steinberg::Linux;

// ─── IRunLoop implementation ──────────────────────────────────────────────────
// Plugins use this to register file descriptors (e.g. MIDI/audio FDs) and
// periodic timers. We service them inside the X11 event loop thread.

struct FdEntry {
    IEventHandler* handler;
    FileDescriptor fd;
};

struct TimerEntry {
    ITimerHandler* handler;
    TimerInterval  intervalMs;
    std::chrono::steady_clock::time_point lastFired;
};

class DvhRunLoop : public FObject, public IRunLoop {
public:
    std::mutex mtx;
    std::vector<FdEntry>    fds;
    std::vector<TimerEntry> timers;

    // ── IRunLoop ──────────────────────────────────────────────────────────
    tresult PLUGIN_API registerEventHandler(IEventHandler* h, FileDescriptor fd) override {
        if (!h) return kInvalidArgument;
        std::lock_guard<std::mutex> lk(mtx);
        fds.push_back({h, fd});
        fprintf(stderr, "[dart_vst_host] IRunLoop: registered fd=%d\n", fd);
        return kResultTrue;
    }

    tresult PLUGIN_API unregisterEventHandler(IEventHandler* h) override {
        std::lock_guard<std::mutex> lk(mtx);
        fds.erase(std::remove_if(fds.begin(), fds.end(),
            [h](const FdEntry& e){ return e.handler == h; }), fds.end());
        return kResultTrue;
    }

    tresult PLUGIN_API registerTimer(ITimerHandler* h, TimerInterval ms) override {
        if (!h) return kInvalidArgument;
        std::lock_guard<std::mutex> lk(mtx);
        timers.push_back({h, ms, std::chrono::steady_clock::now()});
        fprintf(stderr, "[dart_vst_host] IRunLoop: registered timer %llums\n",
                (unsigned long long)ms);
        return kResultTrue;
    }

    tresult PLUGIN_API unregisterTimer(ITimerHandler* h) override {
        std::lock_guard<std::mutex> lk(mtx);
        timers.erase(std::remove_if(timers.begin(), timers.end(),
            [h](const TimerEntry& e){ return e.handler == h; }), timers.end());
        return kResultTrue;
    }

    // Service all registered timers and readable fds. Called from the event thread.
    void tick() {
        auto now = std::chrono::steady_clock::now();

        std::vector<FdEntry>    fdsCopy;
        std::vector<TimerEntry*> dueTimers;
        {
            std::lock_guard<std::mutex> lk(mtx);
            fdsCopy = fds;
            for (auto& t : timers) {
                auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                    now - t.lastFired).count();
                if (elapsed >= (long long)t.intervalMs) {
                    dueTimers.push_back(&t);
                    t.lastFired = now;
                }
            }
        }

        // Poll registered fds with zero timeout (non-blocking).
        if (!fdsCopy.empty()) {
            std::vector<pollfd> pfds;
            pfds.reserve(fdsCopy.size());
            for (const auto& e : fdsCopy)
                pfds.push_back({e.fd, POLLIN, 0});
            ::poll(pfds.data(), (nfds_t)pfds.size(), 0);
            for (size_t i = 0; i < fdsCopy.size(); ++i)
                if (pfds[i].revents & POLLIN)
                    fdsCopy[i].handler->onFDIsSet(fdsCopy[i].fd);
        }

        // Fire due timers.
        for (auto* t : dueTimers)
            t->handler->onTimer();
    }

    // ── FUnknown ──────────────────────────────────────────────────────────
    REFCOUNT_METHODS(FObject)
    tresult PLUGIN_API queryInterface(const TUID iid, void** obj) override {
        QUERY_INTERFACE(iid, obj, FUnknown::iid, IRunLoop)
        QUERY_INTERFACE(iid, obj, IRunLoop::iid, IRunLoop)
        return FObject::queryInterface(iid, obj);
    }
};

// ─── Per-plugin editor state ──────────────────────────────────────────────────

struct EditorState {
    Display*    display{nullptr};
    Window      window{0};
    IPlugView*  plugView{nullptr};
    DvhRunLoop* runLoop{nullptr};
    std::thread eventThread;
    std::atomic<bool> running{false};
    // Set to true by the event thread after it has already called
    // plugView->removed() (i.e. on user-initiated X-button close).
    // _cleanupEditorBlocking checks this after joining to avoid double-removal.
    std::atomic<bool> viewAlreadyRemoved{false};
};

static std::mutex g_editorsMtx;
static std::map<DVH_Plugin, EditorState*> g_editors;

// Tracks ongoing background cleanups for programmatic closes so that
// dvh_open_editor can wait for removed() to finish before calling createView().
static std::mutex g_cleanupMtx;
static std::map<DVH_Plugin, std::shared_future<void>> g_cleanupFutures;

// ─── X11 + IRunLoop event loop ────────────────────────────────────────────────

static void editorEventLoop(EditorState* es, Atom wmDeleteAtom) {
    XEvent ev;
    while (es->running.load()) {
        // Service IRunLoop timers and fds.
        if (es->runLoop) es->runLoop->tick();

        // Process all pending X events.
        while (XPending(es->display)) {
            XNextEvent(es->display, &ev);

            if (ev.type == ClientMessage &&
                (Atom)ev.xclient.data.l[0] == wmDeleteAtom) {
                // User closed via X / title-bar. Hide the window immediately,
                // then break out so the code below can call removed() on this
                // thread (the correct GUI thread for JUCE-based plugins).
                XWithdrawWindow(es->display, es->window,
                                DefaultScreen(es->display));
                XFlush(es->display);
                es->running.store(false);
                fprintf(stderr, "[dart_vst_host] Editor closed by user\n");
                break; // exit inner X-event loop → fall through to removed()
            }

            if (ev.type == ConfigureNotify && es->plugView) {
                ViewRect r{0, 0, ev.xconfigure.width, ev.xconfigure.height};
                es->plugView->onSize(&r);
            }
        }

        if (!es->running.load()) break; // exit outer loop immediately

        // ~10 ms tick; IRunLoop timers are serviced at this rate.
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }

    // Always call removed() here, regardless of whether the loop exited due to
    // the X button or a programmatic dvh_close_editor() call.
    // We are on the plugin's dedicated event thread — the correct thread for
    // JUCE and other frameworks to perform GUI teardown without deadlocking.
    if (es->plugView) {
        es->plugView->setFrame(nullptr);
        es->plugView->removed();
        es->plugView->release();
        es->plugView = nullptr;
        es->viewAlreadyRemoved.store(true);
    }
    fprintf(stderr, "[dart_vst_host] Editor event loop exited\n");
}

// ─── Expose IRunLoop through the host context ─────────────────────────────────
// We store one DvhRunLoop per editor; the plugin queries for it via
// IPlugFrame or via the host context passed to the controller on initialize().
// VST3 plugins on Linux query IRunLoop from IPlugFrame when they call attached().

class DvhPlugFrame : public FObject, public IPlugFrame {
public:
    DvhRunLoop* runLoop{nullptr};
    Display*    display{nullptr};
    Window      window{0};

    tresult PLUGIN_API resizeView(IPlugView* view, ViewRect* r) override {
        if (!r || !display || !window) return kResultFalse;
        XResizeWindow(display, window, (unsigned)r->right, (unsigned)r->bottom);
        XFlush(display);
        return kResultTrue;
    }

    REFCOUNT_METHODS(FObject)
    tresult PLUGIN_API queryInterface(const TUID iid, void** obj) override {
        QUERY_INTERFACE(iid, obj, FUnknown::iid, IPlugFrame)
        QUERY_INTERFACE(iid, obj, IPlugFrame::iid, IPlugFrame)
        if (runLoop) {
            // Forward IRunLoop queries to our run loop implementation.
            if (FUnknownPrivate::iidEqual(iid, IRunLoop::iid)) {
                runLoop->addRef();
                *obj = static_cast<IRunLoop*>(runLoop);
                return kResultTrue;
            }
        }
        return FObject::queryInterface(iid, obj);
    }
};

// ─── Cleanup helper ───────────────────────────────────────────────────────────
// Performs the full blocking teardown of an EditorState.
// Must be called with g_editorsMtx NOT held.
// The entry MUST already have been removed from g_editors before calling.
// WARNING: plugView->removed() can block for JUCE-based plugins (Surge XT etc.)
// because JUCE posts cleanup messages to its SharedMessageThread. Always call
// this from a background thread (see dvh_close_editor) — never from the Dart
// main isolate, or the Flutter UI will freeze.
static void _cleanupEditorBlocking(EditorState* es) {
    // Wait for the X11 event loop thread to finish (at most ~10 ms).
    // After this join, viewAlreadyRemoved is safely readable (happens-before).
    if (es->eventThread.joinable()) es->eventThread.join();

    // If the user closed via the X button, the event thread already called
    // removed() on the plugin's GUI thread (the right thread for JUCE etc.).
    // Only call it here (from a background thread) for the programmatic-close
    // path, where the event loop exited via running=false without removing.
    if (!es->viewAlreadyRemoved.load() && es->plugView) {
        es->plugView->setFrame(nullptr);
        es->plugView->removed(); // may block (JUCE / Surge XT) — OK, background thread
        es->plugView->release();
        es->plugView = nullptr;
    }
    if (es->runLoop) { es->runLoop->release(); es->runLoop = nullptr; }
    if (es->display && es->window) {
        XDestroyWindow(es->display, es->window);
        XFlush(es->display);
    }
    if (es->display) { XCloseDisplay(es->display); es->display = nullptr; }
    delete es;
}

// Used by dvh_open_editor for stale entries (event thread already exited,
// and if the user closed via X button, plugView is already null → fast path).
static void _cleanupEditor(EditorState* es) {
    _cleanupEditorBlocking(es);
}

// ─── Public C API ─────────────────────────────────────────────────────────────

extern "C" {

DVH_API intptr_t dvh_open_editor(DVH_Plugin p, const char* title) {
    if (!p) return 0;

    {
        EditorState* staleEs = nullptr;
        {
            std::lock_guard<std::mutex> lk(g_editorsMtx);
            auto it = g_editors.find(p);
            if (it != g_editors.end()) {
                auto* es = it->second;
                if (es->running.load()) {
                    // Already open — bring to front.
                    XRaiseWindow(es->display, es->window);
                    XFlush(es->display);
                    fprintf(stderr, "[dart_vst_host] Editor already open — raising\n");
                    return (intptr_t)es->window;
                }
                // Stale entry (user closed): erase under lock, clean up after.
                staleEs = es;
                g_editors.erase(it);
            }
        } // lock released here
        if (staleEs) {
            _cleanupEditor(staleEs);
            fprintf(stderr, "[dart_vst_host] Stale editor cleaned up — reopening\n");
        }
    }

    auto* ps = reinterpret_cast<DVH_PluginState*>(p);
    if (!ps->controller) {
        fprintf(stderr, "[dart_vst_host] No IEditController\n");
        return 0;
    }

    // Wait for any previous programmatic close to complete before calling
    // createView() again. removed() must finish before createView() is called,
    // or the plugin will be in an inconsistent state and return null / crash.
    // In practice the event thread exits within ≤10 ms of running=false, then
    // calls removed() — so this wait is typically very short.
    {
        std::shared_future<void> pending;
        {
            std::lock_guard<std::mutex> lk(g_cleanupMtx);
            auto it = g_cleanupFutures.find(p);
            if (it != g_cleanupFutures.end()) pending = it->second;
        }
        if (pending.valid()) {
            fprintf(stderr, "[dart_vst_host] Waiting for previous editor cleanup…\n");
            pending.wait();
            // Safe to erase now: the async thread has finished, so the shared
            // state destructor will not block (no self-join risk).
            std::lock_guard<std::mutex> lk(g_cleanupMtx);
            g_cleanupFutures.erase(p);
            fprintf(stderr, "[dart_vst_host] Previous cleanup done — proceeding\n");
        }
    }

    {
        const char* disp = getenv("DISPLAY");
        const char* wayl = getenv("WAYLAND_DISPLAY");
        fprintf(stderr, "[dart_vst_host] DISPLAY=%s WAYLAND_DISPLAY=%s\n",
                disp ? disp : "(null)", wayl ? wayl : "(null)");
    }
    fprintf(stderr, "[dart_vst_host] singleComponent=%d paramCount=%d, calling createView…\n",
            (int)ps->singleComponent,
            ps->controller->getParameterCount());

    // Ensure X11 is usable from this thread before asking the plugin to create its view.
    XInitThreads();
    {
        Display* testDpy = XOpenDisplay(nullptr);
        if (!testDpy) {
            fprintf(stderr, "[dart_vst_host] XOpenDisplay test failed — DISPLAY not available\n");
            return 0;
        }
        XCloseDisplay(testDpy);
    }

    IPlugView* plugView = ps->controller->createView(ViewType::kEditor);
    if (!plugView) {
        fprintf(stderr, "[dart_vst_host] createView(kEditor) returned null\n");
        return 0;
    }

    if (plugView->isPlatformTypeSupported(kPlatformTypeX11EmbedWindowID) != kResultTrue) {
        fprintf(stderr, "[dart_vst_host] X11EmbedWindowID not supported\n");
        plugView->release();
        return 0;
    }

    Display* dpy = XOpenDisplay(nullptr);
    if (!dpy) {
        fprintf(stderr, "[dart_vst_host] XOpenDisplay failed\n");
        plugView->release();
        return 0;
    }

    ViewRect rect{};
    plugView->getSize(&rect);
    int w = rect.right  - rect.left; if (w <= 0) w = 800;
    int h = rect.bottom - rect.top;  if (h <= 0) h = 600;

    int screen = DefaultScreen(dpy);
    Window win = XCreateSimpleWindow(dpy, DefaultRootWindow(dpy),
        100, 100, (unsigned)w, (unsigned)h, 0,
        BlackPixel(dpy, screen), BlackPixel(dpy, screen));

    const char* wt = (title && title[0]) ? title : "Plugin Editor";
    XStoreName(dpy, win, wt);
    Atom wmDelete = XInternAtom(dpy, "WM_DELETE_WINDOW", False);
    XSetWMProtocols(dpy, win, &wmDelete, 1);
    XSelectInput(dpy, win, ExposureMask | StructureNotifyMask);
    XMapWindow(dpy, win);
    XFlush(dpy);

    // Build IRunLoop + IPlugFrame so the plugin can register timers/fds.
    auto* runLoop   = new DvhRunLoop();
    auto* plugFrame = new DvhPlugFrame();
    plugFrame->runLoop  = runLoop;
    plugFrame->display  = dpy;
    plugFrame->window   = win;
    plugView->setFrame(plugFrame);

    tresult res = plugView->attached((void*)(intptr_t)win, kPlatformTypeX11EmbedWindowID);
    if (res != kResultTrue) {
        fprintf(stderr, "[dart_vst_host] IPlugView::attached() failed (%d)\n", (int)res);
        plugView->setFrame(nullptr);
        plugView->release();
        plugFrame->release();
        runLoop->release();
        XDestroyWindow(dpy, win);
        XCloseDisplay(dpy);
        return 0;
    }

    // Re-read size after attach (plugin may have adjusted it).
    if (plugView->getSize(&rect) == kResultTrue) {
        int pw = rect.right - rect.left, ph = rect.bottom - rect.top;
        if (pw > 0 && ph > 0 && (pw != w || ph != h))
            XResizeWindow(dpy, win, (unsigned)pw, (unsigned)ph);
    }
    XFlush(dpy);

    fprintf(stderr, "[dart_vst_host] Editor window opened (xid=%lu %dx%d)\n",
            (unsigned long)win, w, h);

    auto* es       = new EditorState();
    es->display    = dpy;
    es->window     = win;
    es->plugView   = plugView;
    es->runLoop    = runLoop;
    es->running.store(true);
    es->eventThread = std::thread(editorEventLoop, es, wmDelete);

    {
        std::lock_guard<std::mutex> lk(g_editorsMtx);
        g_editors[p] = es;
    }

    plugFrame->release(); // plugView holds it via setFrame
    return (intptr_t)win;
}

DVH_API void dvh_close_editor(DVH_Plugin p) {
    EditorState* es = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_editorsMtx);
        auto it = g_editors.find(p);
        if (it == g_editors.end()) return;
        es = it->second;
        g_editors.erase(it); // dvh_editor_is_open returns 0 from this point
    }

    // Hide the window immediately so the user sees it disappear at once.
    if (es->display && es->window) {
        XWithdrawWindow(es->display, es->window, DefaultScreen(es->display));
        XFlush(es->display);
    }

    // Signal the event loop to stop. It will exit its current tick (≤10 ms),
    // call plugView->removed() on the event thread, then terminate.
    // removed() is always called from the event thread — the plugin's own GUI
    // thread — so JUCE-based plugins (Surge XT) never deadlock.
    es->running.store(false);

    // Launch a background thread that joins the event thread and cleans up X11.
    // Store the future so dvh_open_editor can wait for it before calling
    // createView() again, preventing a race between removed() and createView().
    // IMPORTANT: do NOT call g_cleanupFutures.erase(p) from inside this lambda.
    // The destructor of the last std::shared_future referring to a state from
    // std::async blocks until the async thread finishes. If called from within
    // the async thread itself it tries to join itself → EDEADLK → std::terminate.
    // The entry is erased by dvh_open_editor after a successful wait(), at which
    // point the thread is guaranteed to have already finished.
    auto future = std::async(std::launch::async, [es]() {
        _cleanupEditorBlocking(es); // joins event thread, then X11 teardown
        fprintf(stderr, "[dart_vst_host] Editor closed (programmatic)\n");
    }).share();
    {
        std::lock_guard<std::mutex> lk(g_cleanupMtx);
        g_cleanupFutures[p] = future;
    }
}

DVH_API int32_t dvh_editor_is_open(DVH_Plugin p) {
    std::lock_guard<std::mutex> lk(g_editorsMtx);
    auto it = g_editors.find(p);
    if (it == g_editors.end()) return 0;
    // Returns 0 if the user closed the window (running=false) so Flutter can
    // detect external window closure and update the button state.
    return it->second->running.load() ? 1 : 0;
}

} // extern "C"

#else // !__linux__

#include "dart_vst_host.h"
extern "C" {
    intptr_t dvh_open_editor(DVH_Plugin, const char*) { return 0; }
    void     dvh_close_editor(DVH_Plugin) {}
    int32_t  dvh_editor_is_open(DVH_Plugin) { return 0; }
}

#endif
