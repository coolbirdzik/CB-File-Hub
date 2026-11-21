#ifndef FLUTTER_PLUGIN_FC_NATIVE_VIDEO_THUMBNAIL_PLUGIN_H_
#define FLUTTER_PLUGIN_FC_NATIVE_VIDEO_THUMBNAIL_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <gdiplus.h>

#include <memory>
#include <thread>
#include <queue>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <unordered_map>
#include <unordered_set>
#include <string>
#include <future>
#include <chrono>
#include <vector>

namespace fc_native_video_thumbnail
{

    // Priority levels for thumbnail requests
    enum class ThumbnailPriority
    {
        LOW = 0,    // Background thumbnails not visible
        NORMAL = 1, // Default priority
        HIGH = 2,   // Visible on screen
        URGENT = 3  // Currently focused/selected item
    };

    // Thumbnail request structure for async processing
    struct ThumbnailRequest
    {
        std::string srcFile;
        std::string destFile;
        int width;
        std::string format;
        int timeSeconds;
        int quality;
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result;
        std::string requestId;
        ThumbnailPriority priority;
        std::chrono::steady_clock::time_point requestTime;

        // Constructor
        ThumbnailRequest() : priority(ThumbnailPriority::NORMAL), requestTime(std::chrono::steady_clock::now()) {}
    };

    // Priority queue comparator for thumbnail requests
    struct ThumbnailRequestComparator
    {
        bool operator()(const std::unique_ptr<ThumbnailRequest> &a, const std::unique_ptr<ThumbnailRequest> &b) const
        {
            // Higher priority first
            if (a->priority != b->priority)
            {
                return static_cast<int>(a->priority) < static_cast<int>(b->priority);
            }
            // If same priority, older requests first (FIFO within same priority)
            return a->requestTime > b->requestTime;
        }
    };

    // Thumbnail cache entry
    struct CacheEntry
    {
        std::string thumbnailPath;
        int64_t lastModified;
        int64_t fileSize;
        std::chrono::system_clock::time_point cacheTime;
    };

    // Helper function to get the CLSID of an image encoder
    int GetEncoderClsid(const WCHAR *format, CLSID *pClsid);

    // Extract a frame from a video at a specific timestamp using MediaFoundation
    std::string ExtractVideoFrameAtTime(PCWSTR srcFile, PCWSTR destFile, int width, REFGUID format, int timeSeconds, int quality);

    // Extract a thumbnail using Windows shell thumbnail cache
    std::string ExtractShellThumbnail(PCWSTR srcFile, PCWSTR destFile, int size, REFGUID type);

    // Save a thumbnail using Windows thumbnail cache, or MediaFoundation when timeSeconds is provided
    std::string SaveThumbnail(PCWSTR srcFile, PCWSTR destFile, int size, REFGUID type, int *timeSeconds, int quality, bool useShellThumbnail);

    class FcNativeVideoThumbnailPlugin : public flutter::Plugin
    {
    public:
        static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

        FcNativeVideoThumbnailPlugin();

        virtual ~FcNativeVideoThumbnailPlugin();

        // Disallow copy and assign.
        FcNativeVideoThumbnailPlugin(const FcNativeVideoThumbnailPlugin &) = delete;
        FcNativeVideoThumbnailPlugin &operator=(const FcNativeVideoThumbnailPlugin &) = delete;

    private:
        // Called when a method is called on this plugin's channel from Dart.
        void HandleMethodCall(
            const flutter::MethodCall<flutter::EncodableValue> &method_call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

        // Async thumbnail processing methods
        bool StartThumbnailWorkers();
        void ProcessThumbnailAsync(std::unique_ptr<ThumbnailRequest> request);
        void WorkerThread();
        bool IsThumbnailCached(const std::string &srcFile, const std::string &destFile);
        void UpdateCache(const std::string &srcFile, const std::string &destFile);
        std::string GenerateCacheKey(const std::string &srcFile, int width, const std::string &format);

        // Priority management methods
        void UpdateRequestPriority(const std::string &requestId, ThumbnailPriority priority);
        void SetVisibleThumbnails(const std::vector<std::string> &visibleFiles);
        void SetFocusedThumbnail(const std::string &focusedFile);
        ThumbnailPriority DeterminePriority(const std::string &srcFile);

        // Thread pool and priority queue management
        std::vector<std::thread> workers_;
        std::vector<std::unique_ptr<ThumbnailRequest>> requestQueue_;
        std::mutex queueMutex_;
        std::condition_variable queueCondition_;
        std::atomic<bool> shutdown_{false};
        bool thumbnailBackendStarted_ = false;
        bool mediaFoundationStarted_ = false;
        bool ffmpegGdiStarted_ = false;

        // Request tracking for priority updates
        std::unordered_map<std::string, ThumbnailPriority> requestPriorities_;
        std::mutex priorityMutex_;

        // Visibility tracking for priority management
        std::unordered_set<std::string> visibleFiles_;
        std::string focusedFile_;
        std::mutex visibilityMutex_;

        // Cache management
        std::unordered_map<std::string, CacheEntry> thumbnailCache_;
        std::mutex cacheMutex_;

        // Active request tracking to prevent duplicates
        std::unordered_set<std::string> activeRequests_;
        std::mutex activeRequestsMutex_;

        // Debouncing for visibility updates
        std::chrono::steady_clock::time_point lastVisibilityUpdate_;
        static constexpr std::chrono::milliseconds VISIBILITY_DEBOUNCE_MS{100};

        // Queue management for performance
        static constexpr size_t MAX_QUEUE_SIZE = 50;
        static constexpr size_t QUEUE_CLEANUP_THRESHOLD = 40;

        // Fast scroll detection
        std::chrono::steady_clock::time_point lastScrollTime_;
        size_t scrollEventCount_;
        static constexpr std::chrono::milliseconds FAST_SCROLL_WINDOW_MS{500};
        static constexpr size_t FAST_SCROLL_THRESHOLD = 5;

        // Shared resources for GDI+ initialization
        static std::mutex gdiMutex_;
        static bool gdiInitialized_;
        static ULONG_PTR gdiplusToken_;
        static int instanceCount_;
    };

} // namespace fc_native_video_thumbnail

#endif // FLUTTER_PLUGIN_FC_NATIVE_VIDEO_THUMBNAIL_PLUGIN_H_
