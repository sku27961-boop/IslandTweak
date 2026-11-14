export THEOS_DEVICE_IP = # put your iPhone's IP here if using SSH install, otherwise leave blank
ARCHS = armv7 arm64
TARGET = iphone:clang:15.0:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = IslandTweak
IslandTweak_FILES = Tweak.xm
IslandTweak_CFLAGS = -fobjc-arc
IslandTweak_FRAMEWORKS = UIKit CoreGraphics QuartzCore AVFoundation CoreTelephony MediaPlayer

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
