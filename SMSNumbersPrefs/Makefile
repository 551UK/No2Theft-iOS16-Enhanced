TARGET := iphone:clang:16.5:16.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME := N2TSMSNumbers
N2TSMSNumbers_FILES := SMSNumbersController.m
N2TSMSNumbers_RESOURCE_FILES := SMSNumbers.plist
N2TSMSNumbers_INSTALL_PATH := /Library/PreferenceBundles
N2TSMSNumbers_FRAMEWORKS := UIKit Foundation
N2TSMSNumbers_PRIVATE_FRAMEWORKS := Preferences
N2TSMSNumbers_CFLAGS := -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
