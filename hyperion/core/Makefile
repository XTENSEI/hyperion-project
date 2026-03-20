# =============================================================================
# Hyperion Project - Makefile for C Binaries
# Made by ShadowBytePrjkt
# Multi-architecture build like Stellar
# =============================================================================

CC ?= gcc
CFLAGS = -O2 -Wall -Wextra -s
LDFLAGS =

# Binary names
DAEMON = hyperiond
UTILS = hyperion

# Source files
DAEMON_SRC = hyperion_daemon.c
UTILS_SRC = hyperion_utils.c

# Android NDK
ANDROID_NDK ?= $(ANDROID_NDK_HOME)
ifeq ($(ANDROID_NDK),)
    ANDROID_NDK := /opt/android-ndk
endif

# Toolchains
ANDROID_TOOLCHAIN = $(ANDROID_NDK)/toolchains/llvm/prebuilt/darwin-x86_64/bin
ANDROID_LINUX_TOOLCHAIN = $(ANDROID_NDK)/toolchains/llvm/prebuilt/linux-x86_64/bin

.PHONY: all clean android arm64 arm7 x86 x86_64 help install

# Default: build for host
all: $(DAEMON) $(UTILS)

# Build daemon for host
$(DAEMON): $(DAEMON_SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

# Build utils for host
$(UTILS): $(UTILS_SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

# ============= Android Builds =============
android: arm64 arm7 x86 x86_64

# ARM64-v8a (primary)
arm64: CROSS_PREFIX=$(ANDROID_TOOLCHAIN)/aarch64-linux-android-
arm64: $(DAEMON)-arm64 $(UTILS)-arm64

$(DAEMON)-arm64: $(DAEMON_SRC)
	$(CROSS_PREFIX)clang++ $(CFLAGS) -target aarch64-linux-android21 -o $@ $< $(LDFLAGS)

$(UTILS)-arm64: $(UTILS_SRC)
	$(CROSS_PREFIX)clang++ $(CFLAGS) -target aarch64-linux-android21 -o $@ $< $(LDFLAGS)

# ARMv7
arm7: CROSS_PREFIX=$(ANDROID_TOOLCHAIN)/armv7a-linux-androideabi-
arm7: $(DAEMON)-arm7 $(UTILS)-arm7

$(DAEMON)-arm7: $(DAEMON_SRC)
	$(CROSS_PREFIX)clang++ $(CFLAGS) -target armv7a-linux-androideabi21 -o $@ $< $(LDFLAGS)

$(UTILS)-arm7: $(UTILS_SRC)
	$(CROSS_PREFIX)clang++ $(CFLAGS) -target armv7a-linux-androideabi21 -o $@ $< $(LDFLAGS)

# x86
x86: CROSS_PREFIX=$(ANDROID_TOOLCHAIN)/i686-linux-android-
x86: $(DAEMON)-x86 $(UTILS)-x86

$(DAEMON)-x86: $(DAEMON_SRC)
	$(CROSS_PREFIX)clang++ $(CFLAGS) -target i686-linux-android21 -o $@ $< $(LDFLAGS)

$(UTILS)-x86: $(UTILS_SRC)
	$(CROSS_PREFIX)clang++ $(CFLAGS) -target i686-linux-android21 -o $@ $< $(LDFLAGS)

# x86_64
x86_64: CROSS_PREFIX=$(ANDROID_TOOLCHAIN)/x86_64-linux-android-
x86_64: $(DAEMON)-x86_64 $(UTILS)-x86_64

$(DAEMON)-x86_64: $(DAEMON_SRC)
	$(CROSS_PREFIX)clang++ $(CFLAGS) -target x86_64-linux-android21 -o $@ $< $(LDFLAGS)

$(UTILS)-x86_64: $(UTILS_SRC)
	$(CROSS_PREFIX)clang++ $(CFLAGS) -target x86_64-linux-android21 -o $@ $< $(LDFLAGS)

# Clean all
clean:
	rm -f $(DAEMON) $(UTILS) $(DAEMON)-arm64 $(DAEMON)-arm7 $(DAEMON)-x86 $(DAEMON)-x86_64
	rm -f $(UTILS)-arm64 $(UTILS)-arm7 $(UTILS)-x86 $(UTILS)-x86_64

# Install binaries to module
install:
	install -m 755 $(DAEMON)-arm64 ../system/bin/$(DAEMON)
	install -m 755 $(DAEMON)-arm7 ../system/bin/$(DAEMON)
	install -m 755 $(DAEMON)-x86 ../system/bin/$(DAEMON)
	install -m 755 $(DAEMON)-x86_64 ../system/bin/$(DAEMON)
	install -m 755 $(UTILS)-arm64 ../system/bin/$(UTILS)
	install -m 755 $(UTILS)-arm7 ../system/bin/$(UTILS)
	install -m 755 $(UTILS)-x86 ../system/bin/$(UTILS)
	install -m 755 $(UTILS)-x86_64 ../system/bin/$(UTILS)

# Help
help:
	@echo "Hyperion Project - Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all     - Build daemon and utils for host"
	@echo "  android - Build all Android architectures"
	@echo "  arm64   - Build arm64-v8a (primary)"
	@echo "  arm7    - Build ARMv7"
	@echo "  x86     - Build x86"
	@echo "  x86_64  - Build x86_64"
	@echo "  clean   - Remove all build artifacts"
	@echo "  install - Install to module directory"
	@echo ""
	@echo "Binaries:"
	@echo "  hyperiond - System monitor daemon"
	@echo "  hyperion  - System optimization utilities (SAC-like)"
	@echo ""
	@echo "Variables:"
	@echo "  CC          - C compiler (default: gcc)"
	@echo "  CFLAGS      - Compiler flags (default: -O2 -Wall -Wextra -s)"
	@echo "  ANDROID_NDK - Android NDK path"
