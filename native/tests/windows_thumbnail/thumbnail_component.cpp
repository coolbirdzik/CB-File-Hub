#include "ffmpeg_thumbnail_helper.h"
#include <iostream>
#include <vector>

namespace fc_native_video_thumbnail {
int GetEncoderClsid(const WCHAR* format, CLSID* result) {
  UINT count = 0, size = 0;
  Gdiplus::GetImageEncodersSize(&count, &size);
  std::vector<unsigned char> buffer(size);
  auto* encoders = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
  if (!size || Gdiplus::GetImageEncoders(count, size, encoders) != Gdiplus::Ok) return -1;
  for (UINT i = 0; i < count; ++i) {
    if (wcscmp(encoders[i].MimeType, format) == 0) {
      *result = encoders[i].Clsid;
      return static_cast<int>(i);
    }
  }
  return -1;
}
}

int wmain(int argc, wchar_t** argv) {
  if (argc != 3) return 2;
  using Helper = fc_native_video_thumbnail::FFmpegThumbnailHelper;
  Helper::InitializeGdiPlus();
  int result = 0;
  const double duration = Helper::GetVideoDuration(argv[1]);
  if (duration <= 0) result = 3;
  const std::wstring base = argv[2];
  for (bool percentage : {false, true}) {
    const std::wstring output = base + (percentage ? L"-percentage.png" : L"-time.jpg");
    const std::string error = percentage
        ? Helper::ExtractThumbnailAtPercentage(argv[1], output.c_str(), 64, Gdiplus::ImageFormatPNG, 50)
        : Helper::ExtractThumbnail(argv[1], output.c_str(), 64, Gdiplus::ImageFormatJPEG, 0);
    Gdiplus::Bitmap image(output.c_str());
    if (!error.empty() || image.GetLastStatus() != Gdiplus::Ok || image.GetWidth() != 64 || image.GetHeight() == 0) {
      std::cerr << "Thumbnail failed: " << error << '\n';
      result = 4;
    } else {
      // The synthetic source contains colored blocks, so a blank image is a failure.
      Gdiplus::Color first, pixel;
      image.GetPixel(0, 0, &first);
      bool varied = false;
      for (UINT y = 0; y < image.GetHeight(); y += 4) {
        for (UINT x = 0; x < image.GetWidth(); x += 4) {
          if (image.GetPixel(x, y, &pixel) != Gdiplus::Ok) result = 5;
          if (pixel.GetValue() != first.GetValue()) varied = true;
        }
      }
      if (!varied) result = 6;
    }
  }
  Helper::ShutdownGdiPlus();
  if (!result) std::cout << "Duration and both thumbnail paths passed\n";
  return result;
}
