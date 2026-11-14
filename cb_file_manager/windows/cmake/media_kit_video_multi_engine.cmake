# media_kit_video 2.0.1 routes every HWND through its latest plugin instance.
# Our spare/PiP engines then steal VideoOutput.Resize from the browser engine.
# Compile a patched copy, leaving the pub cache and generated files untouched.
function(coolbird_patch_media_kit_video)
  if(NOT TARGET media_kit_video_plugin)
    return()
  endif()
  get_target_property(_plugin_dir media_kit_video_plugin SOURCE_DIR)
  set(_source "${_plugin_dir}/media_kit_video_plugin.cc")
  file(READ "${_source}" _code)
  string(REPLACE "\r\n" "\n" _code "${_code}")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_source}")

  macro(replace_required old new)
    string(FIND "${_code}" "${old}" _match)
    if(_match EQUAL -1)
      message(FATAL_ERROR "media_kit_video Windows host changed; review the multi-engine patch (${old}).")
    endif()
    string(REPLACE "${old}" "${new}" _code "${_code}")
  endmacro()

  replace_required(
    "MediaKitVideoPlugin* MediaKitVideoPlugin::instance_ = nullptr;"
    "namespace {\nconstexpr wchar_t kWindowInstance[] = L\"CBFileHub.MediaKitVideo.Instance\";\n}")
  replace_required("  instance_ = this;\n" "")
  replace_required(
    "::GetAncestor(registrar->GetView()->GetNativeWindow(), GA_ROOT);"
    "::GetAncestor(registrar->GetView()->GetNativeWindow(), GA_ROOT);\n  ::SetPropW(flutter_window_, kWindowInstance, this);")
  replace_required(
    [=[  if (flutter_window_ && original_window_proc_) {
    ::SetWindowLongPtr(flutter_window_, GWLP_WNDPROC,
                       reinterpret_cast<LONG_PTR>(original_window_proc_));
  }
  if (instance_ == this) {
    instance_ = nullptr;
  }]=]
    [=[  if (flutter_window_ &&
      ::GetPropW(flutter_window_, kWindowInstance) == this) {
    ::RemovePropW(flutter_window_, kWindowInstance);
    // The runner may have reclaimed the WNDPROC to preserve its custom frame.
    if (original_window_proc_ &&
        reinterpret_cast<WNDPROC>(::GetWindowLongPtr(flutter_window_, GWLP_WNDPROC)) ==
            WindowProcDelegate) {
      ::SetWindowLongPtr(flutter_window_, GWLP_WNDPROC,
                         reinterpret_cast<LONG_PTR>(original_window_proc_));
    }
  }]=])
  replace_required(
    "  if (message == kMainThreadTaskMessage && instance_) {"
    "  auto* instance = static_cast<MediaKitVideoPlugin*>(\n      ::GetPropW(hwnd, kWindowInstance));\n  if (message == kMainThreadTaskMessage && instance) {")
  replace_required("instance_->" "instance->")
  replace_required("if (instance_ &&" "if (instance &&")

  set(_patched "${CMAKE_CURRENT_BINARY_DIR}/media_kit_video_multi_engine.cc")
  # configure_file avoids touching the output when its contents have not changed.
  file(WRITE "${_patched}.in" "${_code}")
  configure_file("${_patched}.in" "${_patched}" COPYONLY)
  get_target_property(_sources media_kit_video_plugin SOURCES)
  list(FILTER _sources EXCLUDE REGEX "(^|/)media_kit_video_plugin\\.cc$")
  set_property(TARGET media_kit_video_plugin PROPERTY SOURCES ${_sources} "${_patched}")
  target_include_directories(media_kit_video_plugin PRIVATE "${_plugin_dir}")
endfunction()
