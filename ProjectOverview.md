# QuickSettings project overview

## Version 1.0.1 implementation

The local source is ready for the user's manual build and device testing. No package build or device validation was performed. The target remains iOS 15.0+, with arm64/arm64e and the existing RootHide, rootless, and rootful scheme/environment mappings.

`Tweak.x` adds one namespaced **App Settings** item to real application icons when enabled, removes duplicates of only its own type, and preserves the relative order of stock/other actions. Menu creation uses icon identity and in-memory enablement. It does not load Preferences.framework or enumerate apps/specifiers. The activation hook consumes owned actions once, including invalid or disabled ones, and passes only `userInfo[QSTargetBundleKey]` to the coordinator. Its activation bundle argument may identify Settings and is never the target source.

`QSPaneResolver` now coordinates preferences, routing, and a single asynchronous request. A serial worker performs startup/notification reads and one committed read per activation. The memory monitor covers only state; CFPreferences and UIKit calls execute outside it. Each preference notification increments the generation and disables opening until its worker read completes. Results from older generations cannot republish enablement or submit a pending request. New targets replace older pending requests; identical pending targets coalesce until completion. An old completion clears only its own request. There is no app-model cache, refresh timer, LaunchServices observer, installed-app enumeration, or synchronous sensitive-URL opener.

The worker constructs an internal URL from a copied, validated identifier. The main queue rechecks the pending request, generation, and in-memory enablement, then calls `UIApplication openURL:options:completionHandler:` once with empty options after the shortcut hook returns. Disablement can invalidate queued work; a request already submitted to iOS cannot be recalled. Rejections end the request without a fallback launch or retry. `QSPreferences.m` retains its existing synchronized commit, rollback on failure, and notification-after-success behavior. Settings' preference controller continues to use the shared persistence functions directly; SpringBoard reads use the worker.

## Routes and evidence

