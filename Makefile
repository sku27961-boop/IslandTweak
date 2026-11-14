ARCHS = arm64
TARGET = iphone:clang:15.6:14.0

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += islandtweak islandtweakprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
