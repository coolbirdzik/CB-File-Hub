#include "ffmpeg_thumbnail_helper.h"

#include <atlbase.h>
#include <atlimage.h>
#include <chrono>
#include <cmath>
#include <codecvt>
#include <cstdio>
#include <locale>
#include <mutex>
#include <stdexcept>
#include <vector>

namespace fc_native_video_thumbnail
{

    // Forward declaration of GetEncoderClsid from fc_native_video_thumbnail_plugin.cpp
    extern int GetEncoderClsid(const WCHAR *format, CLSID *pClsid);

    // Demuxed packets are not frames: an MP4 may contain dozens of audio
    // packets between video packets, and frame-threaded decoding needs several
    // video packets before it produces its first image.
    static bool DecodeFirstVideoFrame(AVFormatContext *formatContext,
                                      AVCodecContext *codecContext,
                                      int videoStreamIndex,
                                      AVPacket *packet,
                                      AVFrame *frame)
    {
        if (!packet || !frame) return false;
        int videoPackets = 0;
        for (int packets = 0; packets < 4096 && videoPackets < 120; ++packets)
        {
            const int readResult = av_read_frame(formatContext, packet);
            if (readResult < 0)
            {
                // Short videos can end before a frame-threaded decoder emits
                // a picture. Drain delayed frames at EOF.
                if (readResult == AVERROR_EOF)
                {
                    avcodec_send_packet(codecContext, nullptr);
                    return avcodec_receive_frame(codecContext, frame) == 0;
                }
                return false;
            }
            if (packet->stream_index != videoStreamIndex)
            {
                av_packet_unref(packet);
                continue;
            }
            ++videoPackets;
            const int sendResult = avcodec_send_packet(codecContext, packet);
            av_packet_unref(packet);
            // EAGAIN means the decoder has output waiting to be received.
            if ((sendResult == 0 || sendResult == AVERROR(EAGAIN)) &&
                avcodec_receive_frame(codecContext, frame) == 0)
            {
                return true;
            }
        }
        return false;
    }

    // Decoding one picture above 4K (8K VR video) takes hundreds of MB. Four
    // thumbnail workers doing that at once pushed the app to several GB, so
    // such decodes run one at a time; 4K and smaller stay parallel.
    static std::mutex g_largeDecodeMutex;

    static std::unique_lock<std::mutex> LockIfLargePicture(
        const AVCodecParameters *params)
    {
        std::unique_lock<std::mutex> lock(g_largeDecodeMutex, std::defer_lock);
        if (params &&
            static_cast<int64_t>(params->width) * params->height >
                3840LL * 2160LL)
        {
            lock.lock();
        }
        return lock;
    }

    // Thumbnail output size. maxEdge is the longest edge in physical pixels:
    // the result fits a maxEdge x maxEdge box, keeps the aspect ratio
    // (portrait stays portrait) and never upscales. maxEdge <= 0 keeps the
    // source size.
    static void ComputeThumbnailOutputSize(int srcWidth,
                                           int srcHeight,
                                           int maxEdge,
                                           int *outWidth,
                                           int *outHeight)
    {
        *outWidth = srcWidth;
        *outHeight = srcHeight;
        if (maxEdge <= 0 || srcWidth <= 0 || srcHeight <= 0) return;
        if (srcWidth <= maxEdge && srcHeight <= maxEdge) return;

        if (srcWidth >= srcHeight)
        {
            *outWidth = maxEdge;
            *outHeight = static_cast<int>(std::llround(
                static_cast<double>(srcHeight) * maxEdge / srcWidth));
        }
        else
        {
            *outHeight = maxEdge;
            *outWidth = static_cast<int>(std::llround(
                static_cast<double>(srcWidth) * maxEdge / srcHeight));
        }
        if (*outWidth < 1) *outWidth = 1;
        if (*outHeight < 1) *outHeight = 1;
    }

    // ============================================================================
    // PER-PHASE TIMING - enabled with the environment variable CB_THUMB_TIMING=1
    // ============================================================================
    static bool ThumbTimingEnabled()
    {
        static const bool enabled = []()
        {
            wchar_t value[4] = {};
            const DWORD length =
                GetEnvironmentVariableW(L"CB_THUMB_TIMING", value, 4);
            return length == 1 && value[0] == L'1';
        }();
        return enabled;
    }

    // Records how long each extraction phase took and prints one line per
    // extraction to stderr and the debugger. When timing is disabled every
    // call returns at once without reading the clock or formatting text.
    namespace
    {
    class ThumbTiming
    {
    public:
        enum Phase
        {
            kOpen,
            kProbe,
            kLock,
            kSeek,
            kDecode,
            kScale,
            kSave,
            kPhaseCount
        };

