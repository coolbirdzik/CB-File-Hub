#include "file_operations_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <shlobj.h>
#include <shobjidl.h>
#include <shldisp.h>
#include <exdisp.h>
#include <oleauto.h>
#include <windows.h>
#include <wrl/client.h>

#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

namespace file_operations_plugin
{

    namespace
    {
        // Declare before every COM interface so reverse destruction releases
        // those interfaces before the worker's apartment is uninitialized.
        // S_FALSE also increments COM's per-thread initialization count.
        class ScopedComApartment
        {
        public:
            explicit ScopedComApartment(DWORD flags)
                : result_(CoInitializeEx(nullptr, flags)) {}

            ~ScopedComApartment()
            {
                if (SUCCEEDED(result_)) CoUninitialize();
            }

            ScopedComApartment(const ScopedComApartment &) = delete;
            ScopedComApartment &operator=(const ScopedComApartment &) = delete;

            HRESULT result() const { return result_; }

        private:
            HRESULT result_;
        };

        constexpr UINT kOperationCompleteMessage = WM_APP + 0x4F1;

        // Tracks method-channel results whose native work runs on a detached
        // worker thread. flutter::MethodResult is NOT thread-safe, so the
        // worker only records its boolean outcome here and posts
        // kOperationCompleteMessage; the result itself is always completed on
        // the platform thread. Used by deleteItems, copyItems and moveItems.
        struct PendingRequestManager
        {
            std::mutex mutex;
            std::unordered_map<uint64_t,
                               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>>
                results;
            std::unordered_map<uint64_t, bool> status;
        };

        bool TrySetRequestStatus(
            const std::shared_ptr<PendingRequestManager> &manager,
            uint64_t request_id,
            bool ok)
        {
            if (!manager)
            {
                return false;
            }

            std::lock_guard<std::mutex> lock(manager->mutex);
            if (manager->results.find(request_id) == manager->results.end())
            {
                manager->status.erase(request_id);
                return false;
            }

            manager->status[request_id] = ok;
            return true;
        }

        void FinishPendingRequest(
            const std::shared_ptr<PendingRequestManager> &manager,
            uint64_t request_id)
        {
            if (!manager)
            {
                return;
            }

            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result;
            bool ok = false;

            {
                std::lock_guard<std::mutex> lock(manager->mutex);
                auto result_it = manager->results.find(request_id);
                auto status_it = manager->status.find(request_id);
                if (result_it == manager->results.end())
                {
                    if (status_it != manager->status.end())
                    {
                        manager->status.erase(status_it);
                    }
                    return;
                }

                result = std::move(result_it->second);
                manager->results.erase(result_it);

                if (status_it != manager->status.end())
                {
                    ok = status_it->second;
                    manager->status.erase(status_it);
                }
            }

            if (result)
            {
                result->Success(flutter::EncodableValue(ok));
            }
        }

