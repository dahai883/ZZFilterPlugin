SDKROOT := $(shell xcrun --sdk iphoneos --show-sdk-path)
CLANG := xcrun --sdk iphoneos clang
ARCHS := -arch arm64 -arch arm64e
CFLAGS := -fobjc-arc -isysroot $(SDKROOT) -miphoneos-version-min=16.0 $(ARCHS) -Wall -Wextra -DZZ_DEBUG=1 -g -O0 -fno-omit-frame-pointer
LDFLAGS := -dynamiclib $(ARCHS) -framework Foundation -framework CoreFoundation -framework UIKit

SOURCES := ZZFilterPlugin.m ZZFilterURLProtocol.m ZZProductFilter.m ZZDetailFetcher.m ZZSettings.m ZZOverlayController.m ZZDebug.m
OBJECTS := $(SOURCES:.m=.o)

all: ZZFilterPlugin.dylib

ZZFilterPlugin.dylib: $(OBJECTS)
	$(CLANG) $(LDFLAGS) -o $@ $(OBJECTS)

%.o: %.m
	$(CLANG) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJECTS) ZZFilterPlugin.dylib
