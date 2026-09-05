# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(cb_file_manager LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "cb_file_hub")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Set policies to suppress warnings from plugin dependencies
if(POLICY CMP0175)
    cmake_policy(SET CMP0175 OLD)  # Allow legacy add_custom_command behavior
endif()

# Force minimum policy version for legacy plugin CMake projects.
# Needed for dependencies that still declare very old cmake_minimum_required values.
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

if(POLICY CMP0169)
    cmake_policy(SET CMP0169 OLD)  # Allow deprecated FetchContent_Populate
endif()

# Additional policy for modern CMake compatibility
if(POLICY CMP0146)
    cmake_policy(SET CMP0146 OLD)  # Allow legacy file handling
endif()

# Suppress developer warnings globally for this project
set(CMAKE_SUPPRESS_DEVELOPER_WARNINGS TRUE CACHE BOOL "Suppress CMake developer warnings")

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Shared dependency setup for this Windows build.
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/dependencies.cmake")

# Ensure NuGet is available before plugin CMake files are processed.
coolbird_ensure_nuget()

# Resolve FFmpeg directory (local checkout or on-demand download).
coolbird_resolve_ffmpeg_dir(COOLBIRD_FFMPEG_DIR)
set(COOLBIRD_FFMPEG_DIR "${COOLBIRD_FFMPEG_DIR}" CACHE PATH "Resolved FFmpeg directory" FORCE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
  # Silence VS 2026 deprecation of <experimental/coroutine> used by some plugins
  target_compile_definitions(${TARGET} PRIVATE "_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")
add_subdirectory(smb_native)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

set(LLAMA_CPP_BUNDLED_LIBRARIES
  "${CMAKE_CURRENT_SOURCE_DIR}/llama/ggml-base.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/llama/ggml-cpu-x64.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/llama/ggml-vulkan.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/llama/ggml.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/llama/libomp.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/llama/LICENSE-LLVM-OpenMP"
  "${CMAKE_CURRENT_SOURCE_DIR}/llama/llama-common.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/llama/llama.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/llama/llama-server-impl.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/llama/mtmd.dll")
# The llama.cpp runtime is installed into its own "llama" subfolder rather than
# next to the app exe. The app bundle ships Flutter's own vulkan-1.dll (from
# ANGLE/media_kit) whose ABI differs from the system Vulkan loader. Because the
# Windows loader prefers a DLL sitting next to the launched exe, launching
# llama-server.exe from the app root would load Flutter's vulkan-1.dll and
# segfault (0xC0000005) inside ggml-vulkan during device enumeration. Isolating
# the server in a subfolder (which has no vulkan-1.dll) makes the loader fall
# back to the real System32 Vulkan loader, so GPU offload works.
set(INSTALL_BUNDLE_LLAMA_DIR "${INSTALL_BUNDLE_LIB_DIR}/llama")
install(FILES ${LLAMA_CPP_BUNDLED_LIBRARIES}
  DESTINATION "${INSTALL_BUNDLE_LLAMA_DIR}"
  COMPONENT Runtime)

install(PROGRAMS "${CMAKE_CURRENT_SOURCE_DIR}/llama/llama-server.exe"
  DESTINATION "${INSTALL_BUNDLE_LLAMA_DIR}"
  COMPONENT Runtime)

# Copy the native assets provided by the build.dart from all packages.
# This directory may not exist if there are no native assets for the platform.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}/native_assets/windows")
if(EXISTS "${NATIVE_ASSETS_DIR}")
  # Trailing slash copies the contents of the directory.
  install(DIRECTORY "${NATIVE_ASSETS_DIR}/"
     DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
     COMPONENT Runtime)
endif()

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