        // path must outlive this object.
        ThumbTiming(const char *mode, const std::string &path)
            : enabled_(ThumbTimingEnabled()), mode_(mode), path_(&path)
        {
            for (int i = 0; i < kPhaseCount; ++i) phaseMs_[i] = -1.0;
            if (enabled_)
            {
                start_ = Clock::now();
                last_ = start_;
            }
        }

        ~ThumbTiming()
        {
            if (enabled_ && !finished_) Emit("\"unfinished\"");
        }

        ThumbTiming(const ThumbTiming &) = delete;
        ThumbTiming &operator=(const ThumbTiming &) = delete;

        // Ends the phase that started at the previous Mark (or construction).
        void Mark(Phase phase)
        {
            if (!enabled_) return;
            const Clock::time_point now = Clock::now();
            phaseMs_[phase] =
                std::chrono::duration<double, std::milli>(now - last_).count();
            last_ = now;
        }

        void SetSizes(int srcWidth, int srcHeight, int outWidth, int outHeight)
        {
            if (!enabled_) return;
            srcWidth_ = srcWidth;
            srcHeight_ = srcHeight;
            outWidth_ = outWidth;
            outHeight_ = outHeight;
        }

        // Logs the extraction result (empty = success) and passes it through.
        std::string Finish(std::string result)
        {
            if (enabled_ && !finished_)
            {
                finished_ = true;
                if (result.empty())
                {
                    Emit("ok");
                }
                else
                {
                    const std::string quoted = "\"" + result + "\"";
                    Emit(quoted.c_str());
                }
            }
            return result;
        }

    private:
        using Clock = std::chrono::steady_clock;

        void Emit(const char *result) const
        {
            static const char *const kNames[kPhaseCount] = {
                "open", "probe", "lock", "seek", "decode", "scale", "save"};
            const double totalMs = std::chrono::duration<double, std::milli>(
                                       Clock::now() - start_)
                                       .count();

            std::string line = "CB_THUMB_TIMING mode=";
            line += mode_;
            char buffer[160];
            for (int i = 0; i < kPhaseCount; ++i)
            {
                if (phaseMs_[i] < 0.0)
                {
                    std::snprintf(buffer, sizeof(buffer), " %s=-", kNames[i]);
                }
                else
                {
                    std::snprintf(buffer, sizeof(buffer), " %s=%.1fms",
                                  kNames[i], phaseMs_[i]);
                }
                line += buffer;
            }
            std::snprintf(buffer, sizeof(buffer),
                          " total=%.1fms src=%dx%d out=%dx%d result=", totalMs,
                          srcWidth_, srcHeight_, outWidth_, outHeight_);
            line += buffer;
            line += result;
            line += " path=";
            line += *path_;
            line += "\n";

            std::fputs(line.c_str(), stderr);
            std::fflush(stderr);
            OutputDebugStringA(line.c_str());
        }

        const bool enabled_;
        const char *const mode_;
        const std::string *const path_;
        bool finished_ = false;
        Clock::time_point start_;
        Clock::time_point last_;
        double phaseMs_[kPhaseCount];
        int srcWidth_ = 0;
        int srcHeight_ = 0;
        int outWidth_ = 0;
        int outHeight_ = 0;
    };
    } // namespace

    // ============================================================================
    // SHARED GDI+ SINGLETON - Eliminates per-call init/shutdown overhead
    // ============================================================================
    static std::mutex g_gdiMutex;
    static bool g_gdiInitialized = false;
    static ULONG_PTR g_gdiToken = 0;
    static int g_instanceCount = 0;

    void FFmpegThumbnailHelper::InitializeGdiPlus()
    {
        std::lock_guard<std::mutex> lock(g_gdiMutex);
        if (!g_gdiInitialized)
        {
            Gdiplus::GdiplusStartupInput input;
            Gdiplus::GdiplusStartup(&g_gdiToken, &input, NULL);
            g_gdiInitialized = true;
        }
        g_instanceCount++;
    }

    void FFmpegThumbnailHelper::ShutdownGdiPlus()
    {
        std::lock_guard<std::mutex> lock(g_gdiMutex);
        g_instanceCount--;
        if (g_instanceCount <= 0 && g_gdiInitialized)
        {
            Gdiplus::GdiplusShutdown(g_gdiToken);
            g_gdiInitialized = false;
            g_instanceCount = 0;
        }
    }

