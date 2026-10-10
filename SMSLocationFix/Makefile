TARGET := iphone:clang:16.5:16.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := N2TSMSLocationFix
N2TSMSLocationFix_FILES := Tweak.m
N2TSMSLocationFix_FRAMEWORKS := Foundation
N2TSMSLocationFix_LIBRARIES := substrate
N2TSMSLocationFix_CFLAGS := -fobjc-arc -fblocks

include $(THEOS_MAKE_PATH)/tweak.mk
