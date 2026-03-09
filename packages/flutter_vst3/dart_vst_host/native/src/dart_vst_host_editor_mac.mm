// macOS editor support for dart_vst_host using Cocoa.
// Opens the plugin's native editor in a standalone NSWindow.

#ifdef __APPLE__

#import <Cocoa/Cocoa.h>
#include "dart_vst_host.h"
#include "dart_vst_host_internal.h"

#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"

#include <map>
#include <mutex>
#include <string>
#include <atomic>

using namespace Steinberg;
using namespace Steinberg::Vst;

// ─── NSWindow Delegate ───────────────────────────────────────────────────────

@interface DVHWindowDelegate : NSObject <NSWindowDelegate>
@property (nonatomic, assign) DVH_Plugin plugin;
@end

@implementation DVHWindowDelegate
- (void)windowWillClose:(NSNotification *)notification {
    dvh_mac_close_editor(self.plugin);
}
@end

// ─── IPlugFrame implementation ────────────────────────────────────────────────

class DvhPlugFrameMac : public IPlugFrame {
public:
    NSWindow* window{nullptr};
    std::atomic<int32_t> refCount{1};

    DvhPlugFrameMac() {}
    virtual ~DvhPlugFrameMac() {}

    // FUnknown implementation
    tresult PLUGIN_API queryInterface(const TUID _iid, void** obj) override {
        if (FUnknownPrivate::iidEqual(_iid, IPlugFrame::iid) ||
            FUnknownPrivate::iidEqual(_iid, FUnknown::iid)) {
            addRef();
            *obj = this;
            return kResultOk;
        }
        *obj = nullptr;
        return kResultFalse;
    }
    uint32 PLUGIN_API addRef() override { return ++refCount; }
    uint32 PLUGIN_API release() override {
        uint32 r = --refCount;
        if (r == 0) delete this;
        return r;
    }

    tresult PLUGIN_API resizeView(IPlugView* view, ViewRect* r) override {
        if (!r || !window) return kResultFalse;
        
        // Capture safe pointer and values for the async block
        NSWindow* win = window;
        float newW = (float)(r->right - r->left);
        float newH = (float)(r->bottom - r->top);

        dispatch_async(dispatch_get_main_queue(), ^{
            NSRect frame = [win frame];
            NSRect contentRect = [win contentRectForFrameRect:frame];
            
            NSRect newContentRect = NSMakeRect(contentRect.origin.x, contentRect.origin.y, newW, newH);
            NSRect newFrame = [win frameRectForContentRect:newContentRect];
            
            // Adjust origin because macOS coordinates start from bottom
            newFrame.origin.y -= (newFrame.size.height - frame.size.height);
            
            [win setFrame:newFrame display:YES animate:YES];
        });
        return kResultTrue;
    }
};

// ─── Per-plugin editor state ──────────────────────────────────────────────────

struct EditorState {
    NSWindow*           window{nullptr};
    DVHWindowDelegate*  delegate{nullptr};
    IPlugView*          plugView{nullptr};
    DvhPlugFrameMac*    plugFrame{nullptr};
};

static std::mutex g_editorsMtx;
static std::map<DVH_Plugin, EditorState*> g_editors;

