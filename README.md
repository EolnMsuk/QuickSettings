# QuickSettings

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="quicksettingsprefs/Resources/banner-dark.png">
  <img src="quicksettingsprefs/Resources/banner-light.png" alt="QuickSettings by EolnMsuk — App settings. One press away." width="100%">
</picture>

**QuickSettings** by **EolnMsuk** adds **App Settings** to Home Screen application menus. Long-press an app icon to request that app's own Settings page.

## Install

<!-- release-assets:start -->
Current version: **1.0.1**.

| Download | Environment | Debian architecture |
| --- | --- | --- |
| `com.eolnmsuk.QuickSettings_1.0.1_roothide.deb` | RootHide | `iphoneos-arm64e` |
| `com.eolnmsuk.QuickSettings_1.0.1_rootless.deb` | rootless | `iphoneos-arm64` |
| `com.eolnmsuk.QuickSettings_1.0.1_rootful.deb` | rootful | `iphoneos-arm` |
<!-- release-assets:end -->

Download from the [published releases](https://github.com/EolnMsuk/QuickSettings/releases). Open the matching `.deb` in your jailbreak package manager, such as Sileo, and follow its installation instructions. Let the package manager perform any initial process reload it requires to load a newly installed tweak.

## Enable and use

1. Open **Settings > QuickSettings** and turn on **Enable QuickSettings**. The initial value is **off**.
2. Long-press a Home Screen app, including an app in the Dock or a folder. No app-page cache warmup is needed.
3. Select **App Settings** to open that application's page.

Enable and disable changes apply live to newly opened menus; changing this switch requires no respring. An already visible action checks the committed preference on a worker before opening. Preference changes and newer selections invalidate pending work; an open already submitted to iOS cannot be recalled. Identical pending requests are coalesced.

**App Settings** can appear even when an app has no dedicated Settings page. QuickSettings checks real application icons without scanning the installed app list. Folder, bookmark, and widget icons are excluded, and existing quick actions retain their order.