    // ============================================================================
    // FAST SAVEIMAGE - Uses shared GDI+ resources, no per-call init overhead
    // ============================================================================
    bool FFmpegThumbnailHelper::SaveImageFast(
        AVFrame *frame,
        int width,
        int height,
        const wchar_t *destFile,
        REFGUID format,
        int quality)
    {
        // Use shared GDI+ - no initialization needed
        std::lock_guard<std::mutex> lock(g_gdiMutex);
        if (!g_gdiInitialized)
        {
            return false; // Should call InitializeGdiPlus() at startup
        }

        bool result = false;

        try
        {
            // Create a GDI+ bitmap
            Gdiplus::Bitmap bitmap(width, height, PixelFormat24bppRGB);

            // Lock the bitmap for writing
            Gdiplus::BitmapData bitmapData;
            Gdiplus::Rect rect(0, 0, width, height);
            bitmap.LockBits(&rect, Gdiplus::ImageLockModeWrite, PixelFormat24bppRGB, &bitmapData);

            // Copy pixel data from FFmpeg frame to GDI+ bitmap
            for (int y = 0; y < height; y++)
            {
                uint8_t *srcLine = frame->data[0] + y * frame->linesize[0];
                uint8_t *dstLine = (uint8_t *)bitmapData.Scan0 + y * bitmapData.Stride;

                for (int x = 0; x < width; x++)
                {
                    // RGB24 format: R, G, B
                    dstLine[x * 3 + 2] = srcLine[x * 3 + 0]; // R
                    dstLine[x * 3 + 1] = srcLine[x * 3 + 1]; // G
                    dstLine[x * 3 + 0] = srcLine[x * 3 + 2]; // B
                }
            }

            // Unlock the bitmap
            bitmap.UnlockBits(&bitmapData);

            // Get encoder CLSID
            CLSID encoderClsid;
            int encoderIndex = -1;

            if (format == Gdiplus::ImageFormatPNG)
            {
                encoderIndex = GetEncoderClsid(L"image/png", &encoderClsid);
            }
            else
            {
                encoderIndex = GetEncoderClsid(L"image/jpeg", &encoderClsid);
            }

            if (encoderIndex < 0)
            {
                return false;
            }

            // Set JPEG quality if needed
            if (format == Gdiplus::ImageFormatJPEG)
            {
                Gdiplus::EncoderParameters encoderParams;
                ULONG qualityValue = quality;
                encoderParams.Count = 1;
                encoderParams.Parameter[0].Guid = Gdiplus::EncoderQuality;
                encoderParams.Parameter[0].Type = Gdiplus::EncoderParameterValueTypeLong;
                encoderParams.Parameter[0].NumberOfValues = 1;
                encoderParams.Parameter[0].Value = &qualityValue;

                result = (bitmap.Save(destFile, &encoderClsid, &encoderParams) == Gdiplus::Ok);
            }
            else
            {
                result = (bitmap.Save(destFile, &encoderClsid) == Gdiplus::Ok);
            }
        }
        catch (...)
        {
            result = false;
        }

        return result;
    }

