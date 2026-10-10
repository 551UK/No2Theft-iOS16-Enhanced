TARGET := iphone:clang:16.5:16.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
include $(THEOS)/makefiles/common.mk

TWEAK_NAME := ZZNo2TheftOnDemandGPS
ZZNo2TheftOnDemandGPS_FILES := EmailHook.m
ZZNo2TheftOnDemandGPS_FRAMEWORKS := Foundation
ZZNo2TheftOnDemandGPS_LIBRARIES := substrate
ZZNo2TheftOnDemandGPS_CFLAGS := -fobjc-arc
include $(THEOS_MAKE_PATH)/tweak.mk
