#ifndef RUNNER_TORRENT_LAUNCH_H_
#define RUNNER_TORRENT_LAUNCH_H_

#include <windows.h>

#include <string>
#include <vector>

// Advertised only after Dart has attached the tab manager and launch handler.
// Engine owner > primary shell > secondary shell; spare/video windows omit it.
inline constexpr wchar_t kTorrentLaunchPriority[] = L"CBFileHub.TorrentLaunch.v1";
inline constexpr ULONG_PTR kTorrentLaunchMessage = 0x43425431;

bool ReadTorrentLaunchMessage(const COPYDATASTRUCT* data,
                             std::vector<std::string>* sources);
// Returns before constructing a Flutter engine when an existing shell accepts.
bool TryForwardTorrentLaunch(const std::vector<std::string>& arguments);

#endif  // RUNNER_TORRENT_LAUNCH_H_
