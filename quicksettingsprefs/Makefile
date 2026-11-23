ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
ifndef QS_ENVIRONMENT
$(error Build quicksettingsprefs through the aggregate Makefile)
endif
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = quicksettingsprefs
quicksettingsprefs_FILES = QSRootListController.m QSUpdateChecker.m QSDonationController.m ../QSPreferences.m
quicksettingsprefs_FRAMEWORKS = Foundation UIKit
quicksettingsprefs_PRIVATE_FRAMEWORKS = Preferences
quicksettingsprefs_INSTALL_PATH = /Library/PreferenceBundles
quicksettingsprefs_CFLAGS = -fobjc-arc -DQS_BUILD_ENVIRONMENT=$(QS_ENVIRONMENT)
include $(THEOS_MAKE_PATH)/bundle.mk
