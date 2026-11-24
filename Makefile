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
QuickSettings_FILES = Tweak.x QSPreferences.m QSPaneResolver.m QSSettingsEligibility.m QSSettingsSupport.m
# Explicit opt-in for request timings and routine discovery logs.
QS_VERBOSE_DIAGNOSTICS ?= 0
QuickSettings_CFLAGS = -fobjc-arc -DQS_BUILD_ENVIRONMENT=$(QS_ENVIRONMENT) -DQS_VERBOSE_DIAGNOSTICS=$(QS_VERBOSE_DIAGNOSTICS)
QuickSettings_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += quicksettingsprefs
include $(THEOS_MAKE_PATH)/aggregate.mk

# Ship the applicable notices with the installed preference bundle.
# Theos applies the package install prefix during packaging, after staging.
after-stage::
	cp "$(THEOS_PROJECT_DIR)/LICENSE" "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/quicksettingsprefs.bundle/QuickSettings-LICENSE.txt"
