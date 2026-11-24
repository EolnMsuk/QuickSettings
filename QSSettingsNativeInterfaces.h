// Narrow 16.x adapter, from the 15.0/16.5 headers linked in plan.md.
// Declarations are possibilities. Every private message/hook is checked at runtime.
#pragma once
#import "QSPrivateInterfaces.h"

@protocol QSSettingsRoot <NSObject>
- (id)rootListController;
@end
@protocol QSSettingsList <NSObject>
- (id)specifiers;
- (id)_thirdPartySpecifiers;
- (id)table;
- (id)indexPathForSpecifier:(id)specifier;
- (id)specifierAtIndexPath:(id)path;
- (id)tableView:(id)table willSelectRowAtIndexPath:(id)path;
- (void)tableView:(id)table didSelectRowAtIndexPath:(id)path;
@end
@protocol QSSettingsSpecifier <NSObject>
- (id)identifier;
- (NSInteger)cellType;
- (id)propertyForKey:(id)key;
- (id)userInfo;
- (Class)detailControllerClass;
- (SEL)buttonAction;
- (SEL)confirmationAction;
- (SEL)legacyAction;
- (BOOL)hasValidSetter;
@end
@protocol QSSettingsPage <NSObject>
- (id)specifier;
@end
