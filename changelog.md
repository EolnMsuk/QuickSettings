# QuickSettings Changelog

## 1.0.5

- Added an experimental way to find and open app pages using Settings' own app list. This navigation method currently requires iOS 16.
- Refreshes available shortcuts when QuickSettings is enabled, Settings is reopened, or its app list changes.
- Removed the 30-second limit that could make shortcuts disappear.
- Improved handling of repeated taps, choosing another app, turning QuickSettings off, and attempts that time out.
- Added clearer failure messages and optional diagnostics for missing shortcuts or pages that do not open.
- This update still needs device testing, especially for built-in apps. Some shortcuts may remain unavailable, and new or changed apps may need Settings reopened before their shortcuts update.

## 1.0.4

- Restored the 1.0.2 Settings-opening and eligibility flow after the reported 1.0.3 regression.
- Added a focused **App Settings** fallback for Stocks and Voice Memos on iOS 15-17.
- Restored the 30-second discovery snapshot: cold or expired discovery may temporarily hide the action, and stale menu selections may cancel.

## 1.0.3

- Fixed missing **App Settings** shortcuts for built-in apps, including Stocks and Voice Memos.
- Improved opening the correct app page in Settings.
- Made the QuickSettings banner easier to read and added space above the enable switch.
- Removed the repeated banner from the package details page.
- Added a simple guide to choosing the correct download.

## 1.0.2

- Fixed **App Settings** appearing for apps without an app-specific Settings page.
- Preserved other Home Screen quick actions and their order.
- Improved handling of app changes and the enable/disable switch.

## 1.0.1

- Improved Settings opening and responsiveness.
- Added Settings shortcuts for more built-in apps.
- Made **App Settings** available on all application icons.
- Improved handling of repeated taps and app changes.

## 1.0.0

- Initial release of QuickSettings.
- Added **App Settings** for apps with a Settings page while keeping other quick actions intact.
- Added a live **Enable QuickSettings** switch.
- Included light and dark artwork, update checks, support links, and donation options.
- Added RootHide, rootless, and rootful packages for iOS 15.0 and later.
