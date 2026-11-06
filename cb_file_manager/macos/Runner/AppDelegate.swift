import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

@main
class AppDelegate: FlutterAppDelegate {
  override func application(_ application: NSApplication, open urls: [URL]) {
    var remaining: [URL] = []
    var folders: [String] = []
    for url in urls {
      let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
      if url.isFileURL && values?.isDirectory != false && values?.isPackage != true {
        folders.append(url.path)
      } else {
        remaining.append(url)
      }
    }
    if !folders.isEmpty { FolderOpenChannel.receive(folders) }
    if !remaining.isEmpty { super.application(application, open: remaining) }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

/// AppKit queues launches until Dart has created the tab manager.
enum FolderOpenChannel {
  private static var channel: FlutterMethodChannel?
  private static var pending: [String] = []
  private static var ready = false

  static func register(with messenger: FlutterBinaryMessenger) {
    let bridge = FlutterMethodChannel(name: "cb_file_manager/folder_open", binaryMessenger: messenger)
    channel = bridge
    bridge.setMethodCallHandler { call, result in
      if call.method == "ready" {
        ready = true
        let queued = pending
        pending.removeAll()
        result(queued)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func receive(_ paths: [String]) {
    if ready, let channel = channel {
      channel.invokeMethod("openFolders", arguments: paths)
    } else {
      pending.append(contentsOf: paths)
    }
    NSApp.activate(ignoringOtherApps: true)
  }
}

enum FolderDefaults {
  private static let backupKey = "cb.previousFolderApplication.v1"
  private static var changing = false

  private static func current() -> URL? {
    NSWorkspace.shared.urlForApplication(toOpen: FileManager.default.homeDirectoryForCurrentUser)
  }

  private static func isOurs(_ url: URL?) -> Bool {
    guard let url = url, let identifier = Bundle(url: url)?.bundleIdentifier,
          let ownIdentifier = Bundle.main.bundleIdentifier else { return false }
    return identifier == ownIdentifier
  }

  static func status() -> [String: Any] {
    ["enabled": isOurs(current()),
     "canRestore": UserDefaults.standard.string(forKey: backupKey) != nil,
     "partial": false]
  }

  static func change(restore: Bool, result: @escaping FlutterResult) {
    guard !changing else {
      result(FlutterError(code: "FOLDER_DEFAULT_BUSY", message: "Another change is in progress.", details: nil))
      return
    }
    let defaults = UserDefaults.standard
    let selected = current()
    let target: URL
    if restore {
      guard let previous = defaults.string(forKey: backupKey), let url = URL(string: previous) else {
        result(nil)
        return
      }
      // Do not overwrite a choice made later in another application.
      guard isOurs(selected) else {
        defaults.removeObject(forKey: backupKey)
        result(nil)
        return
      }
      target = url
    } else {
      if isOurs(selected) { result(nil); return }
      guard defaults.string(forKey: backupKey) == nil else {
        result(FlutterError(code: "FOLDER_DEFAULT_BACKUP", message: "Restore the previous registration first.", details: nil))
        return
      }
      guard let previous = selected else {
        result(FlutterError(code: "FOLDER_DEFAULT_MISSING", message: "The previous folder application is unavailable.", details: nil))
        return
      }
      defaults.set(previous.absoluteString, forKey: backupKey)
      defaults.synchronize()
      target = Bundle.main.bundleURL
    }
    guard FileManager.default.fileExists(atPath: target.path) else {
      result(FlutterError(code: "FOLDER_DEFAULT_MISSING", message: "The folder application is no longer installed.", details: nil))
      return
    }
    changing = true
    NSWorkspace.shared.setDefaultApplication(at: target, toOpen: .folder) { error in
      DispatchQueue.main.async {
        changing = false
        if let error = error {
          result(FlutterError(code: "FOLDER_DEFAULT_FAILED", message: error.localizedDescription, details: nil))
        } else if current()?.standardizedFileURL != target.standardizedFileURL {
          result(FlutterError(code: "FOLDER_DEFAULT_FAILED", message: "macOS did not select the requested application.", details: nil))
        } else {
          if restore { defaults.removeObject(forKey: backupKey) }
          result(nil)
        }
      }
    }
  }
}
