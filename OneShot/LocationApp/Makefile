TARGET := iphone:clang:16.5:16.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
include $(THEOS)/makefiles/common.mk
APPLICATION_NAME := N2TLocation
N2TLocation_FILES := main.m
N2TLocation_FRAMEWORKS := UIKit Foundation CoreLocation
N2TLocation_CFLAGS := -fobjc-arc
N2TLocation_INSTALL_PATH := /Applications
include $(THEOS_MAKE_PATH)/application.mk
