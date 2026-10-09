TARGET := iphone:clang:16.0:16.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZZNo2TheftGPS
ZZNo2TheftGPS_FILES = Tweak.m
ZZNo2TheftGPS_FRAMEWORKS = Foundation CoreLocation
ZZNo2TheftGPS_LIBRARIES = substrate
ZZNo2TheftGPS_CFLAGS = -fobjc-arc -fblocks

include $(THEOS_MAKE_PATH)/tweak.mk
