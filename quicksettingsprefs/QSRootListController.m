// UI adapted from HaptiX by EolnMsuk; GPL-3.0, see ../LICENSE.
// Other actions include ChoySee adaptations; see Resources/ChoySee-LICENSE.txt.
#import "QSRootListController.h"
#import "QSUpdateChecker.h"
#import "QSDonationController.h"
#import "QSSettingsPresentation.h"
#import "../QSConstants.h"
#import "../QSPreferences.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#include <math.h>

@interface QSBlueButtonCell : PSTableCell
@end
@implementation QSBlueButtonCell
- (void)layoutSubviews {
    [super layoutSubviews];
    self.textLabel.textColor = UIColor.systemBlueColor;
    self.textLabel.highlightedTextColor = UIColor.systemBlueColor;
}
@end
@interface QSGreenButtonCell : PSTableCell
@end
@implementation QSGreenButtonCell
- (void)layoutSubviews {
    [super layoutSubviews];
    self.textLabel.textColor = UIColor.systemGreenColor;
    self.textLabel.highlightedTextColor = UIColor.systemGreenColor;
}
@end

@interface QSRootListController ()
@property (nonatomic, strong) UIImageView *bannerView;
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic) BOOL updateCheckInProgress;
@property (nonatomic) BOOL showUpdateResult;
@property (nonatomic) BOOL preferenceWriteInProgress;
@end

