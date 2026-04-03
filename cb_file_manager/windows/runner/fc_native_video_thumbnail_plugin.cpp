#include "fc_native_video_thumbnail_plugin.h"
#include "ffmpeg_thumbnail_helper.h"
#include <atlimage.h>
#include <comdef.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <gdiplus.h>
#include <gdiplusimaging.h>
#include <shlwapi.h>
#include <thumbcache.h>
#include <wincodec.h>
#include <windows.h>
#include <wingdi.h>
// MediaFoundation headers for timestamp-based extraction
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <propvarutil.h>

#include <codecvt>
#include <iostream>
#include <locale>
#include <memory>
#include <sstream>
#include <string>
#include <filesystem>
#include <fstream>
#include <algorithm>
#include <thread>

const std::string kGetThumbnailFailedExtraction = "Failed extraction";

// Need to link with these libraries for MediaFoundation
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "propsys.lib")

namespace fc_native_video_thumbnail
{

  // Static member definitions
  std::mutex FcNativeVideoThumbnailPlugin::gdiMutex_;
  bool FcNativeVideoThumbnailPlugin::gdiInitialized_ = false;
  ULONG_PTR FcNativeVideoThumbnailPlugin::gdiplusToken_ = 0;
  int FcNativeVideoThumbnailPlugin::instanceCount_ = 0;

  const flutter::EncodableValue *ValueOrNull(const flutter::EncodableMap &map, const char *key)
  {
    auto it = map.find(flutter::EncodableValue(key));
    if (it == map.end())
    {
      return nullptr;
    }
    return &(it->second);
  }

  std::optional<int64_t> GetInt64ValueOrNull(const flutter::EncodableMap &map,
                                             const char *key)
  {
    auto value = ValueOrNull(map, key);
    if (!value)
    {
      return std::nullopt;
    }

    if (std::holds_alternative<int32_t>(*value))
    {
      return static_cast<int64_t>(std::get<int32_t>(*value));
    }
    auto val64 = std::get_if<int64_t>(value);
    if (!val64)
    {
      return std::nullopt;
    }
    return *val64;
  }