    // ============================================================================
    // ORIGINAL SAVEIMAGE - Kept for compatibility (with per-call GDI+ init)
    // ============================================================================
    bool FFmpegThumbnailHelper::SaveImage(
        AVFrame *frame,
        int width,
        int height,
        const wchar_t *destFile,
        REFGUID format,
        int quality)
    {
        // Initialize GDI+
        Gdiplus::GdiplusStartupInput gdiplusStartupInput;
        ULONG_PTR gdiplusToken;
        Gdiplus::GdiplusStartup(&gdiplusToken, &gdiplusStartupInput, nullptr);

        bool result = false;

        try
        {
            // Create a GDI+ bitmap
            Gdiplus::Bitmap bitmap(width, height, PixelFormat24bppRGB);

            // Lock the bitmap for writing
            Gdiplus::BitmapData bitmapData;
            Gdiplus::Rect rect(0, 0, width, height);
            bitmap.LockBits(&rect, Gdiplus::ImageLockModeWrite, PixelFormat24bppRGB, &bitmapData);

            // Copy pixel data from FFmpeg frame to GDI+ bitmap
            for (int y = 0; y < height; y++)
            {
                uint8_t *srcLine = frame->data[0] + y * frame->linesize[0];
                uint8_t *dstLine = (uint8_t *)bitmapData.Scan0 + y * bitmapData.Stride;

                for (int x = 0; x < width; x++)
                {
                    // RGB24 format: R, G, B
                    dstLine[x * 3 + 2] = srcLine[x * 3 + 0]; // R
                    dstLine[x * 3 + 1] = srcLine[x * 3 + 1]; // G
                    dstLine[x * 3 + 0] = srcLine[x * 3 + 2]; // B
                }
            }

            // Unlock the bitmap
            bitmap.UnlockBits(&bitmapData);

            // Get encoder CLSID
            CLSID encoderClsid;
            int encoderIndex = -1;

            if (format == Gdiplus::ImageFormatPNG)
            {
                encoderIndex = GetEncoderClsid(L"image/png", &encoderClsid);
            }
            else
            {
                encoderIndex = GetEncoderClsid(L"image/jpeg", &encoderClsid);
            }

            if (encoderIndex < 0)
            {
                throw std::runtime_error("Failed to find image encoder");
            }

            // Set JPEG quality if needed
            if (format == Gdiplus::ImageFormatJPEG)
            {
                Gdiplus::EncoderParameters encoderParams;
                ULONG qualityValue = quality;

                encoderParams.Count = 1;
                encoderParams.Parameter[0].Guid = Gdiplus::EncoderQuality;
                encoderParams.Parameter[0].Type = Gdiplus::EncoderParameterValueTypeLong;
                encoderParams.Parameter[0].NumberOfValues = 1;
                encoderParams.Parameter[0].Value = &qualityValue;

                result = (bitmap.Save(destFile, &encoderClsid, &encoderParams) == Gdiplus::Ok);
            }
            else
            {
                result = (bitmap.Save(destFile, &encoderClsid) == Gdiplus::Ok);
            }
        }
        catch (const std::exception &)
        {
            result = false;
        }

        // Shutdown GDI+
        Gdiplus::GdiplusShutdown(gdiplusToken);

        return result;
    }

