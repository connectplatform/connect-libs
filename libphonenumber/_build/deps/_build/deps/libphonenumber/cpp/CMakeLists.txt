# ConnectPlatform LibPhoneNumber - Modern CMake Wrapper
# Compatible with CMake 3.15+ and C++17

cmake_minimum_required(VERSION 3.15)

# Set policies for modern CMake
cmake_policy(VERSION 3.15)
if(POLICY CMP0077)
    cmake_policy(SET CMP0077 NEW)
endif()

project(libphonenumber 
    VERSION 8.13.27
    LANGUAGES CXX C
    DESCRIPTION "Google's libphonenumber library - ConnectPlatform modernized version"
)

# Modern C++ standards
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Position independent code for shared libraries
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Include the original CMakeLists.txt with compatibility fixes
include(CMakeLists.txt.original)
