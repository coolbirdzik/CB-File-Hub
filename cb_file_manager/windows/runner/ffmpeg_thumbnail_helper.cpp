#include "ffmpeg_thumbnail_helper.h"
#include "fc_native_video_thumbnail_plugin.h"

#include <atlbase.h>
#include <atlimage.h>
#include <codecvt>
#include <locale>
#include <stdexcept>
#include <vector>

namespace fc_native_video_thumbnail
{

    // Forward declaration of GetEncoderClsid from fc_native_video_thumbnail_plugin.cpp
    extern int GetEncoderClsid(const WCHAR *format, CLSID *pClsid);

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
                return "Failed to open input file";
            }
            av_dict_free(&opts);

            // ================================================================
            // STEP 2: FAST STREAM INFO - Limited analysis
            // ================================================================
            AVDictionary *streamOpts = nullptr;
            av_dict_set(&streamOpts, "max_analyze_duration", "500000", 0);
            if (avformat_find_stream_info(formatContext, nullptr) < 0)
            {
                av_dict_free(&streamOpts);
                avformat_close_input(&formatContext);
                return "Failed to find stream info";
            }
            av_dict_free(&streamOpts);

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
                return "No video stream found";
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

            // Use PURE SOFTWARE decoding for maximum compatibility
            // Hardware decoders (D3D11VA/DXVA2) fail on corrupted/mixed-reference streams
            // which causes the console spam and "no frame!" errors
            const AVCodec *codec = avcodec_find_decoder(codecParams->codec_id);

            if (!codec)
            {
                avformat_close_input(&formatContext);
                return "Unsupported codec";
            }

            // Create codec context
            codecContext = avcodec_alloc_context3(codec);
            if (!codecContext)
            {
                avformat_close_input(&formatContext);
                return "Failed to allocate codec context";
            }

            // Copy parameters
            if (avcodec_parameters_to_context(codecContext, codecParams) < 0)
            {
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return "Failed to copy codec parameters";
            }

            // Enable multithreaded decoding
            codecContext->thread_count = 4;
            codecContext->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;

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
                return "Failed to seek to timestamp";
            }

            // Open the codec
            if (avcodec_open2(codecContext, codec, nullptr) < 0)
            {
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return "Failed to open codec";
            }

            // Flush decoder buffers
            avcodec_flush_buffers(codecContext);

            // ================================================================
            // STEP 4: FAST FRAME DECODING - Limited search
            // ================================================================
            packet = av_packet_alloc();
            frame = av_frame_alloc();
            bool frameFound = false;

            // Read frames with limit to avoid infinite loops
            int frameCount = 0;
            while (av_read_frame(formatContext, packet) >= 0)
            {
                if (packet->stream_index == videoStreamIndex)
                {
                    int sendResult = avcodec_send_packet(codecContext, packet);
                    if (sendResult == 0)
                    {
                        int receiveResult = avcodec_receive_frame(codecContext, frame);
                        if (receiveResult == 0)
                        {
                            frameFound = true;
                            break;
                        }
                    }
                }
                av_packet_unref(packet);

                // Limit search to 30 frames max for speed
                frameCount++;
                if (frameCount > 30)
                    break;

                // Also limit by time
                if (av_q2d(formatContext->streams[videoStreamIndex]->time_base) * packet->pts >
                    timeSeconds + 10)
                {
                    break;
                }
            }

            if (!frameFound)
            {
                av_frame_free(&frame);
                av_packet_free(&packet);
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return "Failed to find video frame";
            }

            // ================================================================
            // STEP 5: CALCULATE OUTPUT SIZE - Target thumbnail size
            // ================================================================
            int originalWidth = codecContext->width;
            int originalHeight = codecContext->height;

            // Calculate output dimensions - we scale during swscale, not in codec
            int outputWidth, outputHeight;

            if (width <= 0)
            {
                outputWidth = originalWidth;
                outputHeight = originalHeight;
            }
            else
            {
                // For thumbnail speed, scale to thumbnail size directly
                // This avoids decoding full resolution and then scaling
                if (originalWidth > 1920 && width < originalWidth / 2)
                {
                    outputWidth = originalWidth / 2;
                    outputHeight = originalHeight / 2;
                }
                else if (originalWidth > 1280 && width < originalWidth / 3)
                {
                    outputWidth = originalWidth / 3;
                    outputHeight = originalHeight / 3;
                }
                else
                {
                    outputWidth = width;
                    outputHeight = (int)(((float)originalHeight / originalWidth) * width);
                }
            }

            if (outputWidth <= 0) outputWidth = originalWidth;
            if (outputHeight <= 0) outputHeight = originalHeight;

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
                return "Failed to allocate RGB frame";
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
                return "Failed to allocate RGB buffer";
            }

            av_image_fill_arrays(rgbFrame->data, rgbFrame->linesize, buffer,
                                 AV_PIX_FMT_RGB24, outputWidth, outputHeight, 1);

            // ================================================================
            // STEP 7: SCALE AND CONVERT - Use SWS_FAST_BILINEAR for speed
            // ================================================================
            swsContext = sws_getContext(
                originalWidth, originalHeight, codecContext->pix_fmt,
                outputWidth, outputHeight, AV_PIX_FMT_RGB24,
                SWS_FAST_BILINEAR, nullptr, nullptr, nullptr);

            if (!swsContext)
            {
                av_free(buffer);
                av_frame_free(&rgbFrame);
                av_frame_free(&frame);
                av_packet_free(&packet);
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return "Failed to create scaling context";
            }

            // Perform scaling
            sws_scale(swsContext, frame->data, frame->linesize, 0, originalHeight,
                      rgbFrame->data, rgbFrame->linesize);

            // ================================================================
            // STEP 8: SAVE - Try fast save first, fallback to normal
            // ================================================================
            bool saveResult = SaveImageFast(rgbFrame, outputWidth, outputHeight, destFile, format, quality);

            // If fast save failed (GDI+ not initialized), use normal save
            if (!saveResult)
            {
                saveResult = SaveImage(rgbFrame, outputWidth, outputHeight, destFile, format, quality);
            }

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
                return "Failed to save image";
            }

            return ""; // Success
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
            return std::string("Exception: ") + e.what();
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
            return "Unknown exception occurred";
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
                return "Failed to open input file";
            }
            av_dict_free(&opts);

            if (avformat_find_stream_info(formatContext, nullptr) < 0)
            {
                avformat_close_input(&formatContext);
                return "Failed to find stream info";
            }

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
                return "No video stream found";
            }

            // Get duration
            int64_t duration = formatContext->duration > 0 ? formatContext->duration / AV_TIME_BASE : 0;
            if (timeSeconds < 0 || (duration > 0 && static_cast<int64_t>(timeSeconds) > duration))
            {
                timeSeconds = duration > 0 ? static_cast<int>(duration / 3) : 0;
            }

            // Get codec
            AVCodecParameters *codecParams = formatContext->streams[videoStreamIndex]->codecpar;
            const AVCodec *codec = avcodec_find_decoder(codecParams->codec_id);
            if (!codec)
            {
                avformat_close_input(&formatContext);
                return "Unsupported codec";
            }

            // Create codec context
            codecContext = avcodec_alloc_context3(codec);
            if (!codecContext)
            {
                avformat_close_input(&formatContext);
                return "Failed to allocate codec context";
            }

            if (avcodec_parameters_to_context(codecContext, codecParams) < 0)
            {
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return "Failed to copy codec parameters";
            }

            // Enable multithreaded decoding
            codecContext->thread_count = 4;
            codecContext->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;

            // Seek - always use BACKWARD for reliable keyframe seeking
            int64_t seekTarget = static_cast<int64_t>(timeSeconds) * AV_TIME_BASE;

            int seekResult = av_seek_frame(formatContext, -1, seekTarget, AVSEEK_FLAG_BACKWARD);

            if (seekResult < 0)
            {
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return "Failed to seek to timestamp";
            }

            if (avcodec_open2(codecContext, codec, nullptr) < 0)
            {
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return "Failed to open codec";
            }

            avcodec_flush_buffers(codecContext);

            // Read frames
            packet = av_packet_alloc();
            frame = av_frame_alloc();
            bool frameFound = false;

            while (av_read_frame(formatContext, packet) >= 0)
            {
                if (packet->stream_index == videoStreamIndex)
                {
                    if (avcodec_send_packet(codecContext, packet) == 0)
                    {
                        if (avcodec_receive_frame(codecContext, frame) == 0)
                        {
                            frameFound = true;
                            break;
                        }
                    }
                }
                av_packet_unref(packet);

                if (av_q2d(formatContext->streams[videoStreamIndex]->time_base) * packet->pts >
                    timeSeconds + 10)
                {
                    break;
                }
            }

            if (!frameFound)
            {
                av_frame_free(&frame);
                av_packet_free(&packet);
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return "Failed to find video frame";
            }

            // Calculate output size
            int originalWidth = codecContext->width;
            int originalHeight = codecContext->height;
            int outputWidth, outputHeight;

            if (width <= 0)
            {
                outputWidth = originalWidth;
                outputHeight = originalHeight;
            }
            else if (width < 0)
            {
                float percentage = abs(width) / 100.0f;
                outputWidth = (int)(originalWidth * percentage);
                outputHeight = (int)(originalHeight * percentage);
            }
            else
            {
                if (originalWidth > 1920 && width < originalWidth / 2)
                {
                    outputWidth = originalWidth / 2;
                    outputHeight = originalHeight / 2;
                }
                else if (originalWidth > 1280 && width < originalWidth / 3)
                {
                    outputWidth = originalWidth / 3;
                    outputHeight = originalHeight / 3;
                }
                else
                {
                    outputWidth = width;
                    outputHeight = (int)(((float)originalHeight / originalWidth) * width);
                }
            }

            if (outputWidth <= 0) outputWidth = originalWidth;
            if (outputHeight <= 0) outputHeight = originalHeight;

            // Allocate RGB frame
            rgbFrame = av_frame_alloc();
            if (!rgbFrame)
            {
                av_frame_free(&frame);
                av_packet_free(&packet);
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return "Failed to allocate RGB frame";
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
                return "Failed to allocate RGB buffer";
            }

            av_image_fill_arrays(rgbFrame->data, rgbFrame->linesize, buffer,
                                 AV_PIX_FMT_RGB24, outputWidth, outputHeight, 1);

            // Scale
            swsContext = sws_getContext(
                originalWidth, originalHeight, codecContext->pix_fmt,
                outputWidth, outputHeight, AV_PIX_FMT_RGB24,
                SWS_FAST_BILINEAR, nullptr, nullptr, nullptr);

            if (!swsContext)
            {
                av_free(buffer);
                av_frame_free(&rgbFrame);
                av_frame_free(&frame);
                av_packet_free(&packet);
                avcodec_free_context(&codecContext);
                avformat_close_input(&formatContext);
                return "Failed to create scaling context";
            }

            sws_scale(swsContext, frame->data, frame->linesize, 0, originalHeight,
                      rgbFrame->data, rgbFrame->linesize);

            // Save
            bool saveResult = SaveImageFast(rgbFrame, outputWidth, outputHeight, destFile, format, quality);
            if (!saveResult)
            {
                saveResult = SaveImage(rgbFrame, outputWidth, outputHeight, destFile, format, quality);
            }

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
                return "Failed to save image";
            }

            return "";
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
            return std::string("Exception: ") + e.what();
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
            return "Unknown exception occurred";
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
