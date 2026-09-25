#include "store_update_plugin.h"

#include <unknwn.h>

#include <appmodel.h>
#include <flutter/standard_method_codec.h>
#include <shobjidl_core.h>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Services.Store.h>
#include <winrt/base.h>

#include <sstream>
#include <string>
#include <thread>

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Services::Store::StoreContext;
using winrt::Windows::Services::Store::StorePackageUpdate;
using winrt::Windows::Services::Store::StorePackageUpdateState;
using winrt::Windows::Services::Store::StorePackageUpdateStatus;

namespace {

using MethodResultPtr =
    std::unique_ptr<flutter::MethodResult<EncodableValue>>;

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr,
                                       0, nullptr, nullptr);
  std::string output(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), output.data(), size,
                      nullptr, nullptr);
  return output;
}

bool IsPackaged() {
  UINT32 length = 0;
  return GetCurrentPackageFullName(&length, nullptr) !=
         APPMODEL_ERROR_NO_PACKAGE;
}

// A desktop app must parent Store dialogs to its own window.
StoreContext CreateContext(HWND owner) {
  StoreContext context = StoreContext::GetDefault();
  if (owner != nullptr) {
    auto initialize = context.as<::IInitializeWithWindow>();
    winrt::check_hresult(initialize->Initialize(owner));
  }
  return context;
}

const char* StateName(StorePackageUpdateState state) {
  switch (state) {
    case StorePackageUpdateState::Pending:
      return "pending";
    case StorePackageUpdateState::Downloading:
      return "downloading";
    case StorePackageUpdateState::Deploying:
      return "deploying";
    case StorePackageUpdateState::Completed:
      return "completed";
    case StorePackageUpdateState::Canceled:
      return "canceled";
    case StorePackageUpdateState::ErrorLowBattery:
      return "errorLowBattery";
    case StorePackageUpdateState::ErrorWiFiRecommended:
      return "errorWiFiRecommended";
    case StorePackageUpdateState::ErrorWiFiRequired:
      return "errorWiFiRequired";
    default:
      return "otherError";
  }
}

// Runs [work] on an MTA thread: blocking on WinRT async operations (.get())
// is not allowed on the platform (STA) thread.
template <typename Work>
void RunInBackground(MethodResultPtr result, Work work) {
  auto* result_pointer = result.release();
  std::thread([result_pointer, work]() {
    MethodResultPtr thread_result(result_pointer);
    try {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
      thread_result->Success(work());
    } catch (const winrt::hresult_error& error) {
      thread_result->Error("STORE_ERROR",
                           WideToUtf8(error.message().c_str()));
    } catch (...) {
      thread_result->Error("STORE_ERROR", "Unexpected Store API failure");
    }
  }).detach();
}

}  // namespace

void StoreUpdatePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "cb_file_manager/store_update",
      &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<StoreUpdatePlugin>(registrar);
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });
  registrar->AddPlugin(std::move(plugin));
}

StoreUpdatePlugin::StoreUpdatePlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

StoreUpdatePlugin::~StoreUpdatePlugin() = default;

HWND StoreUpdatePlugin::OwnerWindow() const {
  if (registrar_ == nullptr || registrar_->GetView() == nullptr) {
    return nullptr;
  }
  HWND view = registrar_->GetView()->GetNativeWindow();
  return view == nullptr ? nullptr : GetAncestor(view, GA_ROOT);
}

void StoreUpdatePlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    MethodResultPtr result) {
  const std::string& method = method_call.method_name();

  if (method == "isPackaged") {
    result->Success(EncodableValue(IsPackaged()));
    return;
  }
  if (method == "getProgress") {
    result->Success(EncodableValue(progress_.load()));
    return;
  }
  if (!IsPackaged()) {
    result->Error("NOT_PACKAGED", "The app is not running as an MSIX package");
    return;
  }

  const HWND owner = OwnerWindow();

  if (method == "checkForUpdates") {
    RunInBackground(std::move(result), [owner]() {
      StoreContext context = CreateContext(owner);
      const auto updates =
          context.GetAppAndOptionalStorePackageUpdatesAsync().get();
      std::string version;
      if (updates.Size() > 0) {
        const auto id = updates.GetAt(0).Package().Id().Version();
        std::ostringstream text;
        text << id.Major << "." << id.Minor << "." << id.Build;
        version = text.str();
      }
      return EncodableValue(EncodableMap{
          {EncodableValue("count"),
           EncodableValue(static_cast<int32_t>(updates.Size()))},
          {EncodableValue("version"), EncodableValue(version)},
      });
    });
    return;
  }

  // "download" fetches the packages only; "install" downloads anything still
  // missing, then installs — Windows closes the app to finish that step.
  if (method == "download" || method == "install") {
    if (busy_.exchange(true)) {
      result->Error("BUSY", "A Store update request is already running");
      return;
    }
    progress_ = 0.0;
    const bool install = method == "install";
    RunInBackground(std::move(result), [this, owner, install]() {
      struct BusyReset {
        std::atomic<bool>& flag;
        ~BusyReset() { flag = false; }
      } reset{busy_};

      StoreContext context = CreateContext(owner);
      const auto updates =
          context.GetAppAndOptionalStorePackageUpdatesAsync().get();
      if (updates.Size() == 0) {
        return EncodableValue(std::string("completed"));
      }
      auto operation =
          install ? context.RequestDownloadAndInstallStorePackageUpdatesAsync(
                        updates)
                  : context.RequestDownloadStorePackageUpdatesAsync(updates);
      operation.Progress(
          [this](const auto&, const StorePackageUpdateStatus& status) {
            progress_ = status.TotalDownloadProgress;
          });
      const auto outcome = operation.get();
      return EncodableValue(std::string(StateName(outcome.OverallState())));
    });
    return;
  }

  result->NotImplemented();
}
