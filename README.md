# QuickSettings

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="quicksettingsprefs/Resources/banner-dark.png">
  <img src="quicksettingsprefs/Resources/banner-light.png" alt="QuickSettings by EolnMsuk — App settings. One press away." width="100%">
</picture>

**QuickSettings** by **EolnMsuk** adds **App Settings** to eligible Home Screen application menus. Long-press an app icon to open that app's own Settings page. Other stock and tweak quick actions keep their order.

## Install

<!-- release-assets:start -->
Current version: **1.0.0**.

| Download | Environment | Debian architecture |
| --- | --- | --- |
| `com.eolnmsuk.QuickSettings_1.0.0_roothide.deb` | RootHide | `iphoneos-arm64e` |
| `com.eolnmsuk.QuickSettings_1.0.0_rootless.deb` | rootless | `iphoneos-arm64` |
| `com.eolnmsuk.QuickSettings_1.0.0_rootful.deb` | rootful | `iphoneos-arm` |
<!-- release-assets:end -->

Download from the [published releases](https://github.com/EolnMsuk/QuickSettings/releases). Open the matching `.deb` in your jailbreak package manager, such as Sileo, and follow its installation instructions. Let the package manager perform any initial process reload it requires to load a newly installed tweak.

## Enable and use

1. Open **Settings > QuickSettings** and turn on **Enable QuickSettings**. The initial value is **off**.
2. Allow the native app-page cache to warm, then long-press a Home Screen app, including an app in the Dock or a folder.
3. Select **App Settings** to open that application's page.

Enable and disable changes apply live to newly opened menus; changing this switch requires no respring. An already visible action checks the committed preference again before opening.