    // ============================================================================
    // FAST INTERNAL EXTRACTION - Hardware decode + low-res + optimized seeking
    // ============================================================================
    std::string FFmpegThumbnailHelper::ExtractThumbnailFastInternal(
        const wchar_t *srcFile,
        const wchar_t *destFile,
        int width,
        REFGUID format,
        double percentage,
        int quality,
        bool useHwAccel)
    {
        (void)useHwAccel; // Ignored - pure software decoding for reliability
        const std::string srcFileUtf8 = WideToUtf8(srcFile);
        ThumbTiming timing("pct", srcFileUtf8);
        AVFormatContext *formatContext = nullptr;
        AVCodecContext *codecContext = nullptr;
        AVPacket *packet = nullptr;
        AVFrame *frame = nullptr;
        AVFrame *rgbFrame = nullptr;
        uint8_t *buffer = nullptr;
        SwsContext *swsContext = nullptr;

        try
        {
            // ================================================================
            // STEP 1: FAST FORMAT OPEN - Optimized probing for speed vs reliability
            // ================================================================
            AVDictionary *opts = nullptr;
            av_dict_set(&opts, "analyzeduration", "2000000", 0);  // 2s max for reliability
            av_dict_set(&opts, "probesize", "2000000", 0);       // 2MB max probe

            if (avformat_open_input(&formatContext, srcFileUtf8.c_str(), nullptr, &opts) != 0)
            {
                av_dict_free(&opts);
                return timing.Finish("Failed to open input file");
            }
            av_dict_free(&opts);
            timing.Mark(ThumbTiming::kOpen);

            // ================================================================
            // STEP 2: FAST STREAM INFO - Limited analysis
            // ================================================================
            AVDictionary *streamOpts = nullptr;
            av_dict_set(&streamOpts, "max_analyze_duration", "500000", 0);
            if (avformat_find_stream_info(formatContext, nullptr) < 0)
            {
                av_dict_free(&streamOpts);
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to find stream info");
            }
            av_dict_free(&streamOpts);
            timing.Mark(ThumbTiming::kProbe);

            // Find the first video stream
            int videoStreamIndex = -1;
            for (unsigned int i = 0; i < formatContext->nb_streams; i++)
            {
                if (formatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO)
                {
                    videoStreamIndex = i;
                    break;
                }
            }

            if (videoStreamIndex == -1)
            {
                avformat_close_input(&formatContext);
                return timing.Finish("No video stream found");
            }

            // Get duration
            double durationSeconds = -1.0;
            if (formatContext->duration != AV_NOPTS_VALUE)
            {
                durationSeconds = static_cast<double>(formatContext->duration) / AV_TIME_BASE;
            }
            else
            {
                AVStream *stream = formatContext->streams[videoStreamIndex];
                if (stream->duration != AV_NOPTS_VALUE)
                {
                    durationSeconds = static_cast<double>(stream->duration) * av_q2d(stream->time_base);
                }
            }

            // Calculate target timestamp
            int timeSeconds = 5;
            if (durationSeconds > 0)
            {
                double validPercentage = percentage;
                if (validPercentage < 0.0) validPercentage = 0.0;
                if (validPercentage > 100.0) validPercentage = 100.0;

                // Clamp to safe range (10% to 90%)
                if (validPercentage < 10.0) validPercentage = 10.0;
                if (validPercentage > 90.0) validPercentage = 90.0;

                timeSeconds = static_cast<int>((validPercentage / 100.0) * durationSeconds);

                int minTime = 5;
                int maxTime = static_cast<int>(durationSeconds) - 5;
                if (maxTime < minTime) maxTime = static_cast<int>(durationSeconds / 2);
                if (timeSeconds < minTime) timeSeconds = minTime;
                if (timeSeconds > maxTime) timeSeconds = maxTime;
            }

            // Get the codec parameters
            AVCodecParameters *codecParams = formatContext->streams[videoStreamIndex]->codecpar;
            // Held until this function returns and the decoder is freed.
            const auto largePictureLock = LockIfLargePicture(codecParams);
            timing.Mark(ThumbTiming::kLock);

            // Use PURE SOFTWARE decoding for maximum compatibility
            // Hardware decoders (D3D11VA/DXVA2) fail on corrupted/mixed-reference streams
            // which causes the console spam and "no frame!" errors
            const AVCodec *codec = avcodec_find_decoder(codecParams->codec_id);

            if (!codec)
            {
                avformat_close_input(&formatContext);
                return timing.Finish("Unsupported codec");
            }

            // Create codec context
            codecContext = avcodec_alloc_context3(codec);
            if (!codecContext)
            {
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to allocate codec context");
            }

            // Copy parameters
            if (avcodec_parameters_to_context(codecContext, codecParams) < 0)
            {
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to copy codec parameters");
            }

            // Slice threading only: a thumbnail needs one picture. Frame
            // threading held back output until four packets were decoded and
            // gave each thread its own picture buffers, so four workers on
            // 4K/8K videos peaked at several GB.
            codecContext->thread_count = 4;
            codecContext->thread_type = FF_THREAD_SLICE;

            // ================================================================
            // STEP 3: RELIABLE SEEKING - Always use AVSEEK_FLAG_BACKWARD
            // This ensures we seek to a keyframe for clean decoding
            // AVSEEK_FLAG_ANY causes decoder errors on non-keyframe positions
            // ================================================================
            int64_t seekTarget = static_cast<int64_t>(timeSeconds) * AV_TIME_BASE;

            // Always seek to keyframe for clean decoding
            int seekResult = av_seek_frame(formatContext, -1, seekTarget, AVSEEK_FLAG_BACKWARD);

            if (seekResult < 0)
            {
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to seek to timestamp");
            }

            // Open the codec
            if (avcodec_open2(codecContext, codec, nullptr) < 0)
            {
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to open codec");
            }

            // Flush decoder buffers
            avcodec_flush_buffers(codecContext);
            timing.Mark(ThumbTiming::kSeek);

            // ================================================================
            // STEP 4: FAST FRAME DECODING - Limited search
            // ================================================================
            packet = av_packet_alloc();
            frame = av_frame_alloc();
            const bool frameFound = DecodeFirstVideoFrame(
                formatContext, codecContext, videoStreamIndex, packet, frame);

            if (!frameFound)
            {
                av_frame_free(&frame);
                av_packet_free(&packet);
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to find video frame");
            }
            timing.Mark(ThumbTiming::kDecode);

            // ================================================================
            // STEP 5: CALCULATE OUTPUT SIZE - width is the longest edge
            // ================================================================
            int originalWidth = codecContext->width;
            int originalHeight = codecContext->height;

            // Calculate output dimensions - we scale during swscale, not in codec
            int outputWidth = 0;
            int outputHeight = 0;
            ComputeThumbnailOutputSize(originalWidth, originalHeight, width,
                                       &outputWidth, &outputHeight);
            timing.SetSizes(originalWidth, originalHeight, outputWidth, outputHeight);

            // ================================================================
            // STEP 6: ALLOCATE RGB FRAME
            // ================================================================
            rgbFrame = av_frame_alloc();
            if (!rgbFrame)
            {
                av_frame_free(&frame);
                av_packet_free(&packet);
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to allocate RGB frame");
            }

            int bufferSize = av_image_get_buffer_size(AV_PIX_FMT_RGB24, outputWidth, outputHeight, 1);
            buffer = (uint8_t *)av_malloc(bufferSize);
            if (!buffer)
            {
                av_frame_free(&rgbFrame);
                av_frame_free(&frame);
                av_packet_free(&packet);
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to allocate RGB buffer");
            }

            av_image_fill_arrays(rgbFrame->data, rgbFrame->linesize, buffer,
                                 AV_PIX_FMT_RGB24, outputWidth, outputHeight, 1);

            // ================================================================
            // STEP 7: SCALE AND CONVERT - SWS_AREA: large downscales alias
            // badly with SWS_FAST_BILINEAR
            // ================================================================
            swsContext = sws_getContext(
                originalWidth, originalHeight, codecContext->pix_fmt,
                outputWidth, outputHeight, AV_PIX_FMT_RGB24,
                SWS_AREA, nullptr, nullptr, nullptr);

            if (!swsContext)
            {
                av_free(buffer);
                av_frame_free(&rgbFrame);
                av_frame_free(&frame);
                av_packet_free(&packet);
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to create scaling context");
            }

            // Perform scaling
            sws_scale(swsContext, frame->data, frame->linesize, 0, originalHeight,
                      rgbFrame->data, rgbFrame->linesize);
            timing.Mark(ThumbTiming::kScale);

            // ================================================================
            // STEP 8: SAVE - Try fast save first, fallback to normal
            // ================================================================
            bool saveResult = SaveImageFast(rgbFrame, outputWidth, outputHeight, destFile, format, quality);

            // If fast save failed (GDI+ not initialized), use normal save
            if (!saveResult)
            {
                saveResult = SaveImage(rgbFrame, outputWidth, outputHeight, destFile, format, quality);
            }
            timing.Mark(ThumbTiming::kSave);

            // Cleanup
            sws_freeContext(swsContext);
            av_free(buffer);
            av_frame_free(&rgbFrame);
            av_frame_free(&frame);
            av_packet_free(&packet);
            avcodec_free_context(&codecContext);
            avformat_close_input(&formatContext);

            if (!saveResult)
            {
                return timing.Finish("Failed to save image");
            }

            return timing.Finish(""); // Success
        }
        catch (const std::exception &e)
        {
            if (swsContext) sws_freeContext(swsContext);
            if (buffer) av_free(buffer);
            if (rgbFrame) av_frame_free(&rgbFrame);
            if (frame) av_frame_free(&frame);
            if (packet) av_packet_free(&packet);
            if (codecContext) avcodec_free_context(&codecContext);
            if (formatContext) avformat_close_input(&formatContext);
            return timing.Finish(std::string("Exception: ") + e.what());
        }
        catch (...)
        {
            if (swsContext) sws_freeContext(swsContext);
            if (buffer) av_free(buffer);
            if (rgbFrame) av_frame_free(&rgbFrame);
            if (frame) av_frame_free(&frame);
            if (packet) av_packet_free(&packet);
            if (codecContext) avcodec_free_context(&codecContext);
            if (formatContext) avformat_close_input(&formatContext);
            return timing.Finish("Unknown exception occurred");
        }
    }

