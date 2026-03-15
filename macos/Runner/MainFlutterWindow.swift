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
    if let registrar = flutterViewController.registrar(forPlugin: "ThereminCameraPlugin") {
      ThereminCameraPlugin.register(with: registrar)
    }

    super.awakeFromNib()
  }
}
