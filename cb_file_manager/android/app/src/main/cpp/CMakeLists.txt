cmake_minimum_required(VERSION 3.22.1)
project(cb_llama_android LANGUAGES C CXX)

# Ninja otherwise launches one compiler per host CPU and can exhaust memory
# while building the server's large translation units on CI/developer machines.
set_property(GLOBAL PROPERTY JOB_POOLS cb_llama_compile=4)
set(CMAKE_JOB_POOL_COMPILE cb_llama_compile)
set(CMAKE_JOB_POOL_LINK cb_llama_compile)

include(FetchContent)
# Match the Windows runtime so both platforms use the same model/chat support.
FetchContent_Declare(llama
    URL https://codeload.github.com/ggml-org/llama.cpp/tar.gz/refs/tags/b10809
    URL_HASH SHA256=097848e79245e784c3bd4fcf2d6e1b46ad24553f3840e65a678131825504a8d2)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
set(GGML_CPU_KLEIDIAI OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_MTMD ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
set(LLAMA_TOOLS_INSTALL OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_NUMBER 10809 CACHE STRING "" FORCE)
set(LLAMA_BUILD_COMMIT b10809 CACHE STRING "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
# Flutter's profile config has no default compiler flags; optimize it and debug
# APKs too, because unoptimized CPU inference is unusably slow.
add_compile_options("$<$<OR:$<CONFIG:Debug>,$<CONFIG:Profile>>:-O2>")
add_link_options("-Wl,-z,max-page-size=16384")
FetchContent_MakeAvailable(llama)

# The Flutter client only uses HTTP. Supply the upstream empty asset interface
# without building/downloading a web UI or requiring a host C++ compiler.
add_library(llama-ui STATIC ui.cpp)
target_include_directories(llama-ui PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_features(llama-ui PRIVATE cxx_std_17)
add_subdirectory("${llama_SOURCE_DIR}/tools/server" server)
target_include_directories(server-context PRIVATE "${llama_SOURCE_DIR}")
target_include_directories(llama-server-impl PRIVATE "${llama_SOURCE_DIR}")
set_property(TARGET llama-server PROPERTY SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/main.cpp")

# Android's installer extracts lib*.so from jniLibs into nativeLibraryDir.
# This file is a PIE executable, named .so solely for APK packaging.
# Flutter passes the variant name as CMAKE_BUILD_TYPE (debug/profile/release).
string(TOLOWER "${CMAKE_BUILD_TYPE}" CB_LLAMA_VARIANT)
set_target_properties(llama-server PROPERTIES
    OUTPUT_NAME libcb_llama_server SUFFIX .so
    RUNTIME_OUTPUT_DIRECTORY "${CB_LLAMA_PACKAGE_ROOT}/${CB_LLAMA_VARIANT}/${ANDROID_ABI}")
