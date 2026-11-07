cmake_minimum_required(VERSION 3.16)
project(cb_subtitles LANGUAGES C CXX)
include(FetchContent)
set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)
if(POLICY CMP0169)
  cmake_policy(SET CMP0169 OLD)
endif()

# Scope these settings to this helper: the app's other plugins keep their own
# linkage and GPU runtimes. No ggml library is loaded into the Flutter process.
set(BUILD_SHARED_LIBS OFF)
set(WHISPER_BUILD_TESTS OFF)
set(WHISPER_BUILD_EXAMPLES OFF)
set(GGML_NATIVE OFF)
set(GGML_OPENMP OFF)
set(GGML_METAL_EMBED_LIBRARY ON)
option(CB_SUBTITLE_VULKAN "Accelerate subtitle inference with Vulkan" ${WIN32})
if(CB_SUBTITLE_VULKAN AND WIN32)
  # Build-only tools live in an ignored workspace cache. The downloader treats
  # the SDK as an archive; it never installs an SDK or modifies the machine.
  set(CB_SUBTITLE_VULKAN_TOOLS "${CMAKE_CURRENT_LIST_DIR}/../../cb_file_manager/build/subtitle-deps/vulkan")
  find_package(Python3 REQUIRED COMPONENTS Interpreter)
  execute_process(COMMAND "${Python3_EXECUTABLE}"
    "${CMAKE_CURRENT_LIST_DIR}/../../scripts/fetch_subtitle_vulkan.py"
    --destination "${CB_SUBTITLE_VULKAN_TOOLS}"
    --cmake "${CMAKE_COMMAND}"
    RESULT_VARIABLE CB_VULKAN_FETCH_RESULT
    OUTPUT_VARIABLE CB_VULKAN_FETCH_OUTPUT ERROR_VARIABLE CB_VULKAN_FETCH_ERROR
    TIMEOUT 600)
  if(NOT CB_VULKAN_FETCH_RESULT EQUAL 0)
    message(FATAL_ERROR "Cannot prepare subtitle Vulkan build tools: ${CB_VULKAN_FETCH_ERROR}\nSet CB_SUBTITLE_VULKAN=OFF for a CPU-only build.")
  endif()
  set(ENV{VULKAN_SDK} "${CB_SUBTITLE_VULKAN_TOOLS}")
  set(Vulkan_INCLUDE_DIR "${CB_SUBTITLE_VULKAN_TOOLS}/Include" CACHE PATH "Vulkan headers" FORCE)
  set(Vulkan_LIBRARY "${CB_SUBTITLE_VULKAN_TOOLS}/Lib/vulkan-1.lib" CACHE FILEPATH "Vulkan loader" FORCE)
  set(Vulkan_GLSLC_EXECUTABLE "${CB_SUBTITLE_VULKAN_TOOLS}/Bin/glslc.exe" CACHE FILEPATH "Vulkan shader compiler" FORCE)
endif()
set(GGML_VULKAN ${CB_SUBTITLE_VULKAN})
FetchContent_Declare(whisper
  URL https://codeload.github.com/ggml-org/whisper.cpp/zip/d1be6fde11ac6e0407606b4e42fe72d34add8037
  URL_HASH SHA256=6be93b881acb415c5a25d0ef85bb6a488099de0296e072e22a66d50f20ec40b9)
FetchContent_GetProperties(whisper)
if(NOT whisper_POPULATED)
  FetchContent_Populate(whisper)
endif()
if(WIN32 AND CB_SUBTITLE_VULKAN)
  # The upstream ExternalProject default exceeds MAX_PATH inside Flutter's
  # nested build directory. Keep only the shader compiler's build path short.
  set(CB_VK_CMAKE "${whisper_SOURCE_DIR}/ggml/src/ggml-vulkan/CMakeLists.txt")
  file(READ "${CB_VK_CMAKE}" CB_VK_SOURCE)
  string(REPLACE "        vulkan-shaders-gen\n        SOURCE_DIR"
    "        vulkan-shaders-gen\n        PREFIX \"\${CMAKE_BINARY_DIR}/vk\"\n        BINARY_DIR \"\${CMAKE_BINARY_DIR}/vk/b\"\n        SOURCE_DIR"
    CB_VK_PATCHED "${CB_VK_SOURCE}")
  if(NOT CB_VK_PATCHED STREQUAL CB_VK_SOURCE)
    file(WRITE "${CB_VK_CMAKE}" "${CB_VK_PATCHED}")
  endif()
