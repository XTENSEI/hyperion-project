#!/bin/bash
# =============================================================================
# Hyperion Project - Build Script
# Made by ShadowBytePrjkt
# =============================================================================
# Builds C binaries for Android (multi-architecture like Stellar)
# Also supports native Linux build for testing
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}  Hyperion Project - Build Script v1.0.0${NC}"
echo -e "${BLUE}==============================================${NC}"
echo ""

# Check for required files
if [ ! -f "hyperion_daemon.c" ]; then
    echo -e "${RED}Error: hyperion_daemon.c not found!${NC}"
    exit 1
fi

if [ ! -f "hyperion_utils.c" ]; then
    echo -e "${RED}Error: hyperion_utils.c not found!${NC}"
    exit 1
fi

# Create output directory for binaries
OUTPUT_DIR="../system/bin"
mkdir -p "$OUTPUT_DIR"

# Function to find Android NDK
find_ndk() {
    local paths=(
        "$ANDROID_NDK"
        "/opt/android-ndk"
        "$HOME/Android/Sdk/ndk"
        "/usr/local/android-ndk"
        "/android-ndk"
        "$HOME/ndk"
        "/opt/ndk"
        "$HOME/android-ndk"
        "$HOME/ndk-bundle"
    )
    
    # Check common versioned paths
    local version_paths=(
        "/opt/android-ndk-*"
        "$HOME/Android/Sdk/ndk/*"
        "$HOME/ndk/*"
    )
    
    for path in "${paths[@]}"; do
        if [ -n "$path" ] && [ -d "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    # Try glob patterns
    for path in "${version_paths[@]}"; do
        local found=$(ls -d $path 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            echo "$found"
            return 0
        fi
    done
    
    return 1
}

# Check for Android NDK
ANDROID_NDK=$(find_ndk)

if [ -z "$ANDROID_NDK" ]; then
    echo -e "${YELLOW}Android NDK not found!${NC}"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  1. Install Android NDK"
    echo "  2. Set ANDROID_NDK environment variable"
    echo "  3. Use native Linux build (for testing only)"
    echo ""
    read -p "Build for native Linux instead? (y/n): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Building for native Linux (for testing)...${NC}"
        
        # Native Linux build
        gcc -O2 -Wall -Wextra -s -o "$OUTPUT_DIR/hyperiond" hyperion_daemon.c
        gcc -O2 -Wall -Wextra -s -o "$OUTPUT_DIR/hyperion" hyperion_utils.c
        
        chmod 755 "$OUTPUT_DIR/hyperiond" "$OUTPUT_DIR/hyperion"
        
        echo ""
        echo -e "${GREEN}Build complete!${NC}"
        echo "Binaries created in: $OUTPUT_DIR"
        echo "  - hyperiond (daemon)"
        echo "  - hyperion (utils)"
        echo ""
        echo "Note: These are Linux binaries, not Android!"
        echo "For Android, please install Android NDK."
        exit 0
    fi
    
    echo -e "${RED}Cannot build without Android NDK.${NC}"
    exit 1
fi

echo -e "${GREEN}Using Android NDK: $ANDROID_NDK${NC}"

# Toolchain paths
TOOLCHAIN="$ANDROID_NDK/toolchains/llvm/prebuilt"

# Detect OS
if [ "$(uname)" = "Darwin" ]; then
    if [ -d "$TOOLCHAIN/darwin-x86_64" ]; then
        TOOLCHAIN="$TOOLCHAIN/darwin-x86_64"
    elif [ -d "$TOOLCHAIN/darwin-arm64" ]; then
        TOOLCHAIN="$TOOLCHAIN/darwin-arm64"
    fi
elif [ "$(uname)" = "Linux" ]; then
    if [ -d "$TOOLCHAIN/linux-x86_64" ]; then
        TOOLCHAIN="$TOOLCHAIN/linux-x86_64"
    fi
fi

if [ ! -d "$TOOLCHAIN" ]; then
    echo -e "${RED}Error: Toolchain not found at $TOOLCHAIN${NC}"
    echo "Please check your NDK installation."
    exit 1
fi

echo -e "${GREEN}Toolchain: $TOOLCHAIN${NC}"
echo ""

# Build function
build_arch() {
    local arch=$1
    local prefix=$2
    local target=$3
    
    echo -e "${YELLOW}Building for $arch...${NC}"
    
    # Build daemon
    ${prefix}clang++ -O2 -Wall -Wextra -s -target $target -o "$OUTPUT_DIR/hyperiond-$arch" hyperion_daemon.c 2>/dev/null || \
    ${prefix}clang -O2 -Wall -Wextra -s -target $target -o "$OUTPUT_DIR/hyperiond-$arch" hyperion_daemon.c
    
    # Build utils
    ${prefix}clang++ -O2 -Wall -Wextra -s -target $target -o "$OUTPUT_DIR/hyperion-$arch" hyperion_utils.c 2>/dev/null || \
    ${prefix}clang -O2 -Wall -Wextra -s -target $target -o "$OUTPUT_DIR/hyperion-$arch" hyperion_utils.c
    
    echo -e "${GREEN}  ✓ $arch complete${NC}"
}

# Build for all architectures
echo -e "${BLUE}Building hyperiond (daemon) and hyperion (utils)...${NC}"
echo ""

# ARM64-v8a
build_arch "arm64-v8a" "$TOOLCHAIN/aarch64-linux-android-" "aarch64-linux-android21"

# ARMv7
build_arch "armv7" "$TOOLCHAIN/armv7a-linux-androideabi-" "armv7a-linux-androideabi21"

# x86
build_arch "x86" "$TOOLCHAIN/i686-linux-android-" "i686-linux-android21"

# x86_64
build_arch "x86_64" "$TOOLCHAIN/x86_64-linux-android-" "x86_64-linux-android21"

echo ""

# Create convenience symlinks
echo -e "${BLUE}Creating symlinks...${NC}"
cd "$OUTPUT_DIR"

# Default: use arm64
if [ -f "hyperiond-arm64-v8a" ]; then
    cp hyperiond-arm64-v8a hyperiond
    cp hyperion-arm64-v8a hyperion
    echo -e "${GREEN}  Created default binaries (arm64-v8a)${NC}"
fi

# Make executable
chmod 755 hyperiond hyperion
chmod 755 hyperiond-* hyperion-*

echo ""
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}  Build Complete!${NC}"
echo -e "${GREEN}==============================================${NC}"
echo ""
echo "Binaries created in: $OUTPUT_DIR"
echo ""
echo "  hyperiond              - System monitor daemon (default: arm64)"
echo "  hyperion               - System optimization utilities (default: arm64)"
echo ""
echo "Architecture-specific binaries:"
ls -la hyperiond-* 2>/dev/null || true
ls -la hyperion-* 2>/dev/null || true
echo ""
echo -e "${YELLOW}Usage:${NC}"
echo "  ./hyperion cpu              - Show CPU info"
echo "  ./hyperion gpu              - Show GPU info"
echo "  ./hyperion mem              - Show memory info"
echo "  ./hyperion boost            - Enable gaming boost"
echo "  ./hyperion unboost          - Disable gaming boost"
echo ""
