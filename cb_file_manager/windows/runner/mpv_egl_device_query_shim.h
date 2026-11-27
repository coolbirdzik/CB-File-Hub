#ifndef RUNNER_MPV_EGL_DEVICE_QUERY_SHIM_H_
#define RUNNER_MPV_EGL_DEVICE_QUERY_SHIM_H_

// Lets libmpv's D3D11-EGL interop load on media_kit's ANGLE, so GPU-decoded
// frames stay on the GPU instead of being copied back to system memory.
//
// mpv 0.36's hwdec_d3d11egl requires EGL_EXT_device_query in the *display*
// extension string. That is a client extension; the ANGLE bundled with
// media_kit (and the EGL spec) lists it only for EGL_NO_DISPLAY. The interop
// then fails to load and mpv falls back to d3d11va-copy, which copies every
// decoded frame to RAM and back: an 8192x4096 10-bit frame is ~100 MB, so 8K60
// HEVC played at ~25 fps. With the interop, the same file renders at 60 fps.
//
// libmpv loads libEGL.dll at runtime, so this wraps the eglQueryString it gets
// from GetProcAddress and appends the extension to display queries when ANGLE
// reports it for the client. Nothing else in libmpv's EGL use changes.
//
// Call once, before the first media_kit player is created. libmpv is
// delay-loaded by media_kit_video_plugin.dll, so this loads it first.
// CB_MPV_EGL_SHIM=0 disables it for A/B comparisons.
void InstallMpvEglDeviceQueryShim();

#endif  // RUNNER_MPV_EGL_DEVICE_QUERY_SHIM_H_
