TARGET := iphone:clang:16.5:16.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := N2TRemoteAlarm
N2TRemoteAlarm_FILES := Tweak.m
N2TRemoteAlarm_FRAMEWORKS := Foundation CoreFoundation
N2TRemoteAlarm_LIBRARIES := substrate
N2TRemoteAlarm_CFLAGS := -fobjc-arc -fblocks

include $(THEOS_MAKE_PATH)/tweak.mk
