import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    // FluidSynth pulls in glib, whose g_slice slab allocator bypasses the
    // system malloc zone and corrupts Swift/ObjC heap metadata (causing
    // EXC_BAD_ACCESS crashes). Setting G_SLICE=always-malloc before dyld
    // loads libglib forces glib to use the standard allocator instead.
    // Must run before Flutter's Dart engine starts and before
    // libaudio_input.dylib is opened via dlopen.
    setenv("G_SLICE", "always-malloc", 1)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