    // ============================================================================
    // PUBLIC API: ExtractThumbnailAtPercentage - Now uses optimized path
    // ============================================================================
    std::string FFmpegThumbnailHelper::ExtractThumbnailAtPercentage(
        const wchar_t *srcFile,
        const wchar_t *destFile,
        int width,
        REFGUID format,
        double percentage,
        int quality)
    {
        // Try fast extraction with hardware acceleration first
        std::string result = ExtractThumbnailFastInternal(
            srcFile, destFile, width, format, percentage, quality, true);

        // If hardware decode failed, try without hardware acceleration
        if (!result.empty())
        {
            result = ExtractThumbnailFastInternal(
                srcFile, destFile, width, format, percentage, quality, false);
        }

        return result;
    }

    // ============================================================================
    // PUBLIC API: ExtractThumbnail - Original API, uses fast path internally
    // ============================================================================
    std::string FFmpegThumbnailHelper::ExtractThumbnail(
        const wchar_t *srcFile,
        const wchar_t *destFile,
        int width,
        REFGUID format,
        int timeSeconds,
        int quality)
    {
        // Convert timeSeconds to percentage
        // For simplicity, use timeSeconds directly in fast internal function
        const std::string srcFileUtf8 = WideToUtf8(srcFile);
        ThumbTiming timing("sec", srcFileUtf8);
        AVFormatContext *formatContext = nullptr;
        AVCodecContext *codecContext = nullptr;
        AVPacket *packet = nullptr;
        AVFrame *frame = nullptr;
        AVFrame *rgbFrame = nullptr;
        uint8_t *buffer = nullptr;
        SwsContext *swsContext = nullptr;

        try
        {
            // Fast probing
            AVDictionary *opts = nullptr;
            av_dict_set(&opts, "analyzeduration", "2000000", 0);
            av_dict_set(&opts, "probesize", "2000000", 0);

            if (avformat_open_input(&formatContext, srcFileUtf8.c_str(), nullptr, &opts) != 0)
            {
                av_dict_free(&opts);
                return timing.Finish("Failed to open input file");
            }
            av_dict_free(&opts);
            timing.Mark(ThumbTiming::kOpen);

            if (avformat_find_stream_info(formatContext, nullptr) < 0)
            {
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to find stream info");
            }
            timing.Mark(ThumbTiming::kProbe);

            // Find video stream
            int videoStreamIndex = -1;
            for (unsigned int i = 0; i < formatContext->nb_streams; i++)
            {
                if (formatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO)
                {
                    videoStreamIndex = i;
                    break;
                }
            }

            if (videoStreamIndex == -1)
            {
                avformat_close_input(&formatContext);
                return timing.Finish("No video stream found");
            }

            // Get duration
            int64_t duration = formatContext->duration > 0 ? formatContext->duration / AV_TIME_BASE : 0;
            if (timeSeconds < 0 || (duration > 0 && static_cast<int64_t>(timeSeconds) > duration))
            {
                timeSeconds = duration > 0 ? static_cast<int>(duration / 3) : 0;
            }

            // Get codec
            AVCodecParameters *codecParams = formatContext->streams[videoStreamIndex]->codecpar;
            const auto largePictureLock = LockIfLargePicture(codecParams);
            timing.Mark(ThumbTiming::kLock);
            const AVCodec *codec = avcodec_find_decoder(codecParams->codec_id);
            if (!codec)
            {
                avformat_close_input(&formatContext);
                return timing.Finish("Unsupported codec");
            }

            // Create codec context
            codecContext = avcodec_alloc_context3(codec);
            if (!codecContext)
            {
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to allocate codec context");
            }

            if (avcodec_parameters_to_context(codecContext, codecParams) < 0)
            {
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to copy codec parameters");
            }

            // Slice threading only, as in the path above.
            codecContext->thread_count = 4;
            codecContext->thread_type = FF_THREAD_SLICE;

            // Seek - always use BACKWARD for reliable keyframe seeking
            int64_t seekTarget = static_cast<int64_t>(timeSeconds) * AV_TIME_BASE;

            int seekResult = av_seek_frame(formatContext, -1, seekTarget, AVSEEK_FLAG_BACKWARD);

            if (seekResult < 0)
            {
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to seek to timestamp");
            }

            if (avcodec_open2(codecContext, codec, nullptr) < 0)
            {
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to open codec");
            }

            avcodec_flush_buffers(codecContext);
            timing.Mark(ThumbTiming::kSeek);

            // Read frames
            packet = av_packet_alloc();
            frame = av_frame_alloc();
            const bool frameFound = DecodeFirstVideoFrame(
                formatContext, codecContext, videoStreamIndex, packet, frame);

            if (!frameFound)
            {
                av_frame_free(&frame);
                av_packet_free(&packet);
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to find video frame");
            }
            timing.Mark(ThumbTiming::kDecode);

            // Calculate output size - width is the longest edge
            int originalWidth = codecContext->width;
            int originalHeight = codecContext->height;
            int outputWidth = 0;
            int outputHeight = 0;
            ComputeThumbnailOutputSize(originalWidth, originalHeight, width,
                                       &outputWidth, &outputHeight);
            timing.SetSizes(originalWidth, originalHeight, outputWidth, outputHeight);

            // Allocate RGB frame
            rgbFrame = av_frame_alloc();
            if (!rgbFrame)
            {
                av_frame_free(&frame);
                av_packet_free(&packet);
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to allocate RGB frame");
            }

            int bufferSize = av_image_get_buffer_size(AV_PIX_FMT_RGB24, outputWidth, outputHeight, 1);
            buffer = (uint8_t *)av_malloc(bufferSize);
            if (!buffer)
            {
                av_frame_free(&rgbFrame);
                av_frame_free(&frame);
                av_packet_free(&packet);
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to allocate RGB buffer");
            }

            av_image_fill_arrays(rgbFrame->data, rgbFrame->linesize, buffer,
                                 AV_PIX_FMT_RGB24, outputWidth, outputHeight, 1);

            // Scale (SWS_AREA, as in the path above)
            swsContext = sws_getContext(
                originalWidth, originalHeight, codecContext->pix_fmt,
                outputWidth, outputHeight, AV_PIX_FMT_RGB24,
                SWS_AREA, nullptr, nullptr, nullptr);

            if (!swsContext)
            {
                av_free(buffer);
                av_frame_free(&rgbFrame);
                av_frame_free(&frame);
                av_packet_free(&packet);
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return timing.Finish("Failed to create scaling context");
            }

            sws_scale(swsContext, frame->data, frame->linesize, 0, originalHeight,
                      rgbFrame->data, rgbFrame->linesize);
            timing.Mark(ThumbTiming::kScale);

            // Save
            bool saveResult = SaveImageFast(rgbFrame, outputWidth, outputHeight, destFile, format, quality);
            if (!saveResult)
            {
                saveResult = SaveImage(rgbFrame, outputWidth, outputHeight, destFile, format, quality);
            }
            timing.Mark(ThumbTiming::kSave);

            // Cleanup
            sws_freeContext(swsContext);
            av_free(buffer);
            av_frame_free(&rgbFrame);
            av_frame_free(&frame);
            av_packet_free(&packet);
            avcodec_free_context(&codecContext);
            avformat_close_input(&formatContext);

            if (!saveResult)
            {
                return timing.Finish("Failed to save image");
            }

            return timing.Finish("");
        }
        catch (const std::exception &e)
        {
            if (swsContext) sws_freeContext(swsContext);
            if (buffer) av_free(buffer);
            if (rgbFrame) av_frame_free(&rgbFrame);
            if (frame) av_frame_free(&frame);
            if (packet) av_packet_free(&packet);
            if (codecContext) avcodec_free_context(&codecContext);
            if (formatContext) avformat_close_input(&formatContext);
            return timing.Finish(std::string("Exception: ") + e.what());
        }
        catch (...)
        {
            if (swsContext) sws_freeContext(swsContext);
            if (buffer) av_free(buffer);
            if (rgbFrame) av_frame_free(&rgbFrame);
            if (frame) av_frame_free(&frame);
            if (packet) av_packet_free(&packet);
            if (codecContext) avcodec_free_context(&codecContext);
            if (formatContext) avformat_close_input(&formatContext);
            return timing.Finish("Unknown exception occurred");
        }
    }

