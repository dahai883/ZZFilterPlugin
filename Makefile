SDKROOT := $(shell xcrun --sdk iphoneos --show-sdk-path)
CLANG := xcrun --sdk iphoneos clang
ARCHS := -arch arm64 -arch arm64e
CFLAGS := -fobjc-arc -isysroot $(SDKROOT) -miphoneos-version-min=16.0 $(ARCHS) -Wall -Wextra -DZZ_DEBUG=1 -g -O0 -fno-omit-frame-pointer
LDFLAGS := -dynamiclib $(ARCHS) -framework Foundation -framework CoreFoundation -framework CoreGraphics -framework UIKit -framework QuartzCore

SOURCES := ZZFilterPlugin.m ZZFilterURLProtocol.m ZZProductFilter.m ZZProductVisibility.m ZZDetailFetcher.m ZZSettings.m ZZOverlayController.m ZZOverlayBootstrap.m ZZNetworkInterception.m ZZDebug.m ZZRuntimeFiltering.m
OBJECTS := $(SOURCES:.m=.o)

all: ZZFilterPlugin.dylib

ZZFilterPlugin.dylib: $(OBJECTS)
	$(CLANG) $(LDFLAGS) -o $@ $(OBJECTS)

%.o: %.m
	$(CLANG) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJECTS) ZZFilterPlugin.dylib
