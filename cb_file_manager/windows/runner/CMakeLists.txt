cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "custom_frame_message.h"
  "flutter_mouse_input_guard.cpp"
  "flutter_mouse_input_guard.h"
  "engine_window_host.cpp"
  "engine_window_host.h"
  "d3d11_threading_guard.cpp"
  "d3d11_threading_guard.h"
  "main.cpp"
  "utils.cpp"
  "torrent_launch.cpp"
  "torrent_launch.h"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "fc_native_video_thumbnail_plugin.cpp"
  "fc_native_video_thumbnail_plugin.h"
  "ffmpeg_thumbnail_helper.cpp"
  "ffmpeg_thumbnail_helper.h"
  "smb_native_thumbnail_plugin.cpp"
  "smb_native_thumbnail_plugin.h"
  "app_icon_plugin.cpp"
  "app_icon_plugin.h"
  "folder_defaults.cpp"
  "folder_defaults.h"
  "app_insights_plugin.cpp"
  "app_insights_plugin.h"
  "shell_context_menu_plugin.cpp"
  "shell_context_menu_plugin.h"
  "file_operations_plugin.cpp"
  "file_operations_plugin.h"
  "window_utils_plugin.cpp"
  "window_utils_plugin.h"
  "window_backdrop.h"
  "window_backdrop_frame.h"
  "window_backdrop_diagnostics.h"
  "startup_visibility.h"
  "store_update_plugin.cpp"
  "store_update_plugin.h"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app flutter_wrapper_plugin)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE smb_native)
target_link_libraries(${BINARY_NAME} PRIVATE "comctl32.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "ole32.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "shell32.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "windowsapp.lib")

# Copy smb_native runtime next to the app executable.
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    $<TARGET_FILE:smb_native>
    $<TARGET_FILE_DIR:${BINARY_NAME}>
  COMMENT "Copying smb_native DLL to output directory"
)

# Add FFmpeg libraries
if(DEFINED COOLBIRD_FFMPEG_DIR AND EXISTS "${COOLBIRD_FFMPEG_DIR}")
  set(FFMPEG_DIR "${COOLBIRD_FFMPEG_DIR}")
elseif(DEFINED FFMPEG_DIR AND EXISTS "${FFMPEG_DIR}")
  set(FFMPEG_DIR "${FFMPEG_DIR}")
else()
  set(FFMPEG_DIR "${CMAKE_SOURCE_DIR}/ffmpeg")
endif()

if(NOT EXISTS "${FFMPEG_DIR}/include/libavcodec/avcodec.h" OR NOT EXISTS "${FFMPEG_DIR}/lib/avcodec.lib")
  message(FATAL_ERROR "FFmpeg files are missing in ${FFMPEG_DIR}. Set FFMPEG_DIR or enable COOLBIRD_FFMPEG_AUTO_DOWNLOAD.")
endif()

target_include_directories(${BINARY_NAME} SYSTEM PRIVATE "${FFMPEG_DIR}/include")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
target_link_directories(${BINARY_NAME} PRIVATE "${FFMPEG_DIR}/lib")
target_link_libraries(${BINARY_NAME} PRIVATE delayimp)

# Disable warnings as errors for ffmpeg_thumbnail_helper.cpp (FFmpeg headers have warnings)
set_source_files_properties(
  "${CMAKE_CURRENT_SOURCE_DIR}/ffmpeg_thumbnail_helper.cpp"
  PROPERTIES COMPILE_FLAGS "/W3"
)

# The bundled FFmpeg ships GNU import libraries. MSVC needs its own import
# library format to delay-load those DLLs until the first video operation.
set(FFMPEG_DLLS)
set(FFMPEG_DELAY_IMPORT_LIBS)
set(_ffmpeg_import_dir "${CMAKE_CURRENT_BINARY_DIR}/ffmpeg-imports")
foreach(_component IN ITEMS avformat avcodec avutil swscale)
  file(GLOB _dlls "${FFMPEG_DIR}/bin/${_component}-*.dll")
  list(APPEND FFMPEG_DLLS ${_dlls})
  list(LENGTH _dlls _num_dlls)
  if(_num_dlls EQUAL 1)
    get_filename_component(_dll_name "${_dlls}" NAME)
    get_filename_component(_dll_stem "${_dlls}" NAME_WE)
    set(_exports "${FFMPEG_DIR}/lib/${_dll_stem}.def")
    if(EXISTS "${_exports}")
      set(_import_lib "${_ffmpeg_import_dir}/${_dll_stem}.lib")
      add_custom_command(
        OUTPUT "${_import_lib}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${_ffmpeg_import_dir}"
        COMMAND "${CMAKE_AR}" /NOLOGO "/DEF:${_exports}"
          "/MACHINE:${CMAKE_CXX_COMPILER_ARCHITECTURE_ID}" "/OUT:${_import_lib}"
        DEPENDS "${_exports}"
        VERBATIM
      )
      list(APPEND FFMPEG_DELAY_IMPORT_LIBS "${_import_lib}")
      target_link_libraries(${BINARY_NAME} PRIVATE "${_import_lib}")
      target_link_options(${BINARY_NAME} PRIVATE "/DELAYLOAD:${_dll_name}")
      continue()
    endif()
  endif()
  # Custom FFmpeg distributions can still supply their existing import libs.
  target_link_libraries(${BINARY_NAME} PRIVATE ${_component})
endforeach()
if(FFMPEG_DELAY_IMPORT_LIBS)
  add_custom_target(ffmpeg_delay_imports DEPENDS ${FFMPEG_DELAY_IMPORT_LIBS})
  add_dependencies(${BINARY_NAME} ffmpeg_delay_imports)
endif()
file(GLOB _resampler "${FFMPEG_DIR}/bin/swresample-*.dll")
list(APPEND FFMPEG_DLLS ${_resampler})

if(NOT FFMPEG_DLLS)
  message(FATAL_ERROR "No FFmpeg runtime DLLs found in ${FFMPEG_DIR}/bin.")
endif()

add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    ${FFMPEG_DLLS}
    $<TARGET_FILE_DIR:${BINARY_NAME}>
  COMMENT "Copying FFmpeg DLLs to output directory"
)

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
