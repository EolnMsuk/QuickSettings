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
|-- Tweak.x                                       # Guarded getter/class hooks, payload and preference callback
|-- QSConstants.h                                 # Domain, key, notification, shortcut type and environment labels
|-- QSPrivateInterfaces.h                         # Narrow declarations and runtime ABI checks
|-- QSPreferences.h                               # Shared preference read/commit declarations
|-- QSPreferences.m                               # CFPreferences persistence, rollback and notification
|-- QSPaneResolver.h                              # Immutable available/absent/unresolved results and public adapter
|-- QSPaneResolver.m                              # Native model/providers, cache, observers and URL opening
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
|-- LICENSE                                       # Retained GPL v3 license for adapted source
```
