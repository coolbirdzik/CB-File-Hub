// Pure native unit test: no filesystem changes or elevation prompts.
#include "../file_operations_plugin.cpp"

#include <iostream>
#include <stdexcept>

void Check(bool condition, const char *message) {
  if (!condition) throw std::runtime_error(message);
}

int main() {
  try {
    flutter::EncodableList errors;
    const std::wstring root = L"C:\\approved\\cache";
    auto sink = Microsoft::WRL::Make<file_operations_plugin::DeleteProgressSink>(
        root, &errors);
    // Child errors must retain the approved root and normalize Shell security
    // HRESULTs to the same Win32 code used by direct permanent deletion.
    for (const HRESULT hr : {E_ACCESSDENIED, COPYENGINE_E_ACCESS_DENIED_SRC,
                             COPYENGINE_E_ACCESS_DENIED_DEST}) {
      sink->PostDeleteItem(0, nullptr, hr, nullptr);
    }
    sink->PostDeleteItem(0, nullptr, S_OK, nullptr);
    Check(errors.size() == 3, "Success must not produce a delete error");
    for (const auto &entry : errors) {
      const auto &error = std::get<flutter::EncodableMap>(entry);
      Check(std::get<std::string>(error.at(flutter::EncodableValue("source"))) ==
                "C:\\approved\\cache", "Error broadened the approved target");
      Check(std::get<int32_t>(error.at(flutter::EncodableValue("errorCode"))) ==
                ERROR_ACCESS_DENIED, "Security HRESULT did not normalize to 5");
    }
    errors.clear();
    sink->PostDeleteItem(0, nullptr, HRESULT_FROM_WIN32(ERROR_SHARING_VIOLATION), nullptr);
    const auto &locked = std::get<flutter::EncodableMap>(errors.front());
    Check(std::get<int32_t>(locked.at(flutter::EncodableValue("errorCode"))) ==
              ERROR_SHARING_VIOLATION, "Lock failure was treated as permission denial");
    std::cout << "PASS: delete error mapping and approved target scope\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
}
