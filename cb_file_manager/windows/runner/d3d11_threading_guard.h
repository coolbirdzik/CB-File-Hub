#ifndef RUNNER_D3D11_THREADING_GUARD_H_
#define RUNNER_D3D11_THREADING_GUARD_H_

// Makes the Flutter engine's ANGLE create its D3D11 devices with
// D3D11_CREATE_DEVICE_PREVENT_INTERNAL_THREADING_OPTIMIZATIONS.
//
// The NVIDIA D3D11 driver runs submitted work on internal worker threads.
// Under the raster and IO threads' ANGLE traffic (thumbnail uploads while a
// grid of videos scrolls) those workers crashed in nvwgf2umx with both Skia
// and Impeller. ANGLE loads d3d11.dll at runtime, so the flag is added by
// intercepting flutter_windows.dll's GetProcAddress("D3D11CreateDevice").
//
// Call once, before the first engine starts. CB_D3D11_DRIVER_THREADS=1 keeps
// the driver's default behavior for A/B comparisons.
void InstallD3D11ThreadingGuard();

#endif  // RUNNER_D3D11_THREADING_GUARD_H_
