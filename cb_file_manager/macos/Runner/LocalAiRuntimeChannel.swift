import Cocoa
import FlutterMacOS

enum LocalAiRuntimeChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "cb_file_manager/local_ai", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "getLlamaServerPath" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard #available(macOS 13.3, *) else {
        result(FlutterError(code: "LLAMA_OS_UNSUPPORTED",
          message: "The bundled local GGUF runtime requires macOS 13.3 or later.", details: nil))
        return
      }
      #if arch(arm64)
      let arch = "arm64"
      #else
      let arch = "x86_64"
      #endif
      let server = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/llama/\(arch)/llama-server")
      guard FileManager.default.isExecutableFile(atPath: server.path) else {
        result(FlutterError(code: "LLAMA_RUNTIME_MISSING",
          message: "macOS local AI runtime missing. Rebuild and reinstall the app.", details: server.path))
        return
      }
      result(server.path)
    }
  }
}