    // ============================================================================
    // HELPER: Wide to UTF8
    // ============================================================================
    std::string FFmpegThumbnailHelper::WideToUtf8(const wchar_t *wide)
    {
        if (!wide)
            return "";

        int size_needed = WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
        if (size_needed <= 0)
            return "";

        std::string utf8(size_needed, 0);
        WideCharToMultiByte(CP_UTF8, 0, wide, -1, &utf8[0], size_needed, nullptr, nullptr);
        utf8.resize(size_needed - 1);
        return utf8;
    }

    // ============================================================================
    // HELPER: Get video duration
    // ============================================================================
    double FFmpegThumbnailHelper::GetVideoDuration(const wchar_t *srcFile)
    {
        const std::string srcFileUtf8 = WideToUtf8(srcFile);
        AVFormatContext *formatContext = nullptr;

        try
        {
            // Fast probing
            AVDictionary *opts = nullptr;
            av_dict_set(&opts, "analyzeduration", "2000000", 0);
            av_dict_set(&opts, "probesize", "2000000", 0);

            if (avformat_open_input(&formatContext, srcFileUtf8.c_str(), nullptr, &opts) != 0)
            {
                av_dict_free(&opts);
                return -1.0;
            }
            av_dict_free(&opts);

            if (avformat_find_stream_info(formatContext, nullptr) < 0)
            {
                avformat_close_input(&formatContext);
                return -1.0;
            }

            double durationSeconds = -1.0;

            if (formatContext->duration != AV_NOPTS_VALUE)
            {
                durationSeconds = static_cast<double>(formatContext->duration) / AV_TIME_BASE;
            }
            else
            {
                for (unsigned int i = 0; i < formatContext->nb_streams; i++)
                {
                    AVStream *stream = formatContext->streams[i];
                    if (stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO)
                    {
                        if (stream->duration != AV_NOPTS_VALUE)
                        {
                            durationSeconds = static_cast<double>(stream->duration) *
                                              av_q2d(stream->time_base);
                        }
                        break;
                    }
                }
            }

            avformat_close_input(&formatContext);
            return durationSeconds;
        }
        catch (const std::exception &)
        {
            if (formatContext)
            {
                avformat_close_input(&formatContext);
            }
            return -1.0;
        }
    }

} // namespace fc_native_video_thumbnail
