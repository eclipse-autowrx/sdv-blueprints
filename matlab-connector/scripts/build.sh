#!/bin/bash

# Build script for local machine
# Compiles da_connector.c natively

echo "Building da_connector for local machine..."

# Compiler settings for native compilation
CC="gcc"
CXX="g++"
# include project root (.) so headers such as da_connector.h are found
# use pkg-config to query grpc++ flags if available
if command -v pkg-config >/dev/null 2>&1; then
    GRPC_CFLAGS=$(pkg-config --cflags grpc++ 2>/dev/null || true)
    GRPC_LIBS=$(pkg-config --libs grpc++ 2>/dev/null || true)
else
    GRPC_CFLAGS=""
    GRPC_LIBS=""
fi

CFLAGS="-O2 -fPIC -w -I. $GRPC_CFLAGS"
CXXFLAGS="-O2 -fPIC -w -std=c++17 -I. -Ilocal/protogen $GRPC_CFLAGS"
LDFLAGS="-shared"

# always link protobuf as well (pkg-config for grpc++ does not include it)
GRPC_LIBS="$GRPC_LIBS -lprotobuf"

# if pkg-config didn't yield any grpc libs at all, fall back to a minimal set
if [ -z "$GRPC_LIBS" ]; then
    GRPC_LIBS="-lgrpc++ -lgrpc -lgpr -lprotobuf -lpthread -ldl"
fi

# Source files
C_SOURCES="da_connector.c"
CPP_SOURCES="client.cpp"
# protobuf sources are discovered automatically in the protogen tree
PROTOBUF_SOURCES=""
MAIN_SOURCE="local/main.c"
HEADERS="da_connector.h kuksa_bridge.h"

# Build directory
BUILD_DIR="build"

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

# Ensure we have protobuf definitions and generated sources
PROTO_DIR="local/protos"
GEN_DIR="local/protogen"

# if proto directory is missing or empty, try to clone kuksa-databroker and copy
if [ ! -d "$PROTO_DIR/kuksa/val/v1" ] || \
   [ -z "$(ls -A $PROTO_DIR/kuksa/val/v1 2>/dev/null)" ]; then
    echo "Proto definitions not found in $PROTO_DIR/kuksa/val/v1."
    echo "Attempting to fetch from eclipse/kuksa-databroker repository..."
    if ! command -v git >/dev/null 2>&1; then
        echo "ERROR: git is required to clone protos but is not installed."
        echo "Please install git or place the proto files manually."
        exit 1
    fi
    tmp=$(mktemp -d)
  
    mkdir -p "$PROTO_DIR/kuksa/val/v1"
    cp -r "$tmp"/proto/kuksa/val/v1/* "$PROTO_DIR/kuksa/val/v1/" || {
        echo "ERROR: copying proto files failed"
        rm -rf "$tmp"
        exit 1
    }
    rm -rf "$tmp"
    echo "Copied proto definitions into $PROTO_DIR/kuksa/val/v1."
fi

# regenerate C++ from every .proto file; this will create missing types.pb.*
if [ -d "$PROTO_DIR/kuksa/val/v1" ]; then
    echo "Generating C++ sources from protos in $PROTO_DIR/kuksa/val/v1..."
    for proto in "$PROTO_DIR"/kuksa/val/v1/*.proto; do
        [ -e "$proto" ] || continue
        echo "  protoc processing $proto"
        protoc -I"$PROTO_DIR" \
               --cpp_out="$GEN_DIR" \
               --grpc_out="$GEN_DIR" \
               --plugin=protoc-gen-grpc=$(which grpc_cpp_plugin) \
               "$proto" || {
            echo "ERROR: protoc failed for $proto"
            exit 1
        }
    done
fi

# Compile protobuf generated files
# Automatically build any .pb.cc files present in the protogen directory
PROTO_DIR="local/protogen/kuksa/val/v1"
echo "Compiling protobuf sources in $PROTO_DIR..."
for src in "$PROTO_DIR"/*.pb.cc; do
    [ -e "$src" ] || continue
    obj="$BUILD_DIR/$(basename "$src" .cc).o"
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
else
    echo "ERROR: Executable build failed!"
    exit 1
fi

echo "Build complete!"
