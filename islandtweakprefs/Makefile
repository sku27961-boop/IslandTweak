ARCHS = arm64
TARGET = iphone:clang:14.5:14.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = IslandTweakPrefs
IslandTweakPrefs_INSTALL_PATH = /Library/PreferenceBundles
IslandTweakPrefs_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences
	cp Entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/IslandTweakPrefs.plist
