# QuickSettings project overview

QuickSettings by EolnMsuk adds **App Settings** to Home Screen app menus using an index of real Settings rows, while preserving other quick actions, the live enable switch, update checks, support links, and donation options. The local 1.0.5 candidate uses guarded native row selection and requires a matching visible-controller acknowledgement. Its iOS 16 adapter, unresolved app associations, cross-process transport, and discovery while Settings is suspended or terminated still need device verification; missing index entries are coverage gaps.

Targets **iOS 15.0+** with separate **RootHide**, **rootless**, and **rootful** packages.

```text
QuickSettings/
|-- .gitignore                            # Local files excluded from Git
|-- Makefile                              # Main build and package configuration
|-- control                               # Package information and version
|-- QuickSettings.plist                   # Exact SpringBoard and Settings injection filter
|-- Tweak.x                               # Home Screen menu hooks
|-- QSSettingsBridge.x                    # Settings-only native inventory, selection, lifecycle, and acknowledgement
|-- QSSettingsNativeInterfaces.h          # Narrow ABI-guarded Settings adapter declarations
|-- QSSettingsIPC.h                       # Bounded two-process protocol and navigation build marker
|-- QSSettingsIPC.m                       # Immutable schema validation, synchronized key-level transport, and request identities
|-- QSConstants.h                         # Shared identifiers and defaults
|-- QSPrivateInterfaces.h                 # Guarded private API declarations
|-- QSPreferences.h                       # Preference interface
|-- QSPreferences.m                       # Preference storage and updates
|-- QSPaneResolver.h                      # Settings opening interface
|-- QSPaneResolver.m                      # Expiring requests, cancellation, BOOL bundle-ID launch, and acknowledgement handling
|-- QSSettingsEligibility.h               # Memory-only native-index facade and record checks
|-- QSSettingsEligibility.m               # SpringBoard index cache and proven app-availability invalidation
|-- QSSettingsSupport.h                   # Shared helpers and opt-in diagnostic flag
|-- QSSettingsSupport.m                   # Bundle-ID validation, bounded request diagnostics, and guarded failure feedback
|-- quicksettingsprefs/
|   |-- Makefile                          # Preference bundle build configuration
|   |-- QSRootListController.h            # Preference controller interface
|   |-- QSRootListController.m            # Settings pane, banner spacing, toggle, and footer
|   |-- QSUpdateChecker.h                 # Update checker interface
|   |-- QSUpdateChecker.m                 # Release checks and version comparison
|   |-- QSDonationController.h            # Donation menu interface
|   |-- QSDonationController.m            # Donation links and wallet addresses
|   |-- QSSettingsPresentation.h          # Shared alerts and link handling
|   |-- Resources/
|       |-- Info.plist                    # Bundle information and installed version
|       |-- Root.plist                    # Preference rows and actions
|       |-- icon.png                      # Settings icon
|       |-- icon@2x.png                   # Settings icon at 2x
|       |-- icon@3x.png                   # Settings icon at 3x
|       |-- package-icon.png              # Package manager icon
|       |-- banner-dark.png               # Dark Settings banner
|       |-- banner-light.png              # Light Settings banner
|       |-- banner-sileo-dark.png         # Sileo banner
|       |-- GitHub@2x.png                 # GitHub row icon at 2x
|       |-- GitHub@3x.png                 # GitHub row icon at 3x
|       |-- Reddit@2x.png                 # Reddit row icon at 2x
|       |-- Reddit@3x.png                 # Reddit row icon at 3x
|       |-- ChoySee-LICENSE.txt           # Artwork and source attribution
|-- layout/
|   |-- Library/PreferenceLoader/Preferences/
|       |-- QuickSettings.plist           # Settings pane registration
|-- artwork/
|   |-- Export-Artwork.ps1                # Deterministic artwork export; optional Settings-only banners
|-- scripts/
|   |-- sync-metadata.py                  # Release metadata synchronization
|-- .github/
|   |-- workflows/
|   |   |-- build.yml                     # Package builds and draft releases
|   |-- scripts/
|       |-- verify-package.sh             # Package validation
|-- depiction.json                        # Package manager description and changelog
|-- changelog.md                          # Release history
|-- README.md                             # Installation and usage
|-- ProjectOverview.md                    # Project summary and file list
|-- LICENSE                               # GPL v3 license
```
