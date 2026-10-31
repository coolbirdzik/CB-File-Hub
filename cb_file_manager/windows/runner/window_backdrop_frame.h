#ifndef RUNNER_WINDOW_BACKDROP_FRAME_H_
#define RUNNER_WINDOW_BACKDROP_FRAME_H_

#include <windows.h>

namespace WindowBackdrop {
constexpr UINT kResizeFrameReady = WM_APP + 0x48;
constexpr wchar_t kResizeFramePending[] = L"CBFileHub.BackdropResizeFramePending";

inline bool IsResizeFramePending(HWND hwnd) {
  return ::GetPropW(hwnd, kResizeFramePending) != nullptr;
}

// A WM_SIZE timer can fire before Flutter replaces/presents its resized
// surface. Restore composition only after the matching rendered frame.
class ResizeFrameSync {
 public:
  bool OnSize(HWND hwnd, WPARAM type, LPARAM size) {
    if (has_size_ && type_ == type && size_ == size) return false;
    has_size_ = true;
    type_ = type;
    size_ = size;
    ++generation_;
    pending_ = type != SIZE_MINIMIZED && LOWORD(size) > 0 && HIWORD(size) > 0;
    if (pending_) {
      ::SetPropW(hwnd, kResizeFramePending, reinterpret_cast<HANDLE>(1));
    } else {
      ::RemovePropW(hwnd, kResizeFramePending);
    }
    return pending_;
  }

  WPARAM generation() const { return generation_; }

  bool OnFrame(HWND hwnd, WPARAM generation) {
    if (!pending_ || generation != generation_) return false;
    pending_ = false;
    ::RemovePropW(hwnd, kResizeFramePending);
    return true;
  }

 private:
  bool has_size_ = false;
  bool pending_ = false;
  WPARAM type_ = SIZE_RESTORED;
  LPARAM size_ = 0;
  WPARAM generation_ = 0;
};
}  // namespace WindowBackdrop

#endif  // RUNNER_WINDOW_BACKDROP_FRAME_H_