extern "C" {

DVH_API intptr_t dvh_mac_open_editor(DVH_Plugin p, const char* title) {
    if (!p) return 0;

    std::string safeTitle = title ? title : "Plugin Editor";

    fprintf(stderr, "[dart_vst_host] dvh_mac_open_editor(plugin=%p, title=%s) called\n", p, safeTitle.c_str());
    fflush(stderr);

    {
        std::lock_guard<std::mutex> lk(g_editorsMtx);
        if (g_editors.count(p)) {
            NSWindow* win = g_editors[p]->window;
            dispatch_async(dispatch_get_main_queue(), ^{
                [win makeKeyAndOrderFront:nil];
            });
            return (intptr_t)win;
        }
    }

    auto* ps = reinterpret_cast<DVH_PluginState*>(p);
    if (!ps->controller) {
        fprintf(stderr, "[dart_vst_host] ERROR: No controller for plugin %p\n", p);
        return 0;
    }

    __block IPlugView* plugView = nullptr;
    if ([NSThread isMainThread]) {
        plugView = ps->controller->createView(ViewType::kEditor);
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            plugView = ps->controller->createView(ViewType::kEditor);
        });
    }

    if (!plugView) {
        fprintf(stderr, "[dart_vst_host] ERROR: createView(kEditor) failed for plugin %p\n", p);
        return 0;
    }

    if (plugView->isPlatformTypeSupported(kPlatformTypeNSView) != kResultTrue) {
        fprintf(stderr, "[dart_vst_host] ERROR: kPlatformTypeNSView not supported by plugin %p\n", p);
        plugView->release();
        return 0;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        ViewRect rect{};
        plugView->getSize(&rect);
        int w = rect.right - rect.left; if (w <= 0) w = 800;
        int h = rect.bottom - rect.top; if (h <= 0) h = 600;

        fprintf(stderr, "[dart_vst_host] Opening NSWindow %dx%d...\n", w, h);
        fflush(stderr);

        NSRect frame = NSMakeRect(200, 200, (CGFloat)w, (CGFloat)h);
        NSWindow* window = [[NSWindow alloc] initWithContentRect:frame
                                                     styleMask:(NSWindowStyleMaskTitled | 
                                                                NSWindowStyleMaskClosable | 
                                                                NSWindowStyleMaskResizable)
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO];
        
        NSString* nsTitle = [NSString stringWithUTF8String:safeTitle.c_str()];
        [window setTitle:nsTitle];
        [window setReleasedWhenClosed:NO];
        
        DVHWindowDelegate* delegate = [[DVHWindowDelegate alloc] init];
        delegate.plugin = p;
        [window setDelegate:delegate];

        DvhPlugFrameMac* plugFrame = new DvhPlugFrameMac();
        plugFrame->window = window;
        plugView->setFrame(plugFrame);

        NSView* contentView = [window contentView];
        tresult res = plugView->attached((__bridge void*)contentView, kPlatformTypeNSView);
        
        if (res != kResultTrue) {
            fprintf(stderr, "[dart_vst_host] ERROR: IPlugView::attached() failed with error %d\n", res);
            plugView->setFrame(nullptr);
            plugView->release();
            plugFrame->release();
            [window close];
            return;
        }

        [window makeKeyAndOrderFront:nil];
        fprintf(stderr, "[dart_vst_host] Editor window opened and attached successfully\n");

        EditorState* es = new EditorState();
        es->window = window;
        es->delegate = delegate;
        es->plugView = plugView;
        es->plugFrame = plugFrame;
        
        {
            std::lock_guard<std::mutex> lk(g_editorsMtx);
            g_editors[p] = es;
        }
    });

    return 1; 
}

DVH_API void dvh_mac_close_editor(DVH_Plugin p) {
    if (!p) return;
    EditorState* es = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_editorsMtx);
        auto it = g_editors.find(p);
        if (it == g_editors.end()) return;
        es = it->second;
        g_editors.erase(it);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (es->plugView) {
            es->plugView->setFrame(nullptr);
            es->plugView->removed();
            es->plugView->release();
        }
        if (es->plugFrame) {
            es->plugFrame->release();
        }
        [es->window close];
        delete es;
        fprintf(stderr, "[dart_vst_host] Editor window closed for plugin %p\n", p);
    });
}

DVH_API int32_t dvh_mac_editor_is_open(DVH_Plugin p) {
    if (!p) return 0;
    std::lock_guard<std::mutex> lk(g_editorsMtx);
    return g_editors.count(p) ? 1 : 0;
}

// Keep old names as stubs for compatibility
DVH_API intptr_t dvh_open_editor(DVH_Plugin p, const char* /*title*/) {
    fprintf(stderr, "[dart_vst_host] dvh_open_editor called on macOS (IGNORING: use dvh_mac_open_editor)\n");
    return 0;
}
DVH_API void     dvh_close_editor(DVH_Plugin p) { (void)p; }
DVH_API int32_t  dvh_editor_is_open(DVH_Plugin p) { (void)p; return 0; }

} // extern "C"

#endif // __APPLE__