        std::wstring Utf8ToWide(const std::string &utf8)
        {
            if (utf8.empty())
            {
                return std::wstring();
            }
            int size_needed = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                                  static_cast<int>(utf8.size()),
                                                  nullptr, 0);
            if (size_needed <= 0)
            {
                return std::wstring();
            }
            std::wstring wide(static_cast<size_t>(size_needed), L'\0');
            MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                static_cast<int>(utf8.size()),
                                wide.data(), size_needed);
            return wide;
        }

        void LogOperationMessage(const std::wstring &message)
        {
            std::wstring line = L"[CBFileHub][FileOperations] " + message + L"\n";
            OutputDebugStringW(line.c_str());
        }

        // Send the given items to the Recycle Bin (or permanently delete
        // them) using IFileOperation in a SINGLE batched call. The whole
        // batch goes through one PerformOperations() so we avoid the
        // per-item PowerShell process overhead of the legacy implementation.
        bool PerformDeleteOperation(
            HWND hwnd,
            const std::vector<std::wstring> &source_paths,
            bool permanent,
            bool silent,
            bool require_elevation)
        {
            if (source_paths.empty())
            {
                return false;
            }

            LogOperationMessage(
                L"PerformDeleteOperation start | count=" +
                std::to_wstring(source_paths.size()) +
                L" | permanent=" + std::to_wstring(permanent ? 1 : 0) +
                L" | silent=" + std::to_wstring(silent ? 1 : 0) +
                L" | requireElevation=" +
                    std::to_wstring(require_elevation ? 1 : 0) +
                L" | first=" + source_paths.front());

            // IFileOperation requires COM. The Flutter Windows engine
            // initialises COM on the platform thread, but our background
            // worker needs its own COM apartment.
            // Note: IFileOperation *requires* an STA (Single-Threaded Apartment)
            // on many older Windows versions, but using STA without a message
            // pump causes deadlocks when the shell attempts to marshal calls.
            // Using COINIT_MULTITHREADED avoids the need for a message pump
            // and prevents the PerformOperations() deadlock on modern Windows.
            ScopedComApartment apartment(
                COINIT_MULTITHREADED | COINIT_DISABLE_OLE1DDE);
            if (FAILED(apartment.result()))
            {
                LogOperationMessage(L"COM initialization failed | hr=" +
                                    std::to_wstring(apartment.result()));
                return false;
            }

            bool result_ok = false;
            do
            {
                Microsoft::WRL::ComPtr<IFileOperation> pfo;
                HRESULT hr = CoCreateInstance(
                    CLSID_FileOperation,
                    nullptr,
                    CLSCTX_ALL,
                    IID_PPV_ARGS(&pfo));
                if (FAILED(hr))
                {
                    LogOperationMessage(
                        L"CoCreateInstance failed | hr=" + std::to_wstring(hr));
                    break;
                }

                DWORD flags = 0;
                if (!permanent)
                {
                    flags |= FOF_ALLOWUNDO;
                }
                if (silent)
                {
                    flags |= FOF_NO_UI | FOF_NOCONFIRMATION |
                             FOF_NOERRORUI | FOF_SILENT |
                             FOFX_EARLYFAILURE;
                }
                if (require_elevation)
                {
                    flags |= FOFX_SHOWELEVATIONPROMPT |
                             FOFX_REQUIREELEVATION;
                }
                hr = pfo->SetOperationFlags(flags);
                if (FAILED(hr))
                {
                    LogOperationMessage(
                        L"SetOperationFlags failed | hr=" + std::to_wstring(hr));
                    break;
                }

                // CRITICAL: Do NOT set the owner window if we are running on a
                // background thread. Setting a main-thread HWND as the parent
                // of UI generated by a background thread causes Windows to call
                // AttachThreadInput, which instantly deadlocks both threads if
                // the main thread is blocking or not pumping messages exactly
                // as expected.
                // Since this runs in a detached std::thread, hwnd must be null.
                if (hwnd && !silent)
                {
                    // pfo->SetOwnerWindow(hwnd); // DISABLED TO PREVENT DEADLOCK
                }

                size_t queued = 0;
                for (const auto &source : source_paths)
                {
                    Microsoft::WRL::ComPtr<IShellItem> psiSource;
                    hr = SHCreateItemFromParsingName(
                        source.c_str(),
                        nullptr,
                        IID_PPV_ARGS(&psiSource));
                    if (FAILED(hr))
                    {
                        LogOperationMessage(
                            L"SHCreateItemFromParsingName failed | hr=" +
                            std::to_wstring(hr) + L" | path=" + source);
                        continue;
                    }

                    hr = pfo->DeleteItem(psiSource.Get(), nullptr);
                    if (SUCCEEDED(hr))
                    {
                        ++queued;
                    }
                    else
                    {
                        LogOperationMessage(
                            L"DeleteItem queue failed | hr=" +
                            std::to_wstring(hr) + L" | path=" + source);
                    }
                }

                if (queued == 0)
                {
                    LogOperationMessage(L"No paths were queued for deletion");
                    break;
                }

                LogOperationMessage(
                    L"Calling PerformOperations | queued=" +
                    std::to_wstring(queued) + L" | first=" +
                    source_paths.front());

                hr = pfo->PerformOperations();
                if (FAILED(hr))
                {
                    LogOperationMessage(
                        L"PerformOperations failed | hr=" + std::to_wstring(hr));
                    break;
                }

                BOOL aborted = FALSE;
                pfo->GetAnyOperationsAborted(&aborted);
                result_ok = !aborted;
                LogOperationMessage(
                    L"PerformOperations finished | aborted=" +
                    std::to_wstring(aborted ? 1 : 0) + L" | ok=" +
                    std::to_wstring(result_ok ? 1 : 0));
            } while (false);

            LogOperationMessage(
                L"PerformDeleteOperation end | ok=" +
                std::to_wstring(result_ok ? 1 : 0));
            return result_ok;
        }

        // Perform file operation using IFileOperation with progress dialog
        bool PerformFileOperation(
            HWND hwnd,
            const std::vector<std::wstring> &source_paths,
            const std::wstring &destination_path,
            bool is_move)
        {

            ScopedComApartment apartment(
                COINIT_MULTITHREADED | COINIT_DISABLE_OLE1DDE);
            if (FAILED(apartment.result())) return false;

            Microsoft::WRL::ComPtr<IFileOperation> pfo;
            HRESULT hr = CoCreateInstance(
                CLSID_FileOperation,
                nullptr,
                CLSCTX_ALL,
                IID_PPV_ARGS(&pfo));

            if (FAILED(hr))
            {
                return false;
            }

            // Set operation flags - show UI, allow undo, show progress
            DWORD flags = FOF_ALLOWUNDO | FOFX_ADDUNDORECORD | FOFX_SHOWELEVATIONPROMPT;
            hr = pfo->SetOperationFlags(flags);
            if (FAILED(hr))
            {
                return false;
            }

            // Do not set an owner window from a worker thread. Windows may
            // attach the worker and Flutter UI threads, causing a deadlock.
            (void)hwnd;

            // Get the destination folder
            Microsoft::WRL::ComPtr<IShellItem> psiDest;
            hr = SHCreateItemFromParsingName(
                destination_path.c_str(),
                nullptr,
                IID_PPV_ARGS(&psiDest));

            if (FAILED(hr))
            {
                return false;
            }

            // Add each source item to the operation
            for (const auto &source : source_paths)
            {
                Microsoft::WRL::ComPtr<IShellItem> psiSource;
                hr = SHCreateItemFromParsingName(
                    source.c_str(),
                    nullptr,
                    IID_PPV_ARGS(&psiSource));

                if (FAILED(hr))
                {
                    continue; // Skip invalid paths
                }

                if (is_move)
                {
                    hr = pfo->MoveItem(psiSource.Get(), psiDest.Get(), nullptr, nullptr);
                }
                else
                {
                    hr = pfo->CopyItem(psiSource.Get(), psiDest.Get(), nullptr, nullptr);
                }

                if (FAILED(hr))
                {
                    return false;
                }
            }

            // Perform the operation (this shows the native progress dialog)
            hr = pfo->PerformOperations();

            if (FAILED(hr))
            {
                return false;
            }

            // Check if operation was aborted by user
            BOOL aborted = FALSE;
            pfo->GetAnyOperationsAborted(&aborted);

            return !aborted;
        }

        class FileOperationsPlugin : public flutter::Plugin
        {
        public:
            static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

            explicit FileOperationsPlugin(flutter::PluginRegistrarWindows *registrar);
            virtual ~FileOperationsPlugin();

        private:
            void HandleMethodCall(
                const flutter::MethodCall<flutter::EncodableValue> &method_call,
                std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
            std::optional<LRESULT> HandleWindowProc(
                HWND hwnd,
                UINT message,
                WPARAM wparam,
                LPARAM lparam);
            void FinishRequestOnPlatformThread(uint64_t request_id);

            flutter::PluginRegistrarWindows *registrar_;
            HWND top_level_window_ = nullptr;
            int window_proc_delegate_id_ = 0;
            std::atomic<uint64_t> next_request_id_{1};
            std::shared_ptr<PendingRequestManager> pending_request_manager_ =
                std::make_shared<PendingRequestManager>();
        };

        void FileOperationsPlugin::RegisterWithRegistrar(
            flutter::PluginRegistrarWindows *registrar)
        {
            auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
                registrar->messenger(),
                "cb_file_manager/file_operations",
                &flutter::StandardMethodCodec::GetInstance());

            auto plugin = std::make_unique<FileOperationsPlugin>(registrar);

            channel->SetMethodCallHandler(
                [plugin_pointer = plugin.get()](const auto &call, auto result)
                {
                    plugin_pointer->HandleMethodCall(call, std::move(result));
                });

            registrar->AddPlugin(std::move(plugin));
        }

        FileOperationsPlugin::FileOperationsPlugin(
            flutter::PluginRegistrarWindows *registrar)
            : registrar_(registrar)
        {
            if (auto *view = registrar_->GetView())
            {
                HWND native_window = view->GetNativeWindow();
                top_level_window_ = native_window ? GetAncestor(native_window, GA_ROOT) : nullptr;
            }

            window_proc_delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
                [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam)
                {
                    return HandleWindowProc(hwnd, message, wparam, lparam);
                });
        }

        FileOperationsPlugin::~FileOperationsPlugin()
        {
            if (window_proc_delegate_id_ != 0)
            {
                registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_delegate_id_);
            }
        }

        std::optional<LRESULT> FileOperationsPlugin::HandleWindowProc(
            HWND hwnd,
            UINT message,
            WPARAM wparam,
            LPARAM lparam)
        {
            if (message != kOperationCompleteMessage)
            {
                return std::nullopt;
            }

            auto request_id = static_cast<uint64_t>(wparam);
            FinishRequestOnPlatformThread(request_id);
            return 0;
        }

        void FileOperationsPlugin::FinishRequestOnPlatformThread(
            uint64_t request_id)
        {
            FinishPendingRequest(pending_request_manager_, request_id);
        }

        void FileOperationsPlugin::HandleMethodCall(
            const flutter::MethodCall<flutter::EncodableValue> &method_call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
        {

            const std::string &method = method_call.method_name();

            if (method == "deleteItems")
            {
                const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
                if (!arguments)
                {
                    result->Error("INVALID_ARGUMENTS", "Arguments must be a map.");
                    return;
                }

                auto sources_it = arguments->find(flutter::EncodableValue("sources"));
                if (sources_it == arguments->end())
                {
                    result->Error("INVALID_ARGUMENTS", "Missing 'sources' argument.");
                    return;
                }

                const auto *sources_list = std::get_if<flutter::EncodableList>(&sources_it->second);
                if (!sources_list || sources_list->empty())
                {
                    result->Error("INVALID_ARGUMENTS", "'sources' must be a non-empty list.");
                    return;
                }

                std::vector<std::wstring> source_paths;
                source_paths.reserve(sources_list->size());
                for (const auto &source : *sources_list)
                {
                    if (const auto *path = std::get_if<std::string>(&source))
                    {
                        source_paths.push_back(Utf8ToWide(*path));
                    }
                }

                if (source_paths.empty())
                {
                    result->Error("INVALID_ARGUMENTS", "No valid source paths provided.");
                    return;
                }

                bool permanent = false;
                if (auto perm_it = arguments->find(flutter::EncodableValue("permanent"));
                    perm_it != arguments->end())
                {
                    if (const auto *b = std::get_if<bool>(&perm_it->second)) permanent = *b;
                }

                bool silent = true;
                if (auto silent_it = arguments->find(flutter::EncodableValue("silent"));
                    silent_it != arguments->end())
                {
                    if (const auto *b = std::get_if<bool>(&silent_it->second)) silent = *b;
                }

                bool require_elevation = false;
                if (auto elevation_it = arguments->find(flutter::EncodableValue("requireElevation"));
                    elevation_it != arguments->end())
                {
                    if (const auto *b = std::get_if<bool>(&elevation_it->second)) require_elevation = *b;
                }

                if (require_elevation && !permanent)
                {
                    result->Error(
                        "INVALID_ARGUMENTS",
                        "requireElevation is valid only for permanent deletion.");
                    return;
                }

                int timeout_ms = 0;
                if (auto timeout_it = arguments->find(flutter::EncodableValue("timeoutMs"));
                    timeout_it != arguments->end())
                {
                    if (const auto *timeout32 = std::get_if<int32_t>(&timeout_it->second))
                    {
                        timeout_ms = *timeout32;
                    }
                    else if (const auto *timeout64 = std::get_if<int64_t>(&timeout_it->second))
                    {
                        timeout_ms = static_cast<int>(*timeout64);
                    }
                }

                HWND hwnd = silent ? nullptr : top_level_window_;
                const uint64_t request_id = next_request_id_++;
                LogOperationMessage(
                    L"deleteItems request received | requestId=" +
                    std::to_wstring(request_id) + L" | count=" +
                    std::to_wstring(source_paths.size()) + L" | permanent=" +
                    std::to_wstring(permanent ? 1 : 0) + L" | silent=" +
                    std::to_wstring(silent ? 1 : 0) + L" | requireElevation=" +
                    std::to_wstring(require_elevation ? 1 : 0) + L" | first=" +
                    source_paths.front());
                auto pending_delete_manager = pending_request_manager_;
                {
                    std::lock_guard<std::mutex> lock(pending_delete_manager->mutex);
                    pending_delete_manager->results.emplace(request_id, std::move(result));
                }

                HWND completion_window = top_level_window_;
                if (timeout_ms > 0)
                {
                    std::thread(
                        [pending_delete_manager, request_id, completion_window, timeout_ms]()
                        {
                            std::this_thread::sleep_for(
                                std::chrono::milliseconds(timeout_ms));

                            if (!TrySetRequestStatus(
                                    pending_delete_manager,
                                    request_id,
                                    false))
                            {
                                return;
                            }

                            bool posted = false;
                            if (completion_window)
                            {
                                posted = PostMessage(
                                    completion_window,
                                    kOperationCompleteMessage,
                                    static_cast<WPARAM>(request_id),
                                    0);
                            }

                            if (!posted)
                            {
                                FinishPendingRequest(
                                    pending_delete_manager,
                                    request_id);
                            }

                            LogOperationMessage(
                                L"deleteItems timed out | requestId=" +
                                std::to_wstring(request_id) +
                                L" | timeoutMs=" +
                                std::to_wstring(timeout_ms));
                        })
                        .detach();
                }

                std::thread(
                    [pending_delete_manager, request_id, hwnd, completion_window, source_paths = std::move(source_paths), permanent, silent, require_elevation]() mutable
                    {
                        LogOperationMessage(
                            L"deleteItems worker started | requestId=" +
                            std::to_wstring(request_id) + L" | first=" +
                            source_paths.front());
                        bool ok = false;
                        try
                        {
                            ok = PerformDeleteOperation(
                                hwnd,
                                source_paths,
                                permanent,
                                silent,
                                require_elevation);
                        }
                        catch (...)
                        {
                            LogOperationMessage(
                                L"deleteItems worker threw exception | requestId=" +
                                std::to_wstring(request_id));
                            ok = false;
                        }

                        bool posted = false;
                        if (!TrySetRequestStatus(
                                pending_delete_manager,
                                request_id,
                                ok))
                        {
                            LogOperationMessage(
                                L"deleteItems worker finished after response was already completed | requestId=" +
                                std::to_wstring(request_id) + L" | ok=" +
                                std::to_wstring(ok ? 1 : 0));
                            return;
                        }

                        if (completion_window)
                        {
                            posted = PostMessage(
                                completion_window,
                                kOperationCompleteMessage,
                                static_cast<WPARAM>(request_id),
                                0);
                        }

                        if (!posted)
                        {
                            FinishPendingRequest(pending_delete_manager, request_id);
                        }
                        LogOperationMessage(
                            L"deleteItems worker finished | requestId=" +
                            std::to_wstring(request_id) + L" | ok=" +
                            std::to_wstring(ok ? 1 : 0) + L" | posted=" +
                            std::to_wstring(posted ? 1 : 0));
                    })
                    .detach();

                return;
            }

            if (method == "copyItems" || method == "moveItems")
            {
                const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
                if (!arguments)
                {
                    result->Error("INVALID_ARGUMENTS", "Arguments must be a map.");
                    return;
                }

                // Get source paths
                auto sources_it = arguments->find(flutter::EncodableValue("sources"));
                if (sources_it == arguments->end())
                {
                    result->Error("INVALID_ARGUMENTS", "Missing 'sources' argument.");
                    return;
                }

                const auto *sources_list = std::get_if<flutter::EncodableList>(&sources_it->second);
                if (!sources_list || sources_list->empty())
                {
                    result->Error("INVALID_ARGUMENTS", "'sources' must be a non-empty list.");
                    return;
                }

                std::vector<std::wstring> source_paths;
                for (const auto &source : *sources_list)
                {
                    if (const auto *path = std::get_if<std::string>(&source))
                    {
                        source_paths.push_back(Utf8ToWide(*path));
                    }
                }

                if (source_paths.empty())
                {
                    result->Error("INVALID_ARGUMENTS", "No valid source paths provided.");
                    return;
                }

                // Get destination path
                auto dest_it = arguments->find(flutter::EncodableValue("destination"));
                if (dest_it == arguments->end())
                {
                    result->Error("INVALID_ARGUMENTS", "Missing 'destination' argument.");
                    return;
                }

                const auto *dest_path = std::get_if<std::string>(&dest_it->second);
                if (!dest_path || dest_path->empty())
                {
                    result->Error("INVALID_ARGUMENTS", "'destination' must be a non-empty string.");
                    return;
                }

                std::wstring destination = Utf8ToWide(*dest_path);
                bool is_move = (method == "moveItems");

                const uint64_t request_id = next_request_id_++;
                auto pending_request_manager = pending_request_manager_;
                {
                    std::lock_guard<std::mutex> lock(pending_request_manager->mutex);
                    pending_request_manager->results.emplace(request_id, std::move(result));
                }

                HWND completion_window = top_level_window_;
                std::thread(
                    [pending_request_manager, request_id, completion_window,
                     source_paths = std::move(source_paths), destination, is_move]() mutable
                    {
                        bool success = false;
                        try
                        {
                            success = PerformFileOperation(
                                nullptr, source_paths, destination, is_move);
                        }
                        catch (...)
                        {
                            success = false;
                        }

                        if (!TrySetRequestStatus(
                                pending_request_manager, request_id, success))
                        {
                            return;
                        }

                        if (!completion_window || !PostMessage(
                                completion_window,
                                kOperationCompleteMessage,
                                static_cast<WPARAM>(request_id),
                                0))
                        {
                            FinishPendingRequest(pending_request_manager, request_id);
                        }
                    })
                    .detach();
                return;
            }

            if (method == "enumerateRecycleBin")
            {
                // Optional offset/limit so callers can paginate the
                // enumeration. The COM enumeration itself is unavoidable
                // (no native API to get a single recycle-bin entry by
                // index without first walking the namespace), but
                // returning a slice keeps the IPC payload + Dart-side
                // mapping bounded and lets the UI render the first page
                // without waiting for tens of thousands of entries.
                int requested_offset = 0;
                int requested_limit = -1; // -1 = no limit
                if (const auto *arguments =
                        std::get_if<flutter::EncodableMap>(method_call.arguments()))
                {
                    auto offset_it =
                        arguments->find(flutter::EncodableValue("offset"));
                    if (offset_it != arguments->end())
                    {
                        if (const auto *v =
                                std::get_if<int32_t>(&offset_it->second))
                        {
                            requested_offset = *v;
                        }
                        else if (const auto *vl =
                                     std::get_if<int64_t>(&offset_it->second))
                        {
                            requested_offset = static_cast<int>(*vl);
                        }
                    }
                    auto limit_it =
                        arguments->find(flutter::EncodableValue("limit"));
                    if (limit_it != arguments->end())
                    {
                        if (const auto *v =
                                std::get_if<int32_t>(&limit_it->second))
                        {
                            requested_limit = *v;
                        }
                        else if (const auto *vl =
                                     std::get_if<int64_t>(&limit_it->second))
                        {
                            requested_limit = static_cast<int>(*vl);
                        }
                    }
                }
                if (requested_offset < 0) requested_offset = 0;

                // Run on a worker thread so the platform thread is not
                // blocked by COM enumeration of large recycle bins.
                auto plugin_result_ptr =
                    std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
                        std::move(result));

                std::thread([plugin_result_ptr, requested_offset, requested_limit]() {
                    ScopedComApartment apartment(
                        COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
                    if (FAILED(apartment.result()))
                    {
                        plugin_result_ptr->Error(
                            "RECYCLE_BIN_ENUM_FAILED",
                            "Failed to initialize COM for Recycle Bin enumeration");
                        return;
                    }

                    flutter::EncodableList items;

                    Microsoft::WRL::ComPtr<IShellDispatch> shell_dispatch;
                    HRESULT hr = CoCreateInstance(
                        CLSID_Shell, nullptr, CLSCTX_INPROC_SERVER,
                        IID_PPV_ARGS(&shell_dispatch));
                    if (FAILED(hr) || !shell_dispatch)
                    {
                        plugin_result_ptr->Error(
                            "RECYCLE_BIN_ENUM_FAILED",
                            "Failed to create Shell.Application COM instance");
                        return;
                    }

                    Microsoft::WRL::ComPtr<Folder> recycle_folder;
                    {
                        VARIANT folder_id;
                        VariantInit(&folder_id);
                        folder_id.vt = VT_I4;
                        folder_id.lVal = 0xa; // ssfBITBUCKET (Recycle Bin)
                        hr = shell_dispatch->NameSpace(folder_id, &recycle_folder);
                        VariantClear(&folder_id);
                    }

                    if (FAILED(hr) || !recycle_folder)
                    {
                        plugin_result_ptr->Error(
                            "RECYCLE_BIN_ENUM_FAILED",
                            "Failed to open Recycle Bin namespace");
                        return;
                    }

                    Microsoft::WRL::ComPtr<Folder2> recycle_folder2;
                    recycle_folder.As(&recycle_folder2);

                    // Resolve the property indices for "Original Location"
                    // and "Date deleted" exactly once. Indices are stable
                    // for a given Windows version but locale-independent
                    // names cannot be used, so we discover at runtime.
                    int orig_idx = -1;
                    int date_idx = -1;
                    if (recycle_folder2)
                    {
                        BSTR prop_name = nullptr;
                        for (int i = 0; i < 500 && (orig_idx < 0 || date_idx < 0); i++)
                        {
                            VARIANT empty;
                            VariantInit(&empty);
                            empty.vt = VT_EMPTY;
                            HRESULT prop_hr = recycle_folder2->GetDetailsOf(
                                empty, i, &prop_name);
                            VariantClear(&empty);
                            if (FAILED(prop_hr) || !prop_name)
                            {
                                continue;
                            }
                            std::wstring name(prop_name, SysStringLen(prop_name));
                            SysFreeString(prop_name);
                            prop_name = nullptr;

                            if (orig_idx < 0 && name == L"Original Location")
                            {
                                orig_idx = i;
                            }
                            else if (date_idx < 0 && name == L"Date deleted")
                            {
                                date_idx = i;
                            }
                        }
                    }

                    Microsoft::WRL::ComPtr<FolderItems> folder_items;
                    hr = recycle_folder->Items(&folder_items);
                    long total_count = 0;
                    if (SUCCEEDED(hr) && folder_items)
                    {
                        long count = 0;
                        folder_items->get_Count(&count);
                        total_count = count;
                        const long start_index = static_cast<long>(requested_offset);
                        const long end_index = (requested_limit < 0)
                            ? count
                            : (start_index + static_cast<long>(requested_limit) > count
                                ? count
                                : start_index + static_cast<long>(requested_limit));
                        for (long i = start_index; i < end_index; i++)
                        {
                            VARIANT idx;
                            VariantInit(&idx);
                            idx.vt = VT_I4;
                            idx.lVal = i;

                            Microsoft::WRL::ComPtr<FolderItem> folder_item;
                            HRESULT item_hr = folder_items->Item(idx, &folder_item);
                            VariantClear(&idx);
                            if (FAILED(item_hr) || !folder_item)
                            {
                                continue;
                            }

                            BSTR name = nullptr;
                            BSTR path = nullptr;
                            VARIANT_BOOL is_folder = VARIANT_FALSE;
                            LONGLONG size_ll = 0;

                            folder_item->get_Name(&name);
                            folder_item->get_Path(&path);
                            folder_item->get_IsFolder(&is_folder);

                            // Folder.Size returns LONG (32-bit). For files
                            // > 2 GB this is wrong, but matches the legacy
                            // PowerShell behavior. We pass it through.
                            long size_long = 0;
                            folder_item->get_Size(&size_long);
                            size_ll = static_cast<LONGLONG>(size_long);

                            std::wstring orig;
                            std::wstring date;
                            if (recycle_folder2)
                            {
                                VARIANT item_var;
                                VariantInit(&item_var);
                                item_var.vt = VT_DISPATCH;
                                item_var.pdispVal = folder_item.Get();
                                item_var.pdispVal->AddRef();

                                if (orig_idx >= 0)
                                {
                                    BSTR detail = nullptr;
                                    if (SUCCEEDED(recycle_folder2->GetDetailsOf(
                                            item_var, orig_idx, &detail)) &&
                                        detail)
                                    {
                                        orig.assign(detail, SysStringLen(detail));
                                        SysFreeString(detail);
                                    }
                                }
                                if (date_idx >= 0)
                                {
                                    BSTR detail = nullptr;
                                    if (SUCCEEDED(recycle_folder2->GetDetailsOf(
                                            item_var, date_idx, &detail)) &&
                                        detail)
                                    {
                                        date.assign(detail, SysStringLen(detail));
                                        SysFreeString(detail);
                                    }
                                }
                                VariantClear(&item_var);
                            }

                            auto wide_to_utf8 = [](const std::wstring &w) -> std::string {
                                if (w.empty()) return std::string();
                                int needed = WideCharToMultiByte(
                                    CP_UTF8, 0, w.data(),
                                    static_cast<int>(w.size()),
                                    nullptr, 0, nullptr, nullptr);
                                std::string out(static_cast<size_t>(needed), '\0');
                                WideCharToMultiByte(
                                    CP_UTF8, 0, w.data(),
                                    static_cast<int>(w.size()),
                                    out.data(), needed, nullptr, nullptr);
                                return out;
                            };

                            flutter::EncodableMap entry;
                            entry[flutter::EncodableValue("name")] =
                                flutter::EncodableValue(wide_to_utf8(
                                    name ? std::wstring(name, SysStringLen(name))
                                         : std::wstring()));
                            entry[flutter::EncodableValue("path")] =
                                flutter::EncodableValue(wide_to_utf8(
                                    path ? std::wstring(path, SysStringLen(path))
                                         : std::wstring()));
                            entry[flutter::EncodableValue("originalPath")] =
                                flutter::EncodableValue(wide_to_utf8(orig));
                            entry[flutter::EncodableValue("deletedDate")] =
                                flutter::EncodableValue(wide_to_utf8(date));
                            entry[flutter::EncodableValue("size")] =
                                flutter::EncodableValue(static_cast<int64_t>(size_ll));
                            entry[flutter::EncodableValue("isFolder")] =
                                flutter::EncodableValue(is_folder == VARIANT_TRUE);

                            items.push_back(flutter::EncodableValue(entry));

                            if (name) SysFreeString(name);
                            if (path) SysFreeString(path);
                        }
                    }

                    flutter::EncodableMap response;
                    response[flutter::EncodableValue("items")] =
                        flutter::EncodableValue(items);
                    response[flutter::EncodableValue("total")] =
                        flutter::EncodableValue(static_cast<int64_t>(total_count));
                    plugin_result_ptr->Success(flutter::EncodableValue(response));
                }).detach();
                return;
            }

            result->NotImplemented();
        }

    } // namespace

    void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar)
    {
        FileOperationsPlugin::RegisterWithRegistrar(registrar);
    }

} // namespace file_operations_plugin
