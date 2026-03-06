#!/bin/bash

# Build script for Raspberry Pi 5
# Cross-compiles da_connector.c from WSL to ARM64 target

echo "Building da_connector for Raspberry Pi 5 (ARM64)..."

# Check if ARM64 cross-compilers are installed
ARM_CC="aarch64-linux-gnu-gcc"
ARM_CXX="aarch64-linux-gnu-g++"

if ! command -v $ARM_CC &> /dev/null || ! command -v $ARM_CXX &> /dev/null; then
    echo "ARM64 cross-compiler not found!"
    echo "Installing cross-compilation toolchain..."
    sudo apt-get update
    sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
    
    if ! command -v $ARM_CC &> /dev/null || ! command -v $ARM_CXX &> /dev/null; then
        echo "ERROR: Failed to install ARM64 cross-compiler."
        echo "Please install manually: sudo apt-get install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu"
        exit 1
    fi
fi

# Compiler settings for ARM64 target
CC=$ARM_CC
CXX=$ARM_CXX
# include project root (.) so headers such as da_connector.h are found
CFLAGS="-O2 -fPIC -march=armv8-a -w -I."
CXXFLAGS="-O2 -fPIC -march=armv8-a -w -std=c++17 -I. -Ilocal/protogen -Ilocal/protogen/kuksa/val/v1"
LDFLAGS="-shared"

# gRPC and protobuf libraries (will be available on target RPi5)
GRPC_LIBS="-lgrpc++ -lgrpc -lgpr -lprotobuf -lpthread -ldl"

# Source files
C_SOURCES="da_connector.c"
CPP_SOURCES="client.cpp"
# protobuf sources are discovered automatically in the protogen tree
PROTOBUF_SOURCES=""
MAIN_SOURCE="local/main.c"
HEADERS="da_connector.h kuksa_bridge.h"

# Build directory
BUILD_DIR="build_rpi"

# Outputs
EXE_OUTPUT="$BUILD_DIR/da_connector_app"

# Create build directory if it doesn't exist
if [ ! -d "$BUILD_DIR" ]; then
    echo "Creating build directory..."
    mkdir -p "$BUILD_DIR"
fi

# Check if source files exist
if [ ! -f "da_connector.c" ]; then
    echo "ERROR: da_connector.c not found!"
    exit 1
fi

if [ ! -f "client.cpp" ]; then
    echo "ERROR: client.cpp not found!"
    exit 1
fi

if [ ! -f "da_connector.h" ]; then
    echo "ERROR: da_connector.h not found!"
    exit 1
fi

if [ ! -f "kuksa_bridge.h" ]; then
    echo "ERROR: kuksa_bridge.h not found!"
    exit 1
fi

if [ ! -f "local/main.c" ]; then
    echo "ERROR: local/main.c not found!"
    exit 1
fi

# Compile C source to object file
echo "Compiling C source: $C_SOURCES..."
$CC $CFLAGS -c -o $BUILD_DIR/da_connector.o $C_SOURCES

if [ $? -ne 0 ]; then
    echo "ERROR: C compilation failed!"
    exit 1
fi

# Compile protobuf generated files
# Automatically build any .pb.cpp files present in the protogen directory
PROTO_DIR="local/protogen/kuksa/val/v1"
echo "Compiling protobuf sources in $PROTO_DIR..."
for src in "$PROTO_DIR"/*.pb.cpp; do
    [ -e "$src" ] || continue
    obj="$BUILD_DIR/$(basename "$src" .cpp).o"
    echo "  $src -> $obj"
    $CXX $CXXFLAGS -c -o "$obj" "$src"
    if [ $? -ne 0 ]; then
        echo "ERROR: Protobuf compilation failed for $src!"
        exit 1
    fi
done

# Compile C++ source to object file
echo "Compiling C++ source: $CPP_SOURCES..."
$CXX $CXXFLAGS -c -o $BUILD_DIR/client.o $CPP_SOURCES

if [ $? -ne 0 ]; then
    echo "ERROR: C++ compilation failed!"
    exit 1
fi

# Compile the executable using C++ linker (since it links with C++ code)
echo "Compiling executable $MAIN_SOURCE..."
$CC $CFLAGS -c -o $BUILD_DIR/main.o $MAIN_SOURCE

if [ $? -ne 0 ]; then
    echo "ERROR: Main compilation failed!"
    exit 1
fi

echo "Linking executable..."
# link every object in build directory; this covers generated protobuf objects too
objs=$(ls $BUILD_DIR/*.o 2>/dev/null)
$CXX -o $EXE_OUTPUT $objs $GRPC_LIBS

# Check if compilation was successful
if [ $? -eq 0 ]; then
    echo "Executable build successful! Output: $EXE_OUTPUT"
    ls -lh $EXE_OUTPUT
    echo ""
    echo "To verify ARM64 architecture:"
    echo "  file $EXE_OUTPUT"
    echo ""
    echo "Transfer to RPi5 and ensure these libraries are installed:"
    echo "  sudo apt-get install libgrpc++-dev libprotobuf-dev"
else
    echo "ERROR: Executable build failed!"
    exit 1
fi

echo "Build complete!"
