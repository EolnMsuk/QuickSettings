# QuickSettings Changelog

## 1.0.2

- Restores **App Settings** eligibility filtering from the earlier native Settings model; apps without a resolved app-specific destination no longer receive the action.
- Preserves other quick actions and one asynchronous UIKit Settings request, with cancellation when preferences, eligibility, or the selected target change.
- Caches native discovery separately from menu creation and opening requests, with bounded freshness and recovery. Unsupported or unavailable results stay hidden; restored built-in coverage and permission-only pages still require device verification.
- Adds scoped release-metadata synchronization that preserves README exactly.

## 1.0.1

- Replaces the synchronous LaunchServices opener with one asynchronous UIKit Settings request after shortcut handling returns.
- Removes native app/specifier discovery, per-tap full refreshes, and cache warmup; shows **App Settings** on all real application icons, including apps without a dedicated Settings page.
- Uses `App-prefs:<bundle-id>` for app destinations and explicit iOS 15–17 built-in routes, adding Mail, Contacts, Calendar, Camera, Voice Memos, Translate, Measure, Books, Health, Wallet, Shortcuts, Podcasts, News, and Home.
- Moves SpringBoard's committed preference reads to a serial worker, cancels stale pending requests on preference changes or newer selections, and coalesces identical pending requests.

## 1.0.0

- Initial release of QuickSettings by EolnMsuk.
- Adds **App Settings** to eligible Home Screen app menus for direct access to that app's Settings page.
- Hides the action when no app-specific destination is available and preserves other quick actions.
- Adds a live **Enable QuickSettings** switch, matching light/dark artwork, and a version, iOS, and environment footer.
- Includes manual stable-release checks, GitHub and Reddit links, and Venmo or tap-to-copy crypto donations.
- Provides native RootHide, rootless, and rootful build configurations targeting iOS 15.0 and later.
