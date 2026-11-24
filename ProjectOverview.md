# QuickSettings project overview

## Version 1.0.2 restoration

The earlier eligibility implementation was recovered from local edit history and adapted into `QSSettingsEligibility.h/.m`; the Downloads archive was identical to 1.0.1. [The revised plan](plan.md#restoration-evidence-recovered-locally) records the source provenance and supersedes its former private-header research prerequisite. No package build or device validation was performed. The target remains iOS 15.0+, with arm64/arm64e and the existing RootHide, rootless, and rootful scheme/environment mappings. These targets do not establish compatibility of the restored private model on every OS.

`Tweak.x` removes duplicates of only its own type, validates the application icon, then adds one namespaced **App Settings** item only while enabled and the target has current eligible native evidence. Disabled, ineligible, or unknown results remove only owned actions, preserving other actions and their order. Nil, empty, invalid-icon, and non-array stock results retain their existing handling. Menu creation performs memory lookups and coalesces asynchronous discovery; it never loads Preferences.framework or enumerates apps/specifiers. The activation hook consumes owned actions once, including stale/invalid/disabled ones, and passes only `userInfo[QSTargetBundleKey]` to the coordinator. Its activation bundle argument may identify Settings and is never the target source.

`QSPaneResolver` coordinates preferences, routing, and a single asynchronous request. Its serial worker performs startup/notification reads and one committed read per accepted activation. The memory monitor covers only state; CFPreferences and UIKit calls execute outside it. Each preference notification increments the generation and disables opening until its worker read completes. Eligibility enablement publications also carry that preference generation, so a delayed old read cannot re-enable discovery. Requests capture a separate eligibility generation and check it at acceptance, worker validation, and immediately before UIKit submission. New targets replace older pending requests; identical current requests coalesce. A stale owned tap cancels its request without waiting for discovery to launch later. Old cancellation/completion paths clear only their own request. The synchronous sensitive-URL opener and per-tap full scans have not been restored.

The worker constructs an internal URL from a copied, validated identifier. The main queue rechecks the pending request, generation, and in-memory enablement, then calls `UIApplication openURL:options:completionHandler:` once with empty options after the shortcut hook returns. Disablement can invalidate queued work; a request already submitted to iOS cannot be recalled. Rejections end the request without a fallback launch or retry. `QSPreferences.m` retains its existing synchronized commit, rollback on failure, and notification-after-success behavior. Settings' preference controller continues to use the shared persistence functions directly; SpringBoard reads use the worker.

## Restored eligibility and limits

The isolated adapter reuses the old `PSSystemPolicyManager` class methods `thirdPartyApplications` and `specifiersForThirdPartyApps:`. It preserves the native argument container, checks every used private ABI, bounds containers to 10,000 entries, maps native `PSThirdPartyApp` proxies by exact `applicationIdentifier`, and matches `PSSpecifier` PSLinkCell identifiers. Installation alone never establishes eligibility. An internally consistent nonempty app/specifier model with at least one matched destination can establish negatives for represented third-party apps; empty, group-only, malformed, unsupported, or incomplete data remains unknown. Duplicate/malformed target rows cannot be rescued by a built-in provider. Exceptions are contained at the native-adapter boundary. No Settings.bundle, URL-handler check, or legacy route-table hit is used as eligibility evidence. The policy model is intended to include OS-supplied controls, but permission-only coverage remains a device check.

The eleven recovered built-in adapters query native `+preferencesURL` providers for Safari, Phone, Messages, FaceTime, Maps, Music, Notes, Reminders, Compass, Photos, and App Store. They require an installed, non-placeholder/non-restricted target where the optional predicates exist, a compatible provider, and a returned URL matching that app/root. Definitive native negatives are not overwritten. This restores the earlier provider behavior; a returned provider URL is not device proof that restrictions expose that destination. Other built-ins can qualify through a matching native specifier. Mail, Contacts, Calendar, Camera, Voice Memos, Translate, Measure, Books, Health, Wallet, Shortcuts, Podcasts, News, Home, and other unmapped built-ins remain unknown/hidden if the model does not resolve them. A complete third-party result is never treated as a complete built-in inventory. These are coverage limits, not verified absence of those apps' Settings pages.

Discovery runs only on a separate serial queue, away from preference/open validation. No Preferences controller is created or retained. The inherited non-controller model's background-thread affinity, readiness, SpringBoard access, and semantics are unverified; runtime signature checks cannot establish them. Missing classes/ABIs and failed framework loads fail closed and can recover later. No Settings-process injection, IPC helper, invented selectors, or new policy-notification names were added.

Snapshots contain only copied identifiers and numeric states in memory. Enablement warms asynchronously. Both positive and negative results expire after 30 seconds; the next lookup immediately retires an expired snapshot and coalesces discovery for a subsequent menu. Unknown results hide the action. An incomplete attempt receives at most two automatic retries, spaced at least five seconds from attempt starts; further recovery is driven by a later expired lookup, preference change, or app event. There is no perpetual polling timer or full scan per tap. Only one refresh is queued/running; changes during it request one coalesced follow-up, and a generation captured before scheduling prevents stale publication. No native app inventory is persisted or logged.

The restored guarded workspace observer uses `applicationsDidInstall:`, `applicationsDidUninstall:`, and `applicationStateDidChange:`. Each callback immediately retires positive and negative data and invalidates queued opens by generation. Callback delivery for update/offload and policy changes is unverified; bounded freshness covers missed events on subsequent use. Preference changes retire eligibility immediately. No observer can retract a UIKit request already submitted to iOS.

## Routes and evidence

The explicit table contains the eleven original built-in pairings and the ten gaps listed in [plan.md](plan.md#implementation-steps), plus Shortcuts (`SHORTCUTS`), Podcasts (`com.apple.podcasts`), News (`NEWS`), and Home (`HOMEKIT`). It applies only on iOS 15–17. Exact bundle IDs matter, including capitalization. All other valid targets, including targets on iOS 18+, use `App-prefs:<bundle-id>` with the identifier encoded as one component. This is a routing choice, not an eligibility check or an assertion that every app/OS has a compatible page.

Reviewed November 23, 2026: the [Home Screen Quick Actions source](https://raw.githubusercontent.com/tomaszpoliszuk/HomeScreenQuickActions/master/HomeScreenQuickActions.xm) uses the generic app URL with UIKit's completion-based opener; [Apple's API documentation](https://developer.apple.com/documentation/uikit/uiapplication/open(_:options:completionhandler:)) and the supplied iOS 16.5 `UIApplication.h` describe asynchronous opening and completion. They do not guarantee private Settings destinations. Built-in tokens come from the empirical [Settings URL catalog](https://raw.githubusercontent.com/FifiTheBulldog/ios-settings-urls/master/settings-urls.md), whose [methodology](https://raw.githubusercontent.com/FifiTheBulldog/ios-settings-urls/master/README.md) describes incomplete testing. The additional app IDs are supported by [Apple's deployment bundle-ID list](https://support.apple.com/en-lamr/guide/deployment/depece748c41/web). These source checks do not establish iOS 16.1.1 cold/warm behavior or rootful compatibility.

## Request diagnostics and device follow-up

`[QuickSettings]` request traces record a request ID, target, route kind, and monotonic elapsed milliseconds at activation, worker start, validation/route completion, immediately before and after the opener call, and UIKit completion. `route=pending` precedes route construction; validation identifies `app` or `builtin-root`. `opener-return call=...ms` isolates time spent invoking UIKit. Completion reports `open-accepted (destination-unverified)` or rejection. Cancelled requests may stop before later stages. Only the first 24 distinct requests in each 60-second trace window receive these lines, independently of the existing per-code diagnostic throttle; no timer or launch delay is involved. Duplicate pending requests do not consume another trace. No unrelated app inventory or preference contents are logged.

Use the [manual acceptance checklist](plan.md#manual-device-acceptance-checklist) on each reported environment. Cold and warm GitHub/Messages destinations and SpringBoard responsiveness remain unverified. UIKit acceptance alone is insufficient. If acceptance is prompt and the UI stays responsive but a cold launch still lands on Settings home, follow [the conditional readiness investigation](plan.md#if-cold-start-navigation-still-fails). Any Settings helper requires verified lifecycle/list-readiness evidence, preserved target delivery, bounded request/acknowledgement cleanup, process-specific initialization, and coordinated changes to both the injection filter and `.github/scripts/verify-package.sh`. The first implementation retains SpringBoard-only injection and its exact package assertion.

The restoration's local checks passed: scoped metadata consistency, version/current-notes extraction, JSON/plist versions and complete history, unchanged historical changelog bytes, depiction schema/scope, the three workflow edits, and unchanged README bytes/SHA-256. A read-only fault-injection check confirmed the scoped synchronizer never accesses README and still rejects bundle/depiction version drift. All restored private selectors/classes and eleven provider associations were compared with the recovered source. Source review covered duplicate cleanup, stale/unknown taps, refresh invalidation, disable/re-enable, request coalescing/supersession, and old-completion cleanup; those interleavings were not executed on iOS. The environment mappings, minimum OS, filter/verifier, preference persistence, and installed-version reader were compared with the initial files. No package build, workflow execution, installation, remote operation, or device test was performed; compilation and runtime behavior remain unverified.

## CI and draft release

`control`, both preference-bundle version fields, and current depiction/release history are synchronized at 1.0.2. `QSRootListController.m` still reads `CFBundleShortVersionString` from its own bundle. Use `python scripts/sync-metadata.py --skip-readme` to synchronize and `--check --skip-readme` to validate all metadata except README; all three local workflow checks use that scope. Extraction modes still print only the current version/notes. README is deliberately frozen at its older release/download block; the default full `--check` consequently reports README drift. The workflow was edited locally and was not run.

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
|-- QSSettingsEligibility.h                       # Cached classification and eligibility-generation interface
|-- QSSettingsEligibility.m                       # Restored native adapter, separate discovery queue and bounded recovery
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
