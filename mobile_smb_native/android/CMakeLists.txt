cmake_minimum_required(VERSION 3.10.2)

project(smb_bridge)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add include directories
include_directories(../native/include)

# Find prebuilt libraries
find_library(log-lib log)

# Source files for the shared library - using stub implementation
set(SOURCES
    ../native/smb_bridge_stub.cpp
)

# Create shared library
add_library(smb_bridge SHARED ${SOURCES})

# Link libraries
target_link_libraries(smb_bridge
    ${log-lib}
    # Note: libsmbclient libraries will need to be provided as prebuilt libraries
    # or built from source for Android
)

if(ANDROID)
    target_link_options(smb_bridge PRIVATE "-Wl,-z,max-page-size=16384")
endif()

# LibVLC support removed - now using flutter_vlc_player

# Set library properties
set_target_properties(smb_bridge PROPERTIES
    VERSION 1.0.0
    SOVERSION 1
)
