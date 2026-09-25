import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // The title bar is hidden and Flutter draws its own tab bar in its place, so
  // the traffic lights are moved to sit vertically centred in that bar. Zero
  // height keeps AppKit's native layout (e.g. windows without a tab bar).
  private var trafficLightBarHeight: CGFloat = 0
  private var trafficLightLeading: CGFloat = 0

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "cb_file_manager/macos_window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "setTrafficLightLayout":
        let args = call.arguments as? [String: Any]
        self.trafficLightBarHeight = CGFloat(
          (args?["barHeight"] as? NSNumber)?.doubleValue ?? 0)
        self.trafficLightLeading = CGFloat(
          (args?["leading"] as? NSNumber)?.doubleValue ?? 0)
        // Report where the buttons end so Flutter can reserve exactly that.
        result(self.layoutTrafficLights())
      case "showFullDiskAccessHelper":
        let args = call.arguments as? [String: Any]
        FullDiskAccessHelperPanel.show(
          title: args?["title"] as? String ?? "",
          message: args?["message"] as? String ?? "")
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // AppKit lays the title bar out again on these, dropping the custom position.
    for name in [
      NSWindow.didResizeNotification,
      NSWindow.didEndLiveResizeNotification,
      NSWindow.didExitFullScreenNotification,
      NSWindow.didBecomeKeyNotification,
      NSWindow.didResignKeyNotification,
    ] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(windowLayoutChanged(_:)), name: name, object: self)
    }

    super.awakeFromNib()
  }

  @objc private func windowLayoutChanged(_ notification: Notification) {
    layoutTrafficLights()
  }

  /// Returns the zoom button's right edge in window points, or nil when the
  /// native layout is in charge.
  @discardableResult
  private func layoutTrafficLights() -> Double? {
    guard trafficLightBarHeight > 0,
      !styleMask.contains(.fullScreen),
      let close = standardWindowButton(.closeButton),
      let miniaturize = standardWindowButton(.miniaturizeButton),
      let zoom = standardWindowButton(.zoomButton),
      let titlebarView = close.superview,
      let containerView = titlebarView.superview
    else { return nil }

    var containerFrame = containerView.frame
    containerFrame.size.height = trafficLightBarHeight
    containerFrame.origin.y = frame.height - trafficLightBarHeight
    containerView.frame = containerFrame

    let spacing = miniaturize.frame.minX - close.frame.minX
    for (index, button) in [close, miniaturize, zoom].enumerated() {
      button.setFrameOrigin(
        NSPoint(
          x: trafficLightLeading + CGFloat(index) * spacing,
          y: (titlebarView.bounds.height - button.frame.height) / 2))
    }
    return Double(zoom.convert(zoom.bounds, to: nil).maxX)
  }
}

/// Floating card shown beside System Settings while the user grants Full Disk
/// Access. macOS lets no app add itself to that list, so the card holds the
/// app's icon for the user to drag in; macOS then asks them to approve it with
/// Touch ID or their password. It follows the Settings window and closes once
/// access is granted or Settings quits.
final class FullDiskAccessHelperPanel: NSPanel {
  private static var current: FullDiskAccessHelperPanel?
  private static let settingsBundleId = "com.apple.systempreferences"
  private static let size = NSSize(width: 300, height: 190)

  private var watchTimer: Timer?
  private var sawSettings = false
  private var ticks = 0

  static func show(title: String, message: String) {
    current?.close()
    let panel = FullDiskAccessHelperPanel(title: title, message: message)
    current = panel
    panel.startWatching()
  }

