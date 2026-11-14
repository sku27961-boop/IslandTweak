ARCHS = arm64
TARGET = iphone:clang:15.6:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = IslandTweak
IslandTweak_FILES = Tweak.xm
IslandTweak_CFLAGS = -fobjc-arc
IslandTweak_FRAMEWORKS = UIKit CoreGraphics QuartzCore AVFoundation CoreTelephony MediaPlayer

include $(THEOS_MAKE_PATH)/tweak.mk
