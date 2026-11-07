# Subtitle helper dependencies

The helper uses whisper.cpp 1.9.5 (MIT), ggml (MIT), nlohmann/json 3.12.0
(MIT), and the platform's FFmpeg libraries. Source revisions and archive
SHA-256 digests are pinned in CMakeLists.txt. The whisper.cpp license is
distributed as LICENSE-whisper alongside the helper. FFmpeg redistribution
notices and corresponding-source information follow the app's FFmpeg bundle.

Windows Vulkan builds use Vulkan SDK/runtime 1.4.350.0 from LunarG. The
Vulkan loader is distributed in this helper's isolated directory, together
with its complete LICENSE-VulkanRT.txt. Headers, SPIR-V headers and shader
compiler are build tools only and are not shipped in the application.
Download URLs and SHA-256 digests are pinned in
scripts/fetch_subtitle_vulkan.py in the source repository. Upstream source:
https://github.com/KhronosGroup/Vulkan-Loader and https://vulkan.lunarg.com/.

nlohmann/json Copyright (c) 2013-2025 Niels Lohmann

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