The explicit table contains the eleven original built-in pairings and the ten gaps listed in [plan.md](plan.md#implementation-steps), plus Shortcuts (`SHORTCUTS`), Podcasts (`com.apple.podcasts`), News (`NEWS`), and Home (`HOMEKIT`). It applies only on iOS 15–17. Exact bundle IDs matter, including capitalization. All other valid targets, including targets on iOS 18+, use `App-prefs:<bundle-id>` with the identifier encoded as one component. This is a routing choice, not an eligibility check or an assertion that every app/OS has a compatible page.

Reviewed November 23, 2026: the [Home Screen Quick Actions source](https://raw.githubusercontent.com/tomaszpoliszuk/HomeScreenQuickActions/master/HomeScreenQuickActions.xm) uses the generic app URL with UIKit's completion-based opener; [Apple's API documentation](https://developer.apple.com/documentation/uikit/uiapplication/open(_:options:completionhandler:)) and the supplied iOS 16.5 `UIApplication.h` describe asynchronous opening and completion. They do not guarantee private Settings destinations. Built-in tokens come from the empirical [Settings URL catalog](https://raw.githubusercontent.com/FifiTheBulldog/ios-settings-urls/master/settings-urls.md), whose [methodology](https://raw.githubusercontent.com/FifiTheBulldog/ios-settings-urls/master/README.md) describes incomplete testing. The additional app IDs are supported by [Apple's deployment bundle-ID list](https://support.apple.com/en-lamr/guide/deployment/depece748c41/web). These source checks do not establish iOS 16.1.1 cold/warm behavior or rootful compatibility.

## Request diagnostics and device follow-up

`[QuickSettings]` request traces record a request ID, target, route kind, and monotonic elapsed milliseconds at activation, worker start, validation/route completion, immediately before and after the opener call, and UIKit completion. `route=pending` precedes route construction; validation identifies `app` or `builtin-root`. `opener-return call=...ms` isolates time spent invoking UIKit. Completion reports `open-accepted (destination-unverified)` or rejection. Cancelled requests may stop before later stages. Only the first 24 distinct requests in each 60-second trace window receive these lines, independently of the existing per-code diagnostic throttle; no timer or launch delay is involved. Duplicate pending requests do not consume another trace. No unrelated app inventory or preference contents are logged.

Use the [manual acceptance checklist](plan.md#manual-device-acceptance-checklist) on each reported environment. Cold and warm GitHub/Messages destinations and SpringBoard responsiveness remain unverified. UIKit acceptance alone is insufficient. If acceptance is prompt and the UI stays responsive but a cold launch still lands on Settings home, follow [the conditional readiness investigation](plan.md#if-cold-start-navigation-still-fails). Any Settings helper requires verified lifecycle/list-readiness evidence, preserved target delivery, bounded request/acknowledgement cleanup, process-specific initialization, and coordinated changes to both the injection filter and `.github/scripts/verify-package.sh`. The first implementation retains SpringBoard-only injection and its exact package assertion.

## CI and draft release

| Variant | Toolchain / scheme | Debian architecture | Environment define |
| --- | --- | --- | --- |
| roothide | Native RootHide Theos / roothide | iphoneos-arm64e | 2 |
| rootless | Stock Theos / rootless | iphoneos-arm64 | 1 |
| rootful | Stock Theos / unset | iphoneos-arm | 0 |

## Required file inventory

This tree describes the actual required deliverables; each file has its role beside it.

```text
QuickSettings/
|-- .gitignore                                    # Excludes package/build and interpreter outputs
|-- Makefile                                      # Aggregate build, environment mapping, installed GPL notice
|-- control                                       # Canonical version, package ID, dependencies, asset URLs
|-- QuickSettings.plist                           # SpringBoard-only injection filter
|-- Tweak.x                                       # Guarded getter/class hooks, namespaced payload and queued preference reload
|-- QSConstants.h                                 # Domain, key, notification, shortcut type and environment labels
|-- QSPrivateInterfaces.h                         # Narrow declarations and runtime ABI checks
|-- QSPreferences.h                               # Shared preference read/commit declarations
|-- QSPreferences.m                               # CFPreferences persistence, rollback and notification
|-- QSPaneResolver.h                              # In-memory enablement, queued reload and app-opening interface
|-- QSPaneResolver.m                              # Explicit routes, serial validation, request cancellation and UIKit opener
|-- quicksettingsprefs/
|   |-- Makefile                                  # iOS 15+ preference bundle with shared environment definition
|   |-- QSRootListController.h                    # Preference controller declaration
|   |-- QSRootListController.m                    # Live toggle, Other rows, banner, footer and presentation
|   |-- QSUpdateChecker.h                         # Asynchronous manual-check completion interface
|   |-- QSUpdateChecker.m                         # Bounded GitHub request, stable validation and numeric comparison
|   |-- QSDonationController.h                    # Donation-sheet entry point
|   |-- QSDonationController.m                    # Browser, eight wallets, copy feedback and iPad handling
|   |-- QSSettingsPresentation.h                  # Foreground checks, alert dismissal and link failure UI
|   |-- Resources/
|       |-- Info.plist                            # Bundle identity, minimum OS and synchronized installed version
|       |-- Root.plist                            # Enable switch and ordered Other action specifiers
|       |-- icon.png                              # Matching 29-pixel Settings icon
|       |-- icon@2x.png                           # Matching 58-pixel Settings icon
|       |-- icon@3x.png                           # Matching 87-pixel Settings icon
|       |-- package-icon.png                      # Original 1024-square Sileo/package icon
|       |-- banner-dark.png                       # Original 1600 x 600 dark Settings/README banner
|       |-- banner-light.png                      # Matching 1600 x 600 light Settings/README banner
|       |-- banner-sileo-dark.png                 # Padded dark export with lower visual center
|       |-- GitHub@2x.png                         # Attributed reference GitHub row artwork, 2x
|       |-- GitHub@3x.png                         # Attributed reference GitHub row artwork, 3x
|       |-- Reddit@2x.png                         # Attributed reference Reddit row artwork, 2x
|       |-- Reddit@3x.png                         # Attributed reference Reddit row artwork, 3x
|       |-- ChoySee-LICENSE.txt                    # Retained MIT source/artwork notice
|-- layout/
|   |-- Library/PreferenceLoader/Preferences/
|       |-- QuickSettings.plist                   # Pane registration, controller and icon
|-- artwork/
|   |-- Export-Artwork.ps1                        # Editable vector/drawing source and local PNG exporter
|-- scripts/
|   |-- sync-metadata.py                          # Standard-library sync/check/current-release extraction
|-- .github/
|   |-- workflows/
|   |   |-- build.yml                             # Manual metadata/build matrix and guarded draft release
|   |-- scripts/
|       |-- verify-package.sh                     # CI-only package and Mach-O inspection
|-- depiction.json                                # Sileo Details/Changelog/Information tabs and real asset paths
|-- changelog.md                                  # Authoritative complete end-user release history
|-- README.md                                     # User installation, environment choice, usage and support
|-- ProjectOverview.md                            # Project overview (this file)
|-- plan.md                                       # Planning evidence, manual acceptance checks and conditional follow-up
|-- handoff-prompt.md                              # Original implementation-session handoff from planning
|-- LICENSE                                       # Retained GPL v3 license for adapted source
```
