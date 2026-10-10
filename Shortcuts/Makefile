TARGET := iphone:clang:16.5:16.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk
TWEAK_NAME := ZZNo2TheftShortcutGPS
ZZNo2TheftShortcutGPS_FILES := ShortcutsEmailHook.m
ZZNo2TheftShortcutGPS_FRAMEWORKS := Foundation
ZZNo2TheftShortcutGPS_LIBRARIES := substrate
ZZNo2TheftShortcutGPS_CFLAGS := -fobjc-arc
include $(THEOS_MAKE_PATH)/tweak.mk

TOOL_NAME := N2TShortcutLocation
N2TShortcutLocation_FILES := ShortcutLocation.m
N2TShortcutLocation_FRAMEWORKS := Foundation CoreLocation
N2TShortcutLocation_CFLAGS := -fobjc-arc -Wno-deprecated-declarations
N2TShortcutLocation_CODESIGN_FLAGS := -SShortcutsLocation.entitlements
include $(THEOS_MAKE_PATH)/tool.mk
