TARGET := iphone:clang:16.5:16.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
INSTALL_TARGET_PROCESSES := Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := N2TGPSNotice
N2TGPSNotice_FILES := GPSNotice.m
N2TGPSNotice_FRAMEWORKS := UIKit Foundation
N2TGPSNotice_PRIVATE_FRAMEWORKS := Preferences
N2TGPSNotice_CFLAGS := -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
