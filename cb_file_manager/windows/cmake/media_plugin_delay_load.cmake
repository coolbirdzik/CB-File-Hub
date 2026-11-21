# Register both plugins at startup, but load their native media libraries
# only when a document or video is opened.
if(MSVC AND TARGET pdfx_plugin)
  target_link_libraries(pdfx_plugin PRIVATE delayimp)
  target_link_options(pdfx_plugin PRIVATE "/DELAYLOAD:pdfium.dll")
endif()

if(MSVC AND TARGET media_kit_video_plugin)
  get_target_property(_media_kit_links media_kit_video_plugin LINK_LIBRARIES)
  set(_mpv_gnu_import_lib "${CMAKE_BINARY_DIR}/libmpv/libmpv.dll.a")
  if(_mpv_gnu_import_lib IN_LIST _media_kit_links)
    # The pin ships a MinGW import archive. The delay-load linker needs an
    # MSVC import library. Only the video plugin's native calls use this .lib.
    set(_mpv_exports "${CMAKE_CURRENT_LIST_DIR}/libmpv_video.def")
    set(_mpv_import_lib "${CMAKE_CURRENT_BINARY_DIR}/libmpv_video.lib")
    add_custom_command(
      OUTPUT "${_mpv_import_lib}"
      COMMAND "${CMAKE_AR}" /NOLOGO "/DEF:${_mpv_exports}"
        "/MACHINE:${CMAKE_CXX_COMPILER_ARCHITECTURE_ID}" "/OUT:${_mpv_import_lib}"
      DEPENDS "${_mpv_exports}"
      VERBATIM
    )
    add_custom_target(media_kit_video_delay_import DEPENDS "${_mpv_import_lib}")
    add_dependencies(media_kit_video_plugin media_kit_video_delay_import)
    list(REMOVE_ITEM _media_kit_links "${_mpv_gnu_import_lib}")
    set_property(TARGET media_kit_video_plugin PROPERTY LINK_LIBRARIES "${_media_kit_links}")
    target_link_libraries(media_kit_video_plugin PRIVATE "${_mpv_import_lib}" delayimp)
    target_link_options(media_kit_video_plugin PRIVATE
      "/DELAYLOAD:libmpv-2.dll"
      "/DELAYLOAD:libEGL.dll"
      "/DELAYLOAD:libGLESv2.dll"
    )
  endif()
endif()
