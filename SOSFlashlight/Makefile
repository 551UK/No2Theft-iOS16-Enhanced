TARGET := iphone:clang:16.5:16.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
INSTALL_TARGET_PROCESSES := SpringBoard
include $(THEOS)/makefiles/common.mk

TWEAK_NAME := N2TSOSFlashlight
N2TSOSFlashlight_FILES := Tweak.m
N2TSOSFlashlight_FRAMEWORKS := Foundation AVFoundation CoreFoundation
N2TSOSFlashlight_LIBRARIES := substrate
N2TSOSFlashlight_CFLAGS := -fobjc-arc -fblocks
include $(THEOS_MAKE_PATH)/tweak.mk