endif()
add_subdirectory("${whisper_SOURCE_DIR}" "${whisper_BINARY_DIR}" EXCLUDE_FROM_ALL)
set(CB_JSON_HEADER "${CMAKE_CURRENT_BINARY_DIR}/json.hpp")
file(DOWNLOAD https://raw.githubusercontent.com/nlohmann/json/v3.12.0/single_include/nlohmann/json.hpp
  "${CB_JSON_HEADER}" EXPECTED_HASH SHA256=aaf127c04cb31c406e5b04a63f1ae89369fccde6d8fa7cdda1ed4f32dfc5de63 TLS_VERIFY ON TIMEOUT 120)
add_executable(cb-subtitle-worker worker.cpp)
option(CB_SUBTITLE_TEST_HOOKS "Enable deterministic native component-test hooks" OFF)
if(CB_SUBTITLE_TEST_HOOKS)
  target_compile_definitions(cb-subtitle-worker PRIVATE CB_SUBTITLE_TEST_HOOKS)
endif()
target_compile_features(cb-subtitle-worker PRIVATE cxx_std_17)
target_include_directories(cb-subtitle-worker PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
target_link_libraries(cb-subtitle-worker PRIVATE whisper)
if(WIN32)
  if(NOT CB_SUBTITLE_FFMPEG_DIR)
    set(CB_SUBTITLE_FFMPEG_DIR "${COOLBIRD_FFMPEG_DIR}")
  endif()
  file(TO_CMAKE_PATH "${CB_SUBTITLE_FFMPEG_DIR}" CB_SUBTITLE_FFMPEG_DIR)
  target_include_directories(cb-subtitle-worker PRIVATE "${CB_SUBTITLE_FFMPEG_DIR}/include")
  target_link_directories(cb-subtitle-worker PRIVATE "${CB_SUBTITLE_FFMPEG_DIR}/lib")
  target_link_libraries(cb-subtitle-worker PRIVATE avformat avcodec avutil swresample)
  target_compile_definitions(cb-subtitle-worker PRIVATE NOMINMAX _CRT_SECURE_NO_WARNINGS)
else()
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(SUBTITLE_AV REQUIRED IMPORTED_TARGET libavformat libavcodec libavutil libswresample)
  target_link_libraries(cb-subtitle-worker PRIVATE PkgConfig::SUBTITLE_AV)
endif()
set_target_properties(cb-subtitle-worker PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin")
if(NOT DEFINED CB_SUBTITLE_INSTALL_DIR)
  set(CB_SUBTITLE_INSTALL_DIR subtitles)
endif()
install(TARGETS cb-subtitle-worker RUNTIME DESTINATION "${CB_SUBTITLE_INSTALL_DIR}" COMPONENT Runtime)
install(FILES "${whisper_SOURCE_DIR}/LICENSE" DESTINATION "${CB_SUBTITLE_INSTALL_DIR}" RENAME LICENSE-whisper COMPONENT Runtime)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/THIRD_PARTY_NOTICES.md" DESTINATION "${CB_SUBTITLE_INSTALL_DIR}" COMPONENT Runtime)
if(WIN32)
  if(CB_SUBTITLE_VULKAN)
    # Keep the real loader isolated from Flutter/ANGLE's app-root DLL. The
    # loader is also available on machines where inference falls back to CPU.
    install(FILES "${CB_SUBTITLE_VULKAN_TOOLS}/Bin/vulkan-1.dll"
      "${CB_SUBTITLE_VULKAN_TOOLS}/LICENSE-VulkanRT.txt"
      DESTINATION "${CB_SUBTITLE_INSTALL_DIR}" COMPONENT Runtime)
  endif()
  file(GLOB CB_SUBTITLE_FFMPEG_DLLS
    "${CB_SUBTITLE_FFMPEG_DIR}/bin/avcodec-*.dll"
    "${CB_SUBTITLE_FFMPEG_DIR}/bin/avformat-*.dll"
    "${CB_SUBTITLE_FFMPEG_DIR}/bin/avutil-*.dll"
    "${CB_SUBTITLE_FFMPEG_DIR}/bin/swresample-*.dll")
  install(FILES ${CB_SUBTITLE_FFMPEG_DLLS} DESTINATION "${CB_SUBTITLE_INSTALL_DIR}" COMPONENT Runtime)
endif()