static NSBundle *QSPrefsBundle(void) {
    return [NSBundle bundleForClass:QSRootListController.class];
}
static NSString *QSInstalledVersion(void) {
    return [QSPrefsBundle() objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
}
static UIImage *QSRowSymbol(NSString *name, UIColor *color, UITraitCollection *traits) {
    UIImage *symbol = [UIImage systemImageNamed:name withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular]];
    if (!symbol) return nil;
    symbol = [symbol imageWithTintColor:[color resolvedColorWithTraitCollection:traits]
                         renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(29, 29)];
    return [[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGSize size = symbol.size;
        CGFloat scale = MIN(25 / size.width, 25 / size.height);
        size = CGSizeMake(size.width * scale, size.height * scale);
        [symbol drawInRect:CGRectMake((29 - size.width) / 2, (29 - size.height) / 2, size.width, size.height)];
    }] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

@implementation QSRootListController
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self bundle:QSPrefsBundle()];
        for (PSSpecifier *row in _specifiers) {
            if ([@[@"Updates", @"GitHub", @"Reddit"] containsObject:row.identifier]) {
                [row setProperty:QSBlueButtonCell.class forKey:@"cellClass"];
            } else if ([row.identifier isEqualToString:@"Donate"]) {
                [row setProperty:QSGreenButtonCell.class forKey:@"cellClass"];
            }
            if ([row.identifier isEqualToString:@"Updates"]) {
                [row setProperty:QSRowSymbol(@"arrow.triangle.2.circlepath", UIColor.systemBlueColor, self.traitCollection) forKey:@"iconImage"];
                [row setProperty:@(!self.updateCheckInProgress) forKey:@"enabled"];
            } else if ([row.identifier isEqualToString:@"Donate"]) {
                [row setProperty:QSRowSymbol(@"dollarsign.circle.fill", UIColor.systemGreenColor, self.traitCollection) forKey:@"iconImage"];
            }
        }
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return @([specifier.identifier isEqualToString:@"EnableQuickSettings"] && QSReadEnabled());
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    if (![specifier.identifier isEqualToString:@"EnableQuickSettings"]
        || ![value isKindOfClass:NSNumber.class] || self.preferenceWriteInProgress) return;
    self.preferenceWriteInProgress = YES;
    BOOL success = QSWriteEnabled([value boolValue]);
    self.preferenceWriteInProgress = NO;
    [self reloadSpecifier:specifier]; // Reflect committed state, including persistence failure.
    if (!success) QSShowMessage(self, @"Unable to Save", @"The previous QuickSettings preference was restored. Try again.");
    // Hooks stay installed: no respring or uncommitted preference transaction.
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"QuickSettings";
    self.bannerView = [UIImageView new];
    self.bannerView.contentMode = UIViewContentModeScaleAspectFit;
    self.bannerView.isAccessibilityElement = YES;
    self.bannerView.accessibilityLabel = @"QuickSettings by EolnMsuk";
    [self updateBanner];

    self.footerLabel = [UILabel new];
    self.footerLabel.text = [NSString stringWithFormat:@"QuickSettings v%@ (iOS %@ %@)",
        QSInstalledVersion() ?: @"?", UIDevice.currentDevice.systemVersion, QSInstalledEnvironment()];
    self.footerLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.footerLabel.adjustsFontForContentSizeCategory = YES;
    self.footerLabel.textColor = UIColor.secondaryLabelColor;
    self.footerLabel.textAlignment = NSTextAlignmentCenter;
    self.footerLabel.numberOfLines = 0;
    UIView *footer = [UIView new];
    [footer addSubview:self.footerLabel];
    self.table.tableFooterView = footer; // Independent of artwork success.
}
- (void)updateBanner {
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    NSString *path = [QSPrefsBundle() pathForResource:dark ? @"banner-dark" : @"banner-light" ofType:@"png"];
    self.bannerView.image = path ? [UIImage imageWithContentsOfFile:path] : nil;
    self.table.tableHeaderView = self.bannerView.image ? self.bannerView : nil;
    [self.viewIfLoaded setNeedsLayout];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.table.bounds.size.width;
    if (width <= 0) return;
    UIImage *image = self.bannerView.image;
    if (image && image.size.width > 0) {
        CGFloat height = floor(width * image.size.height / image.size.width);
        CGRect frame = CGRectMake(0, 0, width, height);
        if (!CGRectEqualToRect(self.bannerView.frame, frame)) {
            self.bannerView.frame = frame;
            self.table.tableHeaderView = self.bannerView;
        }
    }
    CGSize size = [self.footerLabel sizeThatFits:CGSizeMake(MAX(1, width - 32), CGFLOAT_MAX)];
    CGFloat height = MAX(52, ceil(size.height) + 32);
    UIView *footer = self.table.tableFooterView;
    self.footerLabel.frame = CGRectMake(16, 16, width - 32, ceil(size.height));
    CGRect frame = CGRectMake(0, 0, width, height);
    if (!CGRectEqualToRect(footer.frame, frame)) {
        footer.frame = frame;
        self.table.tableFooterView = footer;
    }
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (!self.isViewLoaded) return;
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) {
        [self updateBanner];
        for (NSString *identifier in @[@"Updates", @"Donate"]) {
            PSSpecifier *row = [self specifierForID:identifier];
            BOOL donate = [identifier isEqualToString:@"Donate"];
            [row setProperty:QSRowSymbol(donate ? @"dollarsign.circle.fill" : @"arrow.triangle.2.circlepath",
                donate ? UIColor.systemGreenColor : UIColor.systemBlueColor, self.traitCollection) forKey:@"iconImage"];
            if (row && self.isViewLoaded) [self reloadSpecifier:row];
        }
    }
    [self.viewIfLoaded setNeedsLayout];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    PSSpecifier *row = [self specifierForID:@"EnableQuickSettings"];
    if (row) [self reloadSpecifier:row];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.showUpdateResult = NO;
}
- (void)setUpdateCheckInProgress:(BOOL)inProgress {
    _updateCheckInProgress = inProgress;
    PSSpecifier *row = [self specifierForID:@"Updates"];
    [row setProperty:@(!inProgress) forKey:@"enabled"];
    if (row && self.isViewLoaded) [self reloadSpecifier:row];
}
- (void)checkForUpdates {
    if (self.updateCheckInProgress || !QSCanPresent(self)) return;
    self.updateCheckInProgress = YES;
    self.showUpdateResult = YES;
    NSString *version = QSInstalledVersion();
    __weak QSRootListController *weakSelf = self;
    [QSUpdateChecker checkInstalledVersion:version completion:^(NSString *tag, NSURL *url, NSString *failure) {
        QSRootListController *controller = weakSelf;
        controller.updateCheckInProgress = NO;
        if (controller.showUpdateResult && QSCanPresent(controller)) {
            NSString *title = failure ? @"Update Check Failed" : (url ? @"Update Available" : @"Up to Date");
            NSString *message = failure ?: [NSString stringWithFormat:
                @"Installed version %@\nLatest stable release %@", version, tag];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
                preferredStyle:UIAlertControllerStyleAlert];
            __weak UIAlertController *weakAlert = alert;
            if (url) {
                [alert addAction:[UIAlertAction actionWithTitle:@"View Release" style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        QSAfterAlertDismissal(weakAlert, ^{ QSOpenExternalURL(weakSelf, url); });
                    }]];
            }
            [alert addAction:[UIAlertAction actionWithTitle:url ? @"Cancel" : @"OK" style:UIAlertActionStyleCancel handler:nil]];
            [controller presentViewController:alert animated:YES completion:nil];
        }
        controller.showUpdateResult = NO;
    }];
}
- (void)openGitHub { QSOpenExternalURL(self, [NSURL URLWithString:@"https://github.com/EolnMsuk/QuickSettings/"]); }
- (void)openReddit { QSOpenExternalURL(self, [NSURL URLWithString:@"https://www.reddit.com/user/EolnMsuk4334/"]); }
- (void)presentDonationMenu {
    PSSpecifier *row = [self specifierForID:@"Donate"];
    NSIndexPath *path = row ? [self indexPathForSpecifier:row] : nil;
    QSPresentDonationMenu(self, path ? [self.table cellForRowAtIndexPath:path] : nil);
}
@end
