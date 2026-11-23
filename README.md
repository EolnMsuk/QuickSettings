# QuickSettings

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="quicksettingsprefs/Resources/banner-dark.png">
  <img src="quicksettingsprefs/Resources/banner-light.png" alt="QuickSettings by EolnMsuk — App settings. One press away." width="100%">
</picture>

**QuickSettings** by **EolnMsuk** adds **App Settings** to eligible Home Screen application menus. Long-press an app icon to open that app's own Settings page. Other stock and tweak quick actions keep their order.

## Install

Requires a jailbreak with a compatible hooking framework and PreferenceLoader, targeting **iOS 15.0 or later**. Select the package for your installed jailbreak environment. The native RootHide package is built with the RootHide Theos fork and installs directly; it does not need rootless conversion.

<!-- release-assets:start -->
Current version: **1.0.0**.

| Download | Environment | Debian architecture |
| --- | --- | --- |
| `com.eolnmsuk.QuickSettings_1.0.0_roothide.deb` | RootHide | `iphoneos-arm64e` |
| `com.eolnmsuk.QuickSettings_1.0.0_rootless.deb` | rootless | `iphoneos-arm64` |
| `com.eolnmsuk.QuickSettings_1.0.0_rootful.deb` | rootful | `iphoneos-arm` |
<!-- release-assets:end -->

Download from the [published releases](https://github.com/EolnMsuk/QuickSettings/releases). Open the matching `.deb` in your jailbreak package manager, such as Sileo, and follow its installation instructions. Let the package manager perform any initial process reload it requires to load a newly installed tweak.

This is a source-derived implementation baseline. The private interfaces are recorded on iOS 15.5, 16, and 17 (some shortcut/navigation declarations on 15.3.1). A 15.0 deployment target is not proof that every iOS release or jailbreak works. Package builds, installation, device behavior, and Sileo rendering have not yet been verified. Later Settings redesigns need device checks and may need an adapter update.

## Enable and use

1. Open **Settings > QuickSettings** and turn on **Enable QuickSettings**. The initial value is **off**.
2. Allow the native app-page cache to warm, then long-press a Home Screen app, including an app in the Dock or a folder.
3. Select **App Settings** to open that application's page.

Enable and disable changes apply live to newly opened menus; changing this switch requires no respring. An already visible action checks the committed preference again before opening.

The shortcut appears only when an installed app has a validated dedicated page. Apps without a page, removed/offloaded apps, web clips, folders themselves, and unresolved destinations receive no action. Permission-only pages qualify when the native Settings app model exposes them. A cold or unresolved lookup can temporarily hide the action while the model refreshes; retry the menu after a few seconds. App changes trigger refresh when the system observer is available, with a 30-second freshness interval as well.

The native-provider adapter covers Safari, Phone, Messages, FaceTime, Maps, Music, Notes, Reminders, Compass, Photos, and App Store where the installed OS exposes the corresponding provider and valid URL. More built-in apps can qualify through the native app model. Dedicated historical adapters for Mail, Contacts, Calendar, Camera, Voice Memos, Translate, Measure, Books, Health, and Wallet are not implemented; those panes remain hidden if the model cannot resolve them. Unmapped icons receive no unrelated Settings shortcut.

## Preferences and updates

The pane follows light/dark mode and shows the installed version, current iOS, and exactly **RootHide**, **rootless**, or **rootful** for the installed package.

**Updates** manually checks GitHub's latest published stable QuickSettings release. A newer version offers **View Release**, where you choose, download, and install the right package. It never downloads or installs an update automatically. Drafts and prereleases are excluded. Offline, rate-limited, missing-release, and invalid-response cases show feedback.

**GitHub**, **Reddit**, and **Donate** provide the developer's links. Donate offers **Venmo**, **Crypto**, and **Cancel**. Venmo opens in the default browser when the OS's browser-opening interface is available. Crypto lists eight coin/network/address records; tap a row to copy its address and receive **Copied** feedback.

## Support and validation

Report issues at [GitHub](https://github.com/EolnMsuk/QuickSettings/issues) or contact [EolnMsuk on Reddit](https://www.reddit.com/user/EolnMsuk4334/). Include the installed version, iOS version, environment, app bundle identifier, and whether the Settings app was closed or already open. For missing actions, include bounded `[QuickSettings]` console diagnostics, especially model app/specifier types, counts, and identifier mismatch messages. Avoid sharing unrelated device logs.

Before publication, run the manual workflow and the CI/device checklist in [ProjectOverview.md](ProjectOverview.md). In particular, confirm custom Settings.bundle apps, permission-only panes, an app with no pane, native built-in routes, quick-action coexistence, and behavior while Settings is already on another page.

[Source](https://github.com/EolnMsuk/QuickSettings/) · [Releases](https://github.com/EolnMsuk/QuickSettings/releases) · [Reddit](https://www.reddit.com/user/EolnMsuk4334/) · [Venmo](https://venmo.com/EolnMsuk/)

## Maintaining releases

Edit the version in `control` and add its notes as the first `## <version>` section in `changelog.md`. Run `python3 scripts/sync-metadata.py`, then `python3 scripts/sync-metadata.py --check`. This updates bundle versions, depiction history/version, and the package table above. `--release-notes` prints only the current version's notes.

The manually started GitHub Actions workflow builds three variants and prepares a draft `QuickSettings v<version>` tagged `v<version>`. Review its packages and notes before publishing. Builds and release preparation are performed only when you run the workflow.

QuickSettings retains the [GPL v3 license](LICENSE) from adapted HaptiX code. ChoySee-derived Other code and row images retain [their MIT notice](quicksettingsprefs/Resources/ChoySee-LICENSE.txt). The blue/teal QuickSettings mark and banners are original local artwork; editable drawing/export source is in [artwork/Export-Artwork.ps1](artwork/Export-Artwork.ps1).