  std::wstring Utf16FromUtf8(const std::string &utf8_string)
  {
    if (utf8_string.empty())
    {
      return std::wstring();
    }
    int target_length =
        ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(),
                              static_cast<int>(utf8_string.length()), nullptr, 0);
    if (target_length == 0)
    {
      return std::wstring();
    }
    std::wstring utf16_string;
    utf16_string.resize(target_length);
    int converted_length =
        ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(),
                              static_cast<int>(utf8_string.length()),
                              utf16_string.data(), target_length);
    if (converted_length == 0)
    {
      return std::wstring();
    }
    return utf16_string;
  }

  std::wstring NormalizeWindowsPathFromUtf8(const std::string &utf8_path)
  {
    auto wide = Utf16FromUtf8(utf8_path);
    if (wide.empty())
    {
      return std::wstring();
    }

    std::replace(wide.begin(), wide.end(), L'/', L'\\');

    DWORD length = GetFullPathNameW(wide.c_str(), 0, nullptr, nullptr);
    if (length == 0)
    {
      return wide;
    }

    std::wstring fullPath(length, L'\0');
    DWORD written = GetFullPathNameW(wide.c_str(), length, fullPath.data(), nullptr);
    if (written == 0)
    {
      return wide;
    }

    if (!fullPath.empty() && fullPath.back() == L'\0')
    {
      fullPath.pop_back();
    }

    return fullPath;
  }

  std::wstring AddLongPathPrefix(const std::wstring &path)
  {
    if (path.empty())
    {
      return path;
    }

    if (path.rfind(L"\\\\?\\", 0) == 0)
    {
      return path;
    }

    if (path.rfind(L"\\\\", 0) == 0)
    {
      return L"\\\\?\\UNC\\" + path.substr(2);
    }

    if (path.size() >= 2 && path[1] == L':')
    {
      return L"\\\\?\\" + path;
    }

    return path;
  }

  bool FileExistsWide(const std::wstring &path)
  {
    DWORD attrs = GetFileAttributesW(path.c_str());
    if (attrs != INVALID_FILE_ATTRIBUTES)
    {
      return true;
    }

    const auto longPath = AddLongPathPrefix(path);
    if (longPath != path)
    {
      attrs = GetFileAttributesW(longPath.c_str());
      return attrs != INVALID_FILE_ATTRIBUTES;
    }

    return false;
  }

  std::filesystem::path PathFromUtf8(const std::string &utf8_path)
  {
    if (utf8_path.empty())
    {
      return std::filesystem::path();
    }

    auto wide = NormalizeWindowsPathFromUtf8(utf8_path);
    if (!wide.empty())
    {
      return std::filesystem::path(wide);
    }

    return std::filesystem::path(utf8_path);
  }

  std::string HRESULTToString(HRESULT hr)
  {
    _com_error error(hr);
    CString cs;
    cs.Format(_T("Error 0x%08x: %s"), hr, error.ErrorMessage());

    std::string res;

#ifdef UNICODE
    int wlen = lstrlenW(cs);
    int len = WideCharToMultiByte(CP_ACP, 0, cs, wlen, NULL, 0, NULL, NULL);
    res.resize(len);
    WideCharToMultiByte(CP_ACP, 0, cs, wlen, &res[0], len, NULL, NULL);
#else
    res = errMsg;
#endif
    return res;
  }

  int GetEncoderClsid(const WCHAR *format, CLSID *pClsid)
  {
    UINT num = 0;
    UINT size = 0;

    Gdiplus::ImageCodecInfo *pImageCodecInfo = NULL;

    Gdiplus::GetImageEncodersSize(&num, &size);
    if (size == 0)
      return -1;

    pImageCodecInfo = (Gdiplus::ImageCodecInfo *)(malloc(size));
    if (pImageCodecInfo == NULL)
      return -1;

    Gdiplus::GetImageEncoders(num, size, pImageCodecInfo);

    for (UINT j = 0; j < num; ++j)
    {
      if (wcscmp(pImageCodecInfo[j].MimeType, format) == 0)
      {
        *pClsid = pImageCodecInfo[j].Clsid;
        free(pImageCodecInfo);
        return j;
      }
    }

    free(pImageCodecInfo);
    return -1;
  }

  HRESULT SetReaderOutputSubtype(IMFSourceReader *reader, REFGUID subtype)
  {
    IMFMediaType *pMediaType = NULL;
    HRESULT hr = MFCreateMediaType(&pMediaType);
    if (SUCCEEDED(hr))
    {
      hr = pMediaType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    }
    if (SUCCEEDED(hr))
    {
      hr = pMediaType->SetGUID(MF_MT_SUBTYPE, subtype);
    }
    if (SUCCEEDED(hr))
    {
      hr = reader->SetCurrentMediaType(
          (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, NULL, pMediaType);
    }
    if (pMediaType)
    {
      pMediaType->Release();
    }
    return hr;
  }

  // Using existing MediaFoundation extraction as fallback option
  std::string ExtractVideoFrameAtTime(PCWSTR srcFile, PCWSTR destFile, int width, REFGUID format, int timeSeconds, int quality)
  {
    // Original MediaFoundation extraction implementation with improved quality

    // Initialize MediaFoundation
    HRESULT hr = MFStartup(MF_VERSION);
    if (!SUCCEEDED(hr))
    {
      return "MFStartup failed with " + HRESULTToString(hr);
    }

    // Initialize GDI+
    Gdiplus::GdiplusStartupInput gdiplusStartupInput;
    ULONG_PTR gdiplusToken;
    Gdiplus::GdiplusStartup(&gdiplusToken, &gdiplusStartupInput, NULL);

    IMFAttributes *pAttributes = NULL;
    hr = MFCreateAttributes(&pAttributes, 2);
    if (SUCCEEDED(hr))
    {
      pAttributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
      pAttributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
    }

    IMFSourceReader *pReader = NULL;
    hr = MFCreateSourceReaderFromURL(srcFile, pAttributes, &pReader);
    if (pAttributes)
    {
      pAttributes->Release();
    }
    if (!SUCCEEDED(hr))
    {
      MFShutdown();
      Gdiplus::GdiplusShutdown(gdiplusToken);
      return "MFCreateSourceReaderFromURL failed with " + HRESULTToString(hr);
    }

    // Configure the source reader to give us progressive RGB32/ARGB32 frames
    GUID outputSubtype = MFVideoFormat_RGB32;
    hr = SetReaderOutputSubtype(pReader, MFVideoFormat_RGB32);
    if (!SUCCEEDED(hr))
    {
      hr = SetReaderOutputSubtype(pReader, MFVideoFormat_ARGB32);
      if (SUCCEEDED(hr))
      {
        outputSubtype = MFVideoFormat_ARGB32;
      }
    }
    if (!SUCCEEDED(hr))
    {
      pReader->Release();
      MFShutdown();
      Gdiplus::GdiplusShutdown(gdiplusToken);
      return "SetCurrentMediaType failed with " + HRESULTToString(hr);
    }

    // Calculate the time offset to seek to
    PROPVARIANT var;
    PropVariantInit(&var);
    var.vt = VT_I8;

    // Convert from seconds to 100-nanosecond units
    var.hVal.QuadPart = timeSeconds * 10000000LL;
    hr = pReader->SetCurrentPosition(GUID_NULL, var);
    PropVariantClear(&var);

    if (!SUCCEEDED(hr))
    {
      pReader->Release();
      MFShutdown();
      Gdiplus::GdiplusShutdown(gdiplusToken);
      return "SetCurrentPosition failed with " + HRESULTToString(hr);
    }

    // Try to find a keyframe by reading multiple samples if needed
    IMFSample *pSample = NULL;
    bool foundGoodFrame = false;
    int maxAttempts = 30; // Try reading more frames to find a better one

    for (int attempt = 0; attempt < maxAttempts; attempt++)
    {
      // Get the next sample
      DWORD streamIndex, flags;
      LONGLONG timestamp;

      if (pSample)
      {
        pSample->Release();
        pSample = NULL;
      }

      hr = pReader->ReadSample((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,
                               0, &streamIndex, &flags, &timestamp, &pSample);

      if (!SUCCEEDED(hr) || !pSample)
      {
        // If we can't read any more samples but already found one, use what we have
        if (foundGoodFrame)
        {
          break;
        }

        if (pSample)
        {
          pSample->Release();
        }
        pReader->Release();
        MFShutdown();
        Gdiplus::GdiplusShutdown(gdiplusToken);
        return "ReadSample failed with " + HRESULTToString(hr);
      }

      // Check if this is a good frame (not a repeat frame or too dark)
      foundGoodFrame = true;

      // If we've gone too far past our target time, stop
      if (attempt > 0 && timestamp > (timeSeconds + 2) * 10000000LL)
      {
        break;
      }
    }

    if (!pSample)
    {
      pReader->Release();
      MFShutdown();
      Gdiplus::GdiplusShutdown(gdiplusToken);
      return "Failed to find a suitable video frame";
    }

    IMFMediaBuffer *pBuffer = NULL;
    hr = pSample->ConvertToContiguousBuffer(&pBuffer);
    if (!SUCCEEDED(hr) || !pBuffer)
    {
      if (pBuffer)
      {
        pBuffer->Release();
      }
      pSample->Release();
      pReader->Release();
      MFShutdown();
      Gdiplus::GdiplusShutdown(gdiplusToken);
      return "ConvertToContiguousBuffer failed with " + HRESULTToString(hr);
    }

    DWORD maxSize = 0;
    DWORD curSize = 0;
    BYTE *data = NULL;
    hr = pBuffer->Lock(&data, &maxSize, &curSize);

    if (!SUCCEEDED(hr) || !data)
    {
      pBuffer->Release();
      pSample->Release();
      pReader->Release();
      MFShutdown();
      Gdiplus::GdiplusShutdown(gdiplusToken);
      return "Buffer->Lock failed with " + HRESULTToString(hr);
    }

    // Get the media type after ReadSample to get the real frame dimensions
    IMFMediaType *pType = NULL;
    hr = pReader->GetCurrentMediaType((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,
                                      &pType);
    if (!SUCCEEDED(hr) || !pType)
    {
      pBuffer->Unlock();
      pBuffer->Release();
      pSample->Release();
      pReader->Release();
      MFShutdown();
      Gdiplus::GdiplusShutdown(gdiplusToken);
      return "GetCurrentMediaType failed with " + HRESULTToString(hr);
    }

    UINT32 videoWidth, videoHeight;
    hr = MFGetAttributeSize(pType, MF_MT_FRAME_SIZE, &videoWidth, &videoHeight);
    pType->Release();

    if (!SUCCEEDED(hr))
    {
      pBuffer->Unlock();
      pBuffer->Release();
      pSample->Release();
      pReader->Release();
      MFShutdown();
      Gdiplus::GdiplusShutdown(gdiplusToken);
      return "MFGetAttributeSize failed with " + HRESULTToString(hr);
    }

    // Create a GDI+ bitmap from the RGB32 frame data
    auto pixelFormat = outputSubtype == MFVideoFormat_ARGB32 ? PixelFormat32bppARGB : PixelFormat32bppRGB;
    Gdiplus::Bitmap *pGdiPlusBitmap = new Gdiplus::Bitmap(videoWidth, videoHeight, pixelFormat);
    if (!pGdiPlusBitmap)
    {
      pBuffer->Unlock();
      pBuffer->Release();
      pSample->Release();
      pReader->Release();
      MFShutdown();
      Gdiplus::GdiplusShutdown(gdiplusToken);
      return "Failed to create GDI+ bitmap";
    }

    // Copy the pixel data to the bitmap
    Gdiplus::BitmapData bitmapData;
    Gdiplus::Rect rect(0, 0, videoWidth, videoHeight);
    if (pGdiPlusBitmap->LockBits(&rect, Gdiplus::ImageLockModeWrite, pixelFormat, &bitmapData) == Gdiplus::Ok)
    {
      BYTE *pDest = (BYTE *)bitmapData.Scan0;
      BYTE *pSrc = data;
      int stride = bitmapData.Stride;

      for (UINT y = 0; y < videoHeight; y++)
      {
        memcpy(pDest, pSrc, videoWidth * 4);
        pDest += stride;
        pSrc += videoWidth * 4;
      }

      pGdiPlusBitmap->UnlockBits(&bitmapData);
    }
    else
    {
      delete pGdiPlusBitmap;
      pBuffer->Unlock();
      pBuffer->Release();
      pSample->Release();
      pReader->Release();
      MFShutdown();
      Gdiplus::GdiplusShutdown(gdiplusToken);
      return "Failed to lock GDI+ bitmap bits";
    }

    // Apply image enhancement to improve thumbnail quality
    Gdiplus::ColorMatrix enhancementMatrix = {
        1.05f, 0.0f, 0.0f, 0.0f, 0.0f, // Slightly increase red channel
        0.0f, 1.05f, 0.0f, 0.0f, 0.0f, // Slightly increase green channel
        0.0f, 0.0f, 1.1f, 0.0f, 0.0f,  // Slightly increase blue channel
        0.0f, 0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f, 0.0f, 1.0f};

    Gdiplus::ImageAttributes imgAttributes;
    imgAttributes.SetColorMatrix(&enhancementMatrix, Gdiplus::ColorMatrixFlagsDefault, Gdiplus::ColorAdjustTypeBitmap);

    // Smart thumbnail sizing based on original video resolution
    int thumbnailWidth, thumbnailHeight;

    if (width <= 0)
    {
      // Use original resolution
      thumbnailWidth = videoWidth;
      thumbnailHeight = videoHeight;
    }
    else if (width < 0)
    {
      // Use percentage of original
      float percentage = abs(width) / 100.0f;
      thumbnailWidth = (int)(videoWidth * percentage);
      thumbnailHeight = (int)(videoHeight * percentage);
    }
    else
    {
      // Fixed width with intelligent scaling for high-resolution content
      if (videoWidth > 1920 && width < static_cast<int>(videoWidth / 2))
      {
        // For 4K+ videos, ensure at least 50% of original to preserve detail
        thumbnailWidth = static_cast<int>(videoWidth / 2);
        thumbnailHeight = static_cast<int>(videoHeight / 2);
      }
      else if (videoWidth > 1280 && width < static_cast<int>(videoWidth / 3))
      {
        // For HD videos, ensure at least 33% of original
        thumbnailWidth = static_cast<int>(videoWidth / 3);
        thumbnailHeight = static_cast<int>(videoHeight / 3);
      }
      else
      {
        // Standard scaling - maintain aspect ratio
        thumbnailWidth = width;
        thumbnailHeight = (int)(((float)videoHeight / videoWidth) * width);
      }
    }

    // Safety checks
    if (thumbnailWidth <= 0)
      thumbnailWidth = static_cast<int>(videoWidth);
    if (thumbnailHeight <= 0)
      thumbnailHeight = static_cast<int>(videoHeight);

    Gdiplus::Bitmap *pResizedBitmap = new Gdiplus::Bitmap(thumbnailWidth, thumbnailHeight, PixelFormat32bppRGB);
    Gdiplus::Graphics *pGraphics = Gdiplus::Graphics::FromImage(pResizedBitmap);

    // Set high quality rendering settings for better thumbnails
    pGraphics->SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
    pGraphics->SetCompositingQuality(Gdiplus::CompositingQualityHighQuality);
    pGraphics->SetSmoothingMode(Gdiplus::SmoothingModeHighQuality);
    pGraphics->SetPixelOffsetMode(Gdiplus::PixelOffsetModeHighQuality);

    // Draw with enhanced color settings
    Gdiplus::Rect destRect(0, 0, thumbnailWidth, thumbnailHeight);
    pGraphics->DrawImage(pGdiPlusBitmap, destRect, 0, 0, videoWidth, videoHeight,
                         Gdiplus::UnitPixel, &imgAttributes);

    // Configure encoder parameters for better quality
    Gdiplus::EncoderParameters encoderParams;
    ULONG qualityValue;

    encoderParams.Count = 1;
    encoderParams.Parameter[0].Guid = Gdiplus::EncoderQuality;
    encoderParams.Parameter[0].Type = Gdiplus::EncoderParameterValueTypeLong;
    encoderParams.Parameter[0].NumberOfValues = 1;
    encoderParams.Parameter[0].Value = &qualityValue;

    // Use provided quality value for JPEG (PNG is lossless so doesn't need quality setting)
    qualityValue = format == Gdiplus::ImageFormatJPEG ? quality : 100;

    CLSID clsid;
    if (format == Gdiplus::ImageFormatPNG)
    {
      GetEncoderClsid(L"image/png", &clsid);
    }
    else
    {
      GetEncoderClsid(L"image/jpeg", &clsid);
    }

    Gdiplus::Status status = pResizedBitmap->Save(destFile, &clsid, &encoderParams);

    delete pGraphics;
    delete pResizedBitmap;
    delete pGdiPlusBitmap;

    pBuffer->Unlock();
    pBuffer->Release();
    pSample->Release();
    pReader->Release();
    Gdiplus::GdiplusShutdown(gdiplusToken);
    MFShutdown();

    if (status != Gdiplus::Ok)
    {
      return "Failed to save thumbnail";
    }

    return "";
  }

  std::string ExtractShellThumbnail(PCWSTR srcFile, PCWSTR destFile, int size, REFGUID type)
  {
    IShellItem *pSI;
    HRESULT hr = SHCreateItemFromParsingName(srcFile, NULL, IID_IShellItem, (void **)&pSI);
    if (!SUCCEEDED(hr))
    {
      return "`SHCreateItemFromParsingName` failed with " + HRESULTToString(hr);
    }

    IThumbnailCache *pThumbCache;
    hr = CoCreateInstance(CLSID_LocalThumbnailCache,
                          NULL,
                          CLSCTX_INPROC_SERVER,
                          IID_PPV_ARGS(&pThumbCache));

    if (!SUCCEEDED(hr))
    {
      pSI->Release();
      return "`CoCreateInstance` failed with " + HRESULTToString(hr);
    }
    ISharedBitmap *pSharedBitmap = NULL;
    hr = pThumbCache->GetThumbnail(pSI,
                                   size,
                                   WTS_EXTRACT | WTS_SCALETOREQUESTEDSIZE,
                                   &pSharedBitmap,
                                   NULL,
                                   NULL);

    if (!SUCCEEDED(hr) || !pSharedBitmap)
    {
      pSI->Release();
      pThumbCache->Release();
      if (hr == WTS_E_FAILEDEXTRACTION)
      {
        return kGetThumbnailFailedExtraction;
      }
      return "`GetThumbnail` failed with " + HRESULTToString(hr);
    }
    HBITMAP hBitmap;
    hr = pSharedBitmap->GetSharedBitmap(&hBitmap);
    if (!SUCCEEDED(hr) || !hBitmap)
    {
      pSI->Release();
      pSharedBitmap->Release();
      pThumbCache->Release();
      return "`GetSharedBitmap` failed with " + HRESULTToString(hr);
    }

    pSI->Release();
    pSharedBitmap->Release();
    pThumbCache->Release();

    IWICImagingFactory *pFactory = nullptr;
    hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&pFactory));
    if (!SUCCEEDED(hr) || !pFactory)
    {
      DeleteObject(hBitmap);
      return "`CoCreateInstance` for WIC factory failed with " + HRESULTToString(hr);
    }

    IWICBitmap *pWicBitmap = nullptr;
    hr = pFactory->CreateBitmapFromHBITMAP(hBitmap, nullptr, WICBitmapUseAlpha, &pWicBitmap);
    if (!SUCCEEDED(hr) || !pWicBitmap)
    {
      pFactory->Release();
      DeleteObject(hBitmap);
      return "Failed to create WIC bitmap from HBITMAP";
    }

    IWICStream *pStream = nullptr;
    hr = pFactory->CreateStream(&pStream);
    if (!SUCCEEDED(hr) || !pStream)
    {
      pWicBitmap->Release();
      pFactory->Release();
      DeleteObject(hBitmap);
      return "Failed to create WIC stream";
    }

    hr = pStream->InitializeFromFilename(destFile, GENERIC_WRITE);
    if (!SUCCEEDED(hr))
    {
      pStream->Release();
      pWicBitmap->Release();
      pFactory->Release();
      DeleteObject(hBitmap);
      return "Failed to initialize WIC stream";
    }

    GUID containerFormat = (type == Gdiplus::ImageFormatPNG) ? GUID_ContainerFormatPng : GUID_ContainerFormatJpeg;
    IWICBitmapEncoder *pEncoder = nullptr;
    hr = pFactory->CreateEncoder(containerFormat, nullptr, &pEncoder);
    if (!SUCCEEDED(hr) || !pEncoder)
    {
      pStream->Release();
      pWicBitmap->Release();
      pFactory->Release();
      DeleteObject(hBitmap);
      return "Failed to create WIC encoder";
    }

    hr = pEncoder->Initialize(pStream, WICBitmapEncoderNoCache);
    if (!SUCCEEDED(hr))
    {
      pEncoder->Release();
      pStream->Release();
      pWicBitmap->Release();
      pFactory->Release();
      DeleteObject(hBitmap);
      return "Failed to initialize WIC encoder";
    }

    IWICBitmapFrameEncode *pFrame = nullptr;
    IPropertyBag2 *pProps = nullptr;
    hr = pEncoder->CreateNewFrame(&pFrame, &pProps);
    if (!SUCCEEDED(hr) || !pFrame)
    {
      if (pProps)
        pProps->Release();
      pEncoder->Release();
      pStream->Release();
      pWicBitmap->Release();
      pFactory->Release();
      DeleteObject(hBitmap);
      return "Failed to create WIC frame";
    }

    if (containerFormat == GUID_ContainerFormatJpeg && pProps)
    {
      PROPBAG2 option = {};
      option.pstrName = const_cast<LPOLESTR>(L"ImageQuality");
      VARIANT varValue;
      VariantInit(&varValue);
      varValue.vt = VT_R4;
      varValue.fltVal = 0.9f;
      pProps->Write(1, &option, &varValue);
      VariantClear(&varValue);
    }

    hr = pFrame->Initialize(pProps);
    if (pProps)
    {
      pProps->Release();
    }
    if (!SUCCEEDED(hr))
    {
      pFrame->Release();
      pEncoder->Release();
      pStream->Release();
      pWicBitmap->Release();
      pFactory->Release();
      DeleteObject(hBitmap);
      return "Failed to initialize WIC frame";
    }

    UINT width = 0;
    UINT height = 0;
    pWicBitmap->GetSize(&width, &height);
    pFrame->SetSize(width, height);

    GUID pixelFormat = GUID_WICPixelFormat32bppBGRA;
    pFrame->SetPixelFormat(&pixelFormat);

    hr = pFrame->WriteSource(pWicBitmap, nullptr);
    if (!SUCCEEDED(hr))
    {
      pFrame->Release();
      pEncoder->Release();
      pStream->Release();
      pWicBitmap->Release();
      pFactory->Release();
      DeleteObject(hBitmap);
      return "Failed to write WIC frame";
    }

    pFrame->Commit();
    pEncoder->Commit();

    pFrame->Release();
    pEncoder->Release();
    pStream->Release();
    pWicBitmap->Release();
    pFactory->Release();
    DeleteObject(hBitmap);
    return "";
  }

  std::string SaveThumbnail(PCWSTR srcFile, PCWSTR destFile, int size, REFGUID type, int *timeSeconds, int quality, bool useShellThumbnail)
  {
    if (timeSeconds != nullptr)
    {
      std::string mfResult = ExtractVideoFrameAtTime(srcFile, destFile, size, type, *timeSeconds, quality);
      if (mfResult.empty())
      {
        return "";
      }

      if (useShellThumbnail)
      {
        std::string shellResult = ExtractShellThumbnail(srcFile, destFile, size, type);
        if (shellResult.empty())
        {
          return "";
        }
        if (shellResult == kGetThumbnailFailedExtraction)
        {
          return shellResult;
        }
        return "MediaFoundation failed with " + mfResult + "; shell thumbnail failed with " + shellResult;
      }
      return "MediaFoundation failed with " + mfResult;
    }

    // If no timeSeconds, use original Windows thumbnail cache method
    if (!useShellThumbnail)
    {
      return "Shell thumbnail disabled";
    }
    return ExtractShellThumbnail(srcFile, destFile, size, type);
  }

  void FcNativeVideoThumbnailPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "fc_native_video_thumbnail",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<FcNativeVideoThumbnailPlugin>();

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  FcNativeVideoThumbnailPlugin::FcNativeVideoThumbnailPlugin() : shutdown_(false)
  {
    // Initialize shared GDI+ resources
    {
      std::lock_guard<std::mutex> lock(gdiMutex_);
      instanceCount_++;
      if (!gdiInitialized_)
      {
        Gdiplus::GdiplusStartupInput gdiplusStartupInput;
        if (Gdiplus::GdiplusStartup(&gdiplusToken_, &gdiplusStartupInput, nullptr) == Gdiplus::Ok)
        {
          gdiInitialized_ = true;
        }
      }
    }

    // Initialize FFmpeg thumbnail helper GDI+ singleton (for fast SaveImageFast)
    FFmpegThumbnailHelper::InitializeGdiPlus();

    // Initialize MediaFoundation
    MFStartup(MF_VERSION);

    // Create worker threads (use hardware concurrency, but limit to reasonable number)
    const size_t numThreads = std::min(std::thread::hardware_concurrency(), 4u);
    workers_.reserve(numThreads);

    for (size_t i = 0; i < numThreads; ++i)
    {
      workers_.emplace_back(&FcNativeVideoThumbnailPlugin::WorkerThread, this);
    }
  }

  FcNativeVideoThumbnailPlugin::~FcNativeVideoThumbnailPlugin()
  {
    // Signal shutdown
    shutdown_ = true;

    // Clear all pending requests to prevent processing during shutdown
    {
      std::lock_guard<std::mutex> lock(queueMutex_);
      requestQueue_.clear();
    }

    // Clear active requests
    {
      std::lock_guard<std::mutex> lock(activeRequestsMutex_);
      activeRequests_.clear();
    }

    queueCondition_.notify_all();

    // Wait for all worker threads to finish
    for (auto &worker : workers_)
    {
      if (worker.joinable())
      {
        worker.join();
      }
    }

    // Cleanup MediaFoundation
    MFShutdown();

    // Shutdown FFmpeg thumbnail helper GDI+ singleton
    FFmpegThumbnailHelper::ShutdownGdiPlus();

    // Cleanup shared GDI+ resources
    {
      std::lock_guard<std::mutex> lock(gdiMutex_);
      instanceCount_--;
      if (instanceCount_ == 0 && gdiInitialized_)
      {
        Gdiplus::GdiplusShutdown(gdiplusToken_);
        gdiInitialized_ = false;
      }
    }
  }

  void FcNativeVideoThumbnailPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    const auto *argsPtr = std::get_if<flutter::EncodableMap>(method_call.arguments());
    assert(argsPtr);
    auto args = *argsPtr;

    if (method_call.method_name().compare("getVideoThumbnail") == 0)
    {
      const auto *src_file = std::get_if<std::string>(ValueOrNull(args, "srcFile"));
      assert(src_file);

      const auto *dest_file = std::get_if<std::string>(ValueOrNull(args, "destFile"));
      assert(dest_file);

      const auto *width = std::get_if<int>(ValueOrNull(args, "width"));
      assert(width);

      const auto *outType = std::get_if<std::string>(ValueOrNull(args, "format"));
      assert(outType);

      // Check cache first - this prevents unnecessary re-rendering
      if (IsThumbnailCached(*src_file, *dest_file))
      {
        result->Success(flutter::EncodableValue(true));
        return;
      }

      // Check if thumbnail file already exists (even if not in cache)
      if (std::filesystem::exists(PathFromUtf8(*dest_file)))
      {
        // File exists, update cache and return success to avoid re-rendering
        UpdateCache(*src_file, *dest_file);
        result->Success(flutter::EncodableValue(true));
        return;
      }

      // Create async request
      auto request = std::make_unique<ThumbnailRequest>();
      request->srcFile = *src_file;
      request->destFile = *dest_file;
      request->width = *width;
      request->format = *outType;
      request->result = std::move(result);

      // Handle timeSeconds parameter
      const auto *time_seconds_val = ValueOrNull(args, "timeSeconds");
      if (time_seconds_val != nullptr && std::holds_alternative<int>(*time_seconds_val))
      {
        request->timeSeconds = std::get<int>(*time_seconds_val);
      }
      else
      {
        request->timeSeconds = -1; // Use default
      }

      // Handle quality parameter
      const auto *quality_val = ValueOrNull(args, "quality");
      if (quality_val != nullptr && std::holds_alternative<int>(*quality_val))
      {
        request->quality = std::get<int>(*quality_val);
        // Clamp quality to valid range
        if (request->quality < 1)
          request->quality = 1;
        if (request->quality > 100)
          request->quality = 100;
      }
      else
      {
        request->quality = 95; // Default quality
      }

      // Handle priority parameter
      const auto *priority_val = ValueOrNull(args, "priority");
      if (priority_val != nullptr && std::holds_alternative<int>(*priority_val))
      {
        int priorityInt = std::get<int>(*priority_val);
        request->priority = static_cast<ThumbnailPriority>(std::clamp(priorityInt, 0, 3));
      }
      else
      {
        // Determine priority based on visibility
        request->priority = DeterminePriority(*src_file);
      }

      // Generate unique request ID for tracking
      request->requestId = GenerateCacheKey(*src_file, *width, *outType);

      // Check if request is already being processed
      {
        std::lock_guard<std::mutex> lock(activeRequestsMutex_);
        if (activeRequests_.find(request->requestId) != activeRequests_.end())
        {
          // Request already in progress, return immediately
          result->Success(flutter::EncodableValue(false));
          return;
        }
        activeRequests_.insert(request->requestId);
      }

      // Queue the request for async processing
      {
        std::lock_guard<std::mutex> lock(queueMutex_);

        // If queue is getting too large, remove low priority requests to prevent lag
        if (requestQueue_.size() >= QUEUE_CLEANUP_THRESHOLD)
        {
          auto removeIt = std::remove_if(requestQueue_.begin(), requestQueue_.end(),
                                         [](const std::unique_ptr<ThumbnailRequest> &req)
                                         {
                                           return req->priority == ThumbnailPriority::NORMAL;
                                         });

          // Cleanup active requests for removed items
          for (auto it = removeIt; it != requestQueue_.end(); ++it)
          {
            std::lock_guard<std::mutex> activeLock(activeRequestsMutex_);
            activeRequests_.erase((*it)->requestId);
          }

          requestQueue_.erase(removeIt, requestQueue_.end());
        }

        // Don't add if queue is at max capacity and this is low priority
        if (requestQueue_.size() >= MAX_QUEUE_SIZE && request->priority == ThumbnailPriority::NORMAL)
        {
          std::lock_guard<std::mutex> activeLock(activeRequestsMutex_);
          activeRequests_.erase(request->requestId);
          result->Success(flutter::EncodableValue(false));
          return;
        }

        requestQueue_.push_back(std::move(request));

        // Insert request in correct position to maintain sorted order (more efficient than full sort)
        if (requestQueue_.size() > 1)
        {
          auto insertPos = std::upper_bound(requestQueue_.begin(), requestQueue_.end() - 1, requestQueue_.back(),
                                            [](const std::unique_ptr<ThumbnailRequest> &a, const std::unique_ptr<ThumbnailRequest> &b)
                                            {
                                              // Higher priority first
                                              if (a->priority != b->priority)
                                              {
                                                return static_cast<int>(a->priority) > static_cast<int>(b->priority);
                                              }
                                              // If same priority, older requests first (FIFO within same priority)
                                              return a->requestTime < b->requestTime;
                                            });

          // Move the last element to correct position
          if (insertPos != requestQueue_.end() - 1)
          {
            std::rotate(insertPos, requestQueue_.end() - 1, requestQueue_.end());
          }
        }
      }
      queueCondition_.notify_one();
    }
    else if (method_call.method_name().compare("setVisibleThumbnails") == 0)
    {
      const auto *visible_files = std::get_if<std::vector<flutter::EncodableValue>>(ValueOrNull(args, "visibleFiles"));
      if (visible_files)
      {
        std::vector<std::string> files;
        for (const auto &file : *visible_files)
        {
          if (const auto *str = std::get_if<std::string>(&file))
          {
            files.push_back(*str);
          }
        }
        SetVisibleThumbnails(files);
      }
      result->Success(flutter::EncodableValue(true));
    }
    else if (method_call.method_name().compare("setFocusedThumbnail") == 0)
    {
      const auto *focused_file = std::get_if<std::string>(ValueOrNull(args, "focusedFile"));
      if (focused_file)
      {
        SetFocusedThumbnail(*focused_file);
      }
      result->Success(flutter::EncodableValue(true));
    }
    else if (method_call.method_name().compare("getVideoDuration") == 0)
    {
      const auto *src_file = std::get_if<std::string>(ValueOrNull(args, "srcFile"));
      if (src_file && !src_file->empty())
      {
        // Run FFmpeg operation on background thread to avoid blocking UI
        std::string filePath = *src_file;
        auto result_ptr = std::move(result);

        std::thread([filePath, result_ptr = std::move(result_ptr)]() mutable
                    {
          std::wstring widePath = Utf16FromUtf8(filePath);
          double duration = FFmpegThumbnailHelper::GetVideoDuration(widePath.c_str());
          
          // Post result back to main thread
          result_ptr->Success(flutter::EncodableValue(duration)); })
            .detach();
      }
      else
      {
        result->Success(flutter::EncodableValue(-1.0));
      }
    }
    else if (method_call.method_name().compare("generateThumbnailAtPercentage") == 0)
    {
      // Fast combined method: gets duration and extracts thumbnail in one file open
      const auto *src_file = std::get_if<std::string>(ValueOrNull(args, "srcFile"));
      const auto *dest_file = std::get_if<std::string>(ValueOrNull(args, "destFile"));
      const auto *format_val = std::get_if<std::string>(ValueOrNull(args, "format"));

      // Handle width - could be int32_t or int64_t from Dart
      int width = 0;
      if (auto *width_i32 = std::get_if<int32_t>(ValueOrNull(args, "width")))
      {
        width = *width_i32;
      }
      else if (auto *width_i64 = std::get_if<int64_t>(ValueOrNull(args, "width")))
      {
        width = static_cast<int>(*width_i64);
      }

      // Handle quality - could be int32_t or int64_t from Dart
      int quality = 95;
      if (auto *quality_i32 = std::get_if<int32_t>(ValueOrNull(args, "quality")))
      {
        quality = *quality_i32;
      }
      else if (auto *quality_i64 = std::get_if<int64_t>(ValueOrNull(args, "quality")))
      {
        quality = static_cast<int>(*quality_i64);
      }

      // Handle percentage - could be double or int from Dart (e.g., 30.0 might come as 30)
      double percentage = 30.0;
      if (auto *pct_dbl = std::get_if<double>(ValueOrNull(args, "percentage")))
      {
        percentage = *pct_dbl;
      }
      else if (auto *pct_i32 = std::get_if<int32_t>(ValueOrNull(args, "percentage")))
      {
        percentage = static_cast<double>(*pct_i32);
      }
      else if (auto *pct_i64 = std::get_if<int64_t>(ValueOrNull(args, "percentage")))
      {
        percentage = static_cast<double>(*pct_i64);
      }

      if (src_file && dest_file && !src_file->empty() && !dest_file->empty())
      {
        std::string srcPath = *src_file;
        std::string destPath = *dest_file;
        std::string format = format_val ? *format_val : "jpg";

        auto result_ptr = std::move(result);

        // Run on background thread for non-blocking operation
        std::thread([srcPath, destPath, width, format, percentage, quality,
                     result_ptr = std::move(result_ptr)]() mutable
                    {
          std::wstring wideSrc = Utf16FromUtf8(srcPath);
          std::wstring wideDest = Utf16FromUtf8(destPath);

          GUID formatGuid = (format == "png") ? Gdiplus::ImageFormatPNG : Gdiplus::ImageFormatJPEG;

          std::string error = FFmpegThumbnailHelper::ExtractThumbnailAtPercentage(
              wideSrc.c_str(),
              wideDest.c_str(),
              width,
              formatGuid,
              percentage,
              quality);

          if (error.empty())
          {
            result_ptr->Success(flutter::EncodableValue(destPath));
          }
          else
          {
            result_ptr->Success(flutter::EncodableValue());  // null on error
          } })
            .detach();
      }
      else
      {
        result->Success(flutter::EncodableValue()); // null on invalid args
      }
    }
    else
    {
      result->NotImplemented();
    }
  }

  // Worker thread function
  void FcNativeVideoThumbnailPlugin::WorkerThread()
  {
    const HRESULT coInit = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool coInitialized = (coInit == S_OK || coInit == S_FALSE);

    while (!shutdown_)
    {
      std::unique_ptr<ThumbnailRequest> request;

      // Wait for work
      {
        std::unique_lock<std::mutex> lock(queueMutex_);
        queueCondition_.wait(lock, [this]
                             { return !requestQueue_.empty() || shutdown_; });

        if (shutdown_)
          break;

        if (!requestQueue_.empty())
        {
          // Get highest priority request (first element after sorting)
          request = std::move(requestQueue_.front());
          requestQueue_.erase(requestQueue_.begin());
        }
      }

      // Validate request before processing
      if (request && !request->srcFile.empty() && !request->destFile.empty())
      {
        // Check if source file still exists
        const auto normalizedSrc = NormalizeWindowsPathFromUtf8(request->srcFile);
        if (normalizedSrc.empty())
        {
          {
            std::lock_guard<std::mutex> lock(activeRequestsMutex_);
            activeRequests_.erase(request->requestId);
          }
          if (request->result)
          {
            request->result->Error("InvalidRequest", "Invalid source path");
          }
          continue;
        }

        if (!FileExistsWide(normalizedSrc))
        {
          // Cleanup and skip invalid request
          {
            std::lock_guard<std::mutex> lock(activeRequestsMutex_);
            activeRequests_.erase(request->requestId);
          }
          if (request->result)
          {
            request->result->Error("FileNotFound", "Source file does not exist");
          }
          continue;
        }

        ProcessThumbnailAsync(std::move(request));
      }
      else if (request)
      {
        // Cleanup invalid request
        {
          std::lock_guard<std::mutex> lock(activeRequestsMutex_);
          activeRequests_.erase(request->requestId);
        }
        if (request->result)
        {
          request->result->Error("InvalidRequest", "Invalid request parameters");
        }
      }
    }

    if (coInitialized)
    {
      CoUninitialize();
    }
  }

  // Process thumbnail request asynchronously
  void FcNativeVideoThumbnailPlugin::ProcessThumbnailAsync(std::unique_ptr<ThumbnailRequest> request)
  {
    // Ensure cleanup of active requests on exit
    auto cleanup = [this, &request]()
    {
      std::lock_guard<std::mutex> lock(activeRequestsMutex_);
      activeRequests_.erase(request->requestId);
    };

    try
    {
      int *timeSeconds = nullptr;
      int timeSecondsValue = request->timeSeconds;
      if (timeSecondsValue >= 0)
      {
        timeSeconds = &timeSecondsValue;
      }

      const auto normalizedSrc = NormalizeWindowsPathFromUtf8(request->srcFile);
      const auto normalizedDest = NormalizeWindowsPathFromUtf8(request->destFile);
      if (normalizedSrc.empty() || normalizedDest.empty())
      {
        request->result->Error("PluginError", "Invalid path encoding");
        cleanup();
        return;
      }

      auto oper_res = SaveThumbnail(
          normalizedSrc.c_str(),
          normalizedDest.c_str(),
          request->width,
          request->format.compare("png") == 0 ? Gdiplus::ImageFormatPNG : Gdiplus::ImageFormatJPEG,
          timeSeconds,
          request->quality,
          timeSeconds == nullptr);

      if (oper_res == kGetThumbnailFailedExtraction)
      {
        request->result->Success(flutter::EncodableValue(false));
      }
      else if (oper_res != "")
      {
        request->result->Error("PluginError", "Operation failed. " + oper_res);
      }
      else
      {
        // Update cache on success
        UpdateCache(request->srcFile, request->destFile);
        request->result->Success(flutter::EncodableValue(true));
      }
    }
    catch (const std::exception &e)
    {
      request->result->Error("PluginError", std::string("Exception: ") + e.what());
    }
    catch (...)
    {
      request->result->Error("PluginError", "Unknown exception occurred");
    }

    // Always cleanup active requests
    cleanup();
  }

  // Check if thumbnail is cached and valid
  bool FcNativeVideoThumbnailPlugin::IsThumbnailCached(const std::string &srcFile, const std::string &destFile)
  {
    std::lock_guard<std::mutex> lock(cacheMutex_);

    // Check if thumbnail file exists
    if (!std::filesystem::exists(PathFromUtf8(destFile)))
    {
      return false;
    }

    // Check cache entry using proper cache key that includes file path
    auto cacheKey = destFile; // Use destination file path as cache key for better uniqueness
    auto it = thumbnailCache_.find(cacheKey);

    if (it == thumbnailCache_.end())
    {
      return false;
    }

    // Check if source file has been modified
    try
    {
      auto fileTime = std::filesystem::last_write_time(PathFromUtf8(srcFile));
      auto fileSize = std::filesystem::file_size(PathFromUtf8(srcFile));

      // Convert file_time_type to system_clock::time_point for comparison
      auto sctp = std::chrono::time_point_cast<std::chrono::system_clock::duration>(
          fileTime - std::filesystem::file_time_type::clock::now() + std::chrono::system_clock::now());

      if (it->second.lastModified != std::chrono::duration_cast<std::chrono::seconds>(sctp.time_since_epoch()).count() ||
          it->second.fileSize != static_cast<int64_t>(fileSize))
      {
        // File has been modified, remove from cache
        thumbnailCache_.erase(it);
        return false;
      }

      return true;
    }
    catch (const std::filesystem::filesystem_error &)
    {
      return false;
    }
  }

  // Update cache with new thumbnail info
  void FcNativeVideoThumbnailPlugin::UpdateCache(const std::string &srcFile, const std::string &destFile)
  {
    std::lock_guard<std::mutex> lock(cacheMutex_);

    try
    {
      auto fileTime = std::filesystem::last_write_time(PathFromUtf8(srcFile));
      auto fileSize = std::filesystem::file_size(PathFromUtf8(srcFile));

      // Convert file_time_type to system_clock::time_point
      auto sctp = std::chrono::time_point_cast<std::chrono::system_clock::duration>(
          fileTime - std::filesystem::file_time_type::clock::now() + std::chrono::system_clock::now());

      CacheEntry entry;
      entry.thumbnailPath = destFile;
      entry.lastModified = std::chrono::duration_cast<std::chrono::seconds>(sctp.time_since_epoch()).count();
      entry.fileSize = static_cast<int64_t>(fileSize);
      entry.cacheTime = std::chrono::system_clock::now();

      auto cacheKey = destFile; // Use destination file path as cache key for consistency
      thumbnailCache_[cacheKey] = entry;

      // Clean up old cache entries (keep only last 1000 entries)
      if (thumbnailCache_.size() > 1000)
      {
        auto oldest = thumbnailCache_.begin();
        for (auto it = thumbnailCache_.begin(); it != thumbnailCache_.end(); ++it)
        {
          if (it->second.cacheTime < oldest->second.cacheTime)
          {
            oldest = it;
          }
        }
        thumbnailCache_.erase(oldest);
      }
    }
    catch (const std::filesystem::filesystem_error &)
    {
      // Ignore filesystem errors for cache updates
    }
  }

  // Generate cache key for thumbnail
  std::string FcNativeVideoThumbnailPlugin::GenerateCacheKey(const std::string &srcFile, int width, const std::string &format)
  {
    std::hash<std::string> hasher;
    std::string combined = srcFile + "_" + std::to_string(width) + "_" + format;
    return std::to_string(hasher(combined));
  }

  // Update priority of a specific request
  void FcNativeVideoThumbnailPlugin::UpdateRequestPriority(const std::string &requestId, ThumbnailPriority priority)
  {
    std::lock_guard<std::mutex> lock(priorityMutex_);
    requestPriorities_[requestId] = priority;
  }

  // Set visible thumbnails for priority management
  void FcNativeVideoThumbnailPlugin::SetVisibleThumbnails(const std::vector<std::string> &visibleFiles)
  {
    auto now = std::chrono::steady_clock::now();

    // Fast scroll detection
    {
      std::lock_guard<std::mutex> lock(visibilityMutex_);

      // Reset scroll count if window expired
      if (now - lastScrollTime_ > FAST_SCROLL_WINDOW_MS)
      {
        scrollEventCount_ = 0;
      }

      scrollEventCount_++;
      lastScrollTime_ = now;

      // If scrolling too fast, only process urgent/high priority requests
      if (scrollEventCount_ > FAST_SCROLL_THRESHOLD)
      {
        // During fast scroll, skip normal priority updates
        return;
      }
    }

    // Debounce visibility updates to prevent excessive re-rendering during fast scrolling
    {
      std::lock_guard<std::mutex> lock(visibilityMutex_);
      if (now - lastVisibilityUpdate_ < VISIBILITY_DEBOUNCE_MS)
      {
        return; // Skip update if too frequent
      }
      lastVisibilityUpdate_ = now;
    }

    std::lock_guard<std::mutex> lock(visibilityMutex_);

    // Only update if the visible files actually changed
    std::unordered_set<std::string> newVisibleFiles;
    for (const auto &file : visibleFiles)
    {
      newVisibleFiles.insert(file);
    }

    // Check if there's any difference
    if (newVisibleFiles.size() == visibleFiles_.size())
    {
      bool same = true;
      for (const auto &file : newVisibleFiles)
      {
        if (visibleFiles_.find(file) == visibleFiles_.end())
        {
          same = false;
          break;
        }
      }
      if (same)
        return; // No change, skip update
    }

    visibleFiles_ = std::move(newVisibleFiles);
  }

  // Set focused thumbnail for highest priority
  void FcNativeVideoThumbnailPlugin::SetFocusedThumbnail(const std::string &focusedFile)
  {
    std::lock_guard<std::mutex> lock(visibilityMutex_);
    focusedFile_ = focusedFile;
  }

  // Determine priority based on visibility and focus
  ThumbnailPriority FcNativeVideoThumbnailPlugin::DeterminePriority(const std::string &srcFile)
  {
    std::lock_guard<std::mutex> lock(visibilityMutex_);

    // Highest priority for focused file
    if (!focusedFile_.empty() && srcFile == focusedFile_)
    {
      return ThumbnailPriority::URGENT;
    }

    // High priority for visible files
    if (visibleFiles_.find(srcFile) != visibleFiles_.end())
    {
      return ThumbnailPriority::HIGH;
    }

    // Normal priority for others
    return ThumbnailPriority::NORMAL;
  }

} // namespace fc_native_video_thumbnail
