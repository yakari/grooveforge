import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {

  override func applicationWillFinishLaunching(_ notification: Notification) {
    // glib (loaded transitively by FluidSynth via libaudio_input.dylib) uses a
    // slab allocator called g_slice that carves raw VM pages from the OS,
    // bypassing the system malloc zone.  Swift's conformance cache and ObjC
    // metadata tables live in the same zone, so a g_slice arena that overlaps
    // them corrupts pointers and crashes in swift_conformsToProtocol /
    // shared_preferences_foundation.
    //
    // G_SLICE=always-malloc makes g_slice delegate every allocation to the
    // system malloc/free, eliminating the conflict entirely.
    //
    // This MUST be set here — before any Dart code runs — because glib calls
    // g_slice_init() (which reads G_SLICE) the very first time g_slice_alloc()
    // is called.  If we waited until keyboard_init() in Dart, libglib would
    // already be loaded and g_slice_init() would have run.
    setenv("G_SLICE", "always-malloc", 1)
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
