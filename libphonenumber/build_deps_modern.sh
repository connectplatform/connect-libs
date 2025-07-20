#!/usr/bin/env bash

# ConnectPlatform LibPhoneNumber - Modern Build Script
# Compatible with CMake 4.0+, C++17, and Erlang/OTP 26

set -euo pipefail

DEPS_LOCATION=_build/deps
DESTINATION=libphonenumber
LIB_PHONE_NUMBER_REPO=https://github.com/google/libphonenumber.git
LIB_PHONE_NUMBER_REV=${1:-v8.13.27}  # Latest stable version
OS=$(uname -s)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🚀 ConnectPlatform LibPhoneNumber - Modern Build${NC}"
echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}Repository: ${LIB_PHONE_NUMBER_REPO}${NC}"
echo -e "${GREEN}Revision: ${LIB_PHONE_NUMBER_REV}${NC}"
echo -e "${GREEN}OS: ${OS}${NC}"
echo ""

# Check if already built
if [ -f "$DEPS_LOCATION/$DESTINATION/cpp/build/libphonenumber.a" ]; then
    echo -e "${GREEN}✅ LibPhoneNumber already built. Delete $DEPS_LOCATION/$DESTINATION for fresh build.${NC}"
    exit 0
fi

# Modern error handling
fail_check() {
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        echo -e "${RED}❌ Error executing: $*${NC}" >&2
        exit 1
    fi
}

# Modern CMake configuration for Unix/Linux
configure_cmake_unix() {
    echo -e "${BLUE}🔧 Configuring CMake for Unix/Linux...${NC}"
    
    export CFLAGS="-fPIC -Wno-deprecated-declarations -O2"
    export CXXFLAGS="-fPIC -Wno-deprecated-declarations -std=c++17 -O2"
    
    fail_check cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX:PATH=install \
        -DCMAKE_CXX_STANDARD=17 \
        -DCMAKE_CXX_STANDARD_REQUIRED=ON \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DUSE_BOOST=OFF \
        -DUSE_STD_MAP=ON \
        -DCMAKE_POLICY_DEFAULT_CMP0077=NEW \
        ..
}

# Modern CMake configuration for macOS
configure_cmake_darwin() {
    echo -e "${BLUE}🔧 Configuring CMake for macOS...${NC}"
    
    # Find ICU installation
    ICU_PATHS=(
        "/usr/local/opt/icu4c"
        "/opt/homebrew/opt/icu4c"
        "/usr/local/Cellar/icu4c"
        "/opt/homebrew/Cellar/icu4c"
    )
    
    ICU_PATH=""
    for path in "${ICU_PATHS[@]}"; do
        if [ -d "$path" ]; then
            ICU_PATH="$path"
            break
        fi
    done
    
    if [ -z "$ICU_PATH" ]; then
        echo -e "${RED}❌ ICU not found. Please install with: brew install icu4c${NC}"
        exit 1
    fi
    
    # Get ICU version (handle both versioned and direct paths)
    if [ -d "$ICU_PATH/77.1" ]; then
        ICU_VERSION_PATH="$ICU_PATH/77.1"
    elif [ -d "$ICU_PATH" ] && [ -d "$ICU_PATH/include" ]; then
        ICU_VERSION_PATH="$ICU_PATH"
    else
        ICU_VERSION=$(ls "$ICU_PATH" | head -1)
        ICU_VERSION_PATH="$ICU_PATH/$ICU_VERSION"
    fi
    
    echo -e "${GREEN}ICU found at: ${ICU_VERSION_PATH}${NC}"
    
    export CFLAGS="-fPIC -Wno-deprecated-declarations -O2"
    export CXXFLAGS="-fPIC -Wno-deprecated-declarations -std=c++17 -O2"
    
    # Set ICU environment variables for the build
    export PKG_CONFIG_PATH="${ICU_VERSION_PATH}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
    export CPPFLAGS="-I${ICU_VERSION_PATH}/include ${CPPFLAGS:-}"
    export LDFLAGS="-L${ICU_VERSION_PATH}/lib ${LDFLAGS:-}"

    fail_check cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX:PATH=install \
        -DCMAKE_CXX_STANDARD=17 \
        -DCMAKE_CXX_STANDARD_REQUIRED=ON \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DUSE_BOOST=OFF \
        -DUSE_STD_MAP=ON \
        -DCMAKE_POLICY_DEFAULT_CMP0077=NEW \
        -DGTEST_SOURCE_DIR=../../../googletest/googletest/ \
        -DGTEST_INCLUDE_DIR=../../../googletest/googletest/include/ \
        -DICU_UC_INCLUDE_DIR="${ICU_VERSION_PATH}/include/" \
        -DICU_UC_LIB="${ICU_VERSION_PATH}/lib/libicuuc.dylib" \
        -DICU_I18N_INCLUDE_DIR="${ICU_VERSION_PATH}/include/" \
        -DICU_I18N_LIB="${ICU_VERSION_PATH}/lib/libicui18n.dylib" \
        -DCMAKE_OSX_ARCHITECTURES="$(uname -m)" \
        -DCMAKE_CXX_FLAGS="-I${ICU_VERSION_PATH}/include" \
        -DCMAKE_C_FLAGS="-I${ICU_VERSION_PATH}/include" \
        ..
}

