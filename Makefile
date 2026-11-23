export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:15.0

# Command-line selections are inherited by the preference subproject.
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
export QS_ENVIRONMENT = 2
else ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
export QS_ENVIRONMENT = 1
else ifeq ($(THEOS_PACKAGE_SCHEME),)
export QS_ENVIRONMENT = 0
else
$(error Unsupported THEOS_PACKAGE_SCHEME)
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = QuickSettings
QuickSettings_FILES = Tweak.x QSPreferences.m QSPaneResolver.m
QuickSettings_CFLAGS = -fobjc-arc -DQS_BUILD_ENVIRONMENT=$(QS_ENVIRONMENT)
QuickSettings_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += quicksettingsprefs
include $(THEOS_MAKE_PATH)/aggregate.mk

# Ship the applicable notices with the installed preference bundle.
after-stage::
	cp "$(THEOS_PROJECT_DIR)/LICENSE" "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceBundles/quicksettingsprefs.bundle/QuickSettings-LICENSE.txt"