  private init(title: String, message: String) {
    super.init(
      contentRect: NSRect(origin: .zero, size: Self.size),
      styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered, defer: false)
    isFloatingPanel = true
    level = .floating
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = true
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let background = NSVisualEffectView()
    background.material = .popover
    background.state = .active

    let icon = AppIconDragView()
    icon.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      icon.widthAnchor.constraint(equalToConstant: 64),
      icon.heightAnchor.constraint(equalToConstant: 64),
    ])

    let titleLabel = NSTextField(wrappingLabelWithString: title)
    titleLabel.font = .boldSystemFont(ofSize: 13)
    titleLabel.alignment = .center
    let messageLabel = NSTextField(wrappingLabelWithString: message)
    messageLabel.font = .systemFont(ofSize: 11)
    messageLabel.textColor = .secondaryLabelColor
    messageLabel.alignment = .center

    let stack = NSStackView(views: [icon, titleLabel, messageLabel])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    background.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 28),
      titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
      messageLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
    contentView = background
  }

  override func close() {
    watchTimer?.invalidate()
    watchTimer = nil
    if Self.current === self { Self.current = nil }
    super.close()
  }

  private func startWatching() {
    watchTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
      self?.tick()
    }
    tick()
  }

  private func tick() {
    ticks += 1
    if Self.hasFullDiskAccess() {
      close()
      return
    }
    guard
      let settings = NSRunningApplication.runningApplications(
        withBundleIdentifier: Self.settingsBundleId
      ).first
    else {
      // Settings is still launching, or the user quit it.
      if sawSettings || ticks > 25 { close() }
      return
    }
    sawSettings = true
    guard let settingsFrame = Self.mainWindowFrame(of: settings.processIdentifier) else {
      return
    }
    setFrameOrigin(origin(beside: settingsFrame))
    if !isVisible { orderFrontRegardless() }
  }

  /// Right of the Settings window, else left of it, else over its sidebar.
  private func origin(beside settings: NSRect) -> NSPoint {
    let screen =
      NSScreen.screens.first { $0.frame.intersects(settings) }?.visibleFrame
      ?? NSScreen.main?.visibleFrame ?? settings
    let y = min(max(settings.midY - Self.size.height / 2, screen.minY), screen.maxY - Self.size.height)
    if settings.maxX + 12 + Self.size.width <= screen.maxX {
      return NSPoint(x: settings.maxX + 12, y: y)
    }
    if settings.minX - 12 - Self.size.width >= screen.minX {
      return NSPoint(x: settings.minX - 12 - Self.size.width, y: y)
    }
    return NSPoint(x: settings.minX + 12, y: settings.minY + 12)
  }

  /// The Settings window's frame in Cocoa screen coordinates. Window bounds
  /// are readable without Screen Recording permission (titles are not).
  private static func mainWindowFrame(of pid: pid_t) -> NSRect? {
    guard
      let infos = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]],
      let primaryHeight = NSScreen.screens.first?.frame.height
    else { return nil }
    for info in infos {
      guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
        (info[kCGWindowLayer as String] as? Int) == 0,
        let bounds = info[kCGWindowBounds as String] as? NSDictionary,
        let rect = CGRect(dictionaryRepresentation: bounds),
        rect.width > 200
      else { continue }
      // CoreGraphics measures from the top of the primary screen, Cocoa from the bottom.
      return NSRect(
        x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
    return nil
  }

  /// Same probe as PermissionStateService on the Dart side.
  private static func hasFullDiskAccess() -> Bool {
    let home = NSHomeDirectory()
    for path in [
      "\(home)/Library/Application Support/com.apple.TCC/TCC.db",
      "/Library/Application Support/com.apple.TCC/TCC.db",
      "\(home)/Library/Safari/Bookmarks.plist",
    ] where FileManager.default.fileExists(atPath: path) {
      if let handle = FileHandle(forReadingAtPath: path) {
        handle.closeFile()
        return true
      }
    }
    return false
  }
}

/// The app icon, draggable as the app bundle's file URL, which is what the
/// Full Disk Access list accepts.
private final class AppIconDragView: NSView, NSDraggingSource {
  private let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

  override func draw(_ dirtyRect: NSRect) {
    icon.draw(in: bounds)
  }

  // The panel never activates the app, so the first click must start the drag.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .openHand)
  }

  override func mouseDragged(with event: NSEvent) {
    let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
    item.setDraggingFrame(bounds, contents: icon)
    beginDraggingSession(with: [item], event: event, source: self)
  }

  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    [.copy, .link, .generic]
  }
}