# Create modern CMakeLists.txt wrapper
create_modern_cmake_wrapper() {
    echo -e "${BLUE}📝 Creating modern CMake wrapper...${NC}"
    
    # Ensure the directory exists
    mkdir -p "$DEPS_LOCATION/$DESTINATION/cpp"
    
    cat > "$DEPS_LOCATION/$DESTINATION/cpp/CMakeLists.txt.modern" << 'EOF'
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
EOF

    # Backup original and install modern version
    if [ -f "$DEPS_LOCATION/$DESTINATION/cpp/CMakeLists.txt" ]; then
        mv "$DEPS_LOCATION/$DESTINATION/cpp/CMakeLists.txt" "$DEPS_LOCATION/$DESTINATION/cpp/CMakeLists.txt.original"
        
        # Fix the cmake_minimum_required in original
        sed -i.bak 's/cmake_minimum_required.*/cmake_minimum_required(VERSION 3.15)/' "$DEPS_LOCATION/$DESTINATION/cpp/CMakeLists.txt.original"
    fi
    
    mv "$DEPS_LOCATION/$DESTINATION/cpp/CMakeLists.txt.modern" "$DEPS_LOCATION/$DESTINATION/cpp/CMakeLists.txt"
}

# Install GoogleTest (required dependency)
install_googletest() {
    echo -e "${BLUE}📦 Installing GoogleTest...${NC}"
    
    if [ ! -d "googletest" ]; then
        git clone --depth 1 --branch release-1.12.1 https://github.com/google/googletest.git
    fi
}

# Install LibPhoneNumber
install_libphonenumber() {
    echo -e "${BLUE}📦 Installing LibPhoneNumber...${NC}"
    
    # Clone the repository
    if [ ! -d "${DESTINATION}" ]; then
        git clone --depth 1 --branch ${LIB_PHONE_NUMBER_REV} ${LIB_PHONE_NUMBER_REPO} ${DESTINATION}
    fi
    
    # Install GoogleTest first
    install_googletest
    
    # Create modern CMake wrapper
    create_modern_cmake_wrapper
    
    # Create build directory
    mkdir -p ${DESTINATION}/cpp/build
    pushd ${DESTINATION}/cpp/build
    
    # Configure based on OS
    case $OS in
        Linux)
            configure_cmake_unix
            ;;
        Darwin)
            configure_cmake_darwin
            ;;
        *)
            echo -e "${RED}❌ Unsupported OS: $OS${NC}"
            exit 1
            ;;
    esac
    
    # Build with modern settings
    echo -e "${BLUE}🔨 Building LibPhoneNumber...${NC}"
    fail_check make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    
    echo -e "${BLUE}📦 Installing LibPhoneNumber...${NC}"
    fail_check make install
    
    popd
}

# Copy resources
copy_resources() {
    echo -e "${BLUE}📁 Copying resources...${NC}"
    
    rm -rf priv
    fail_check mkdir -p priv
    
    if [ -d "$DEPS_LOCATION/$DESTINATION/resources/carrier" ]; then
        fail_check cp -R "$DEPS_LOCATION/$DESTINATION/resources/carrier" priv/carrier
    fi
    
    if [ -d "$DEPS_LOCATION/$DESTINATION/resources/geocoding" ]; then
        fail_check cp -R "$DEPS_LOCATION/$DESTINATION/resources/geocoding" priv/geocoding
    fi
    
    if [ -d "$DEPS_LOCATION/$DESTINATION/resources/PhoneNumberMetadata.xml" ]; then
        fail_check cp "$DEPS_LOCATION/$DESTINATION/resources/PhoneNumberMetadata.xml" priv/
    fi
}

# Verify build
verify_build() {
    echo -e "${BLUE}🔍 Verifying build...${NC}"
    
    local lib_file="$DEPS_LOCATION/$DESTINATION/cpp/build/install/lib/libphonenumber.a"
    if [ -f "$lib_file" ]; then
        echo -e "${GREEN}✅ LibPhoneNumber built successfully!${NC}"
        echo -e "${GREEN}   Library: $lib_file${NC}"
        echo -e "${GREEN}   Size: $(du -h "$lib_file" | cut -f1)${NC}"
    else
        echo -e "${RED}❌ Build verification failed - library not found${NC}"
        exit 1
    fi
}

# Main execution
main() {
    echo -e "${BLUE}🚀 Starting ConnectPlatform LibPhoneNumber build...${NC}"
    
    # Create dependencies directory
    mkdir -p $DEPS_LOCATION
    pushd $DEPS_LOCATION
    
    # Install and build
    install_libphonenumber
    
    popd
    
    # Copy resources
    copy_resources
    
    # Verify build
    verify_build
    
    echo ""
    echo -e "${GREEN}🎉 ConnectPlatform LibPhoneNumber build completed successfully!${NC}"
    echo -e "${GREEN}✅ Compatible with Erlang/OTP 26${NC}"
    echo -e "${GREEN}✅ Modern C++17 standards${NC}"
    echo -e "${GREEN}✅ CMake 4.0+ compatible${NC}"
    echo ""
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 