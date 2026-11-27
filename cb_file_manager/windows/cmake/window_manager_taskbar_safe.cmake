# window_manager 0.5.2 assumes waitUntilReadyToShow has already created the
# taskbar COM interface. A runner-placed player skips that call to preserve its
# geometry, and COM activation itself may fail (e.g. Explorer restarting).
# Patch the embedded implementation without modifying the pub cache.
function(coolbird_patch_window_manager_taskbar)
  if(NOT TARGET window_manager_plugin)
    return()
  endif()
  get_target_property(_plugin_dir window_manager_plugin SOURCE_DIR)
  set(_source "${_plugin_dir}/window_manager.cpp")
  set(_entry "${_plugin_dir}/window_manager_plugin.cpp")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_source}" "${_entry}")
  file(READ "${_source}" _code)
  string(REPLACE "\r\n" "\n" _code "${_code}")
  macro(replace_taskbar_required old new)
    string(FIND "${_code}" "${old}" _match)
    if(_match EQUAL -1)
      message(FATAL_ERROR "window_manager Windows source changed; review the taskbar patch (${old}).")
    endif()
    string(REPLACE "${old}" "${new}" _code "${_code}")
  endmacro()

  replace_taskbar_required(
    "  ITaskbarList3* taskbar_ = nullptr;"
    "  ITaskbarList3* taskbar_ = nullptr;\n  bool EnsureTaskbar();")
  replace_taskbar_required(
    [=[void WindowManager::WaitUntilReadyToShow() {
  ::CoCreateInstance(CLSID_TaskbarList, NULL, CLSCTX_INPROC_SERVER,
                     IID_PPV_ARGS(&taskbar_));
}]=]
    [=[bool WindowManager::EnsureTaskbar() {
  if (taskbar_) return true;
  ITaskbarList3* taskbar = nullptr;
  const HRESULT result = ::CoCreateInstance(CLSID_TaskbarList, nullptr,
      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&taskbar));
  if (FAILED(result) || !taskbar) return false;
  if (FAILED(taskbar->HrInit())) {
    taskbar->Release();
    return false;
  }
  taskbar_ = taskbar;
  return true;
}

void WindowManager::WaitUntilReadyToShow() {
  EnsureTaskbar();
}]=])
  replace_taskbar_required(
    [=[  LPVOID lp = NULL;
  CoInitialize(lp);

  taskbar_->HrInit();]=]
    [=[  if (!EnsureTaskbar()) return;]=])
  replace_taskbar_required(
    [=[void WindowManager::SetProgressBar(const flutter::EncodableMap& args) {
  double progress =]=]
    [=[void WindowManager::SetProgressBar(const flutter::EncodableMap& args) {
  if (!EnsureTaskbar()) return;
  double progress =]=])

  set(_patched "${CMAKE_CURRENT_BINARY_DIR}/window_manager_taskbar_safe.cpp")
  file(WRITE "${_patched}.in" "${_code}")
  configure_file("${_patched}.in" "${_patched}" COPYONLY)

  # The plugin entry includes the implementation directly, in addition to the
  # original standalone source in its CMake target. Replace that include too.
  file(READ "${_entry}" _code)
  replace_taskbar_required("#include \"window_manager.cpp\""
    "#include \"window_manager_taskbar_safe.cpp\"")
  set(_patched_entry "${CMAKE_CURRENT_BINARY_DIR}/window_manager_plugin_taskbar_safe.cpp")
  file(WRITE "${_patched_entry}.in" "${_code}")
  configure_file("${_patched_entry}.in" "${_patched_entry}" COPYONLY)
  get_target_property(_sources window_manager_plugin SOURCES)
  list(FILTER _sources EXCLUDE REGEX "(^|/)window_manager(_plugin)?\\.cpp$")
  set_property(TARGET window_manager_plugin PROPERTY SOURCES ${_sources} "${_patched_entry}")
  target_include_directories(window_manager_plugin PRIVATE "${_plugin_dir}")
endfunction()
