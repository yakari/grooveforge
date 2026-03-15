import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register the theremin camera distance plugin.
    // registrar(forPlugin:) returns a non-optional FlutterPluginRegistrar on
    // current FlutterMacOS SDK, so no optional binding is needed.
    let thereminRegistrar = flutterViewController.registrar(forPlugin: "ThereminCameraPlugin")
    ThereminCameraPlugin.register(with: thereminRegistrar)

    super.awakeFromNib()
  }
}
