SDKROOT := $(shell xcrun --sdk iphoneos --show-sdk-path)
CLANG := xcrun --sdk iphoneos clang
ARCHS := -arch arm64 -arch arm64e
CFLAGS := -fobjc-arc -isysroot $(SDKROOT) -miphoneos-version-min=16.0 $(ARCHS) -Wall -Wextra
LDFLAGS := -dynamiclib $(ARCHS) -framework Foundation -framework CoreFoundation

SOURCES := ZZFilterPlugin.m ZZFilterURLProtocol.m ZZProductFilter.m ZZDetailFetcher.m ZZSettings.m
OBJECTS := $(SOURCES:.m=.o)

all: ZZFilterPlugin.dylib

ZZFilterPlugin.dylib: $(OBJECTS)
	$(CLANG) $(LDFLAGS) -o $@ $(OBJECTS)

%.o: %.m
	$(CLANG) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJECTS) ZZFilterPlugin.dylib
