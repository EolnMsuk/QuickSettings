#!/usr/bin/env bash
# Adapted from HaptiX by EolnMsuk; GPL-3.0, see ../../LICENSE.
# CI only: inspect an already built package; never builds or installs it.
set -euo pipefail
[[ $# == 5 ]] || { echo "Usage: verify-package.sh package variant architecture version minimum-ios" >&2; exit 1; }
package="$1"
variant="$2"
package_arch="$3"
version="$4"
minimum_ios="$5"
fail() { printf '%s\n' "$*" >&2; exit 1; }
check_field() {
    local actual
    actual=$(dpkg-deb -f "$package" "$1")
    [[ "$actual" == "$2" ]] || fail "Expected $1=$2; found $actual."
}
prefix=
case "$variant:$package_arch" in
    roothide:iphoneos-arm64e) environment=RootHide ;;
    rootless:iphoneos-arm64) prefix=var/jb/; environment=rootless ;;
    rootful:iphoneos-arm) environment=rootful ;;
    *) fail "Inconsistent variant and Debian architecture." ;;
esac
[[ "$minimum_ios" == 15.0 ]] || fail "All QuickSettings variants target iOS 15.0."
check_field Package com.eolnmsuk.quicksettings
check_field Name QuickSettings
check_field Version "$version"
check_field Architecture "$package_arch"

# The dependency IDs remain the package-manager interfaces for each variant;
# binary load paths below independently verify each toolchain's relocation.
dependencies=$(dpkg-deb -f "$package" Depends)
python3 - "$dependencies" <<'PY'
import re, sys
items = {re.sub(r"\s+", "", item) for item in sys.argv[1].split(",")}
assert items == {"firmware(>=15.0)", "mobilesubstrate", "preferenceloader"}, items
PY

extracted=$(mktemp -d "$RUNNER_TEMP/quicksettings-package.XXXXXXXX")
trap 'rm -rf -- "$extracted"' EXIT
dpkg-deb -x "$package" "$extracted"
tweak=
for candidate in Library/MobileSubstrate/DynamicLibraries/QuickSettings.dylib usr/lib/TweakInject/QuickSettings.dylib; do
    if [[ -f "$extracted/$prefix$candidate" ]]; then
        [[ -z "$tweak" ]] || fail "Multiple tweak binaries."
        tweak="$prefix$candidate"
    fi
done
[[ -n "$tweak" ]] || fail "No QuickSettings.dylib under the expected install root."
bundle="${prefix}Library/PreferenceBundles/quicksettingsprefs.bundle"
entry="${prefix}Library/PreferenceLoader/Preferences/QuickSettings.plist"
prefs="$extracted/$bundle/quicksettingsprefs"
for path in "$tweak" "${tweak%.dylib}.plist" "$bundle/quicksettingsprefs" "$entry"; do
    [[ -f "$extracted/$path" && ! -L "$extracted/$path" ]] || fail "Missing regular payload file: $path."
done
[[ $(find "$extracted" -name QuickSettings.dylib -type f | wc -l | tr -d ' ') == 1 ]] || fail "Unexpected duplicate tweak payload."
if [[ "$variant" != rootless && -e "$extracted/var/jb" ]]; then fail "Stock rootless payload in $variant."; fi

python3 - "$extracted" "$bundle" "$entry" "${tweak%.dylib}.plist" "$version" <<'PY'
from pathlib import Path
import plistlib, struct, sys
root, bundle, entry, filter_path = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
version = sys.argv[5]
def plist(path):
    with (root / path).open("rb") as file:
        return plistlib.load(file)
info = plist(bundle + "/Info.plist")
assert info["CFBundleIdentifier"] == "com.eolnmsuk.quicksettingsprefs"
assert info["CFBundleExecutable"] == "quicksettingsprefs"
assert info["NSPrincipalClass"] == "QSRootListController"
assert info["CFBundleVersion"] == info["CFBundleShortVersionString"] == version
assert info["MinimumOSVersion"] == "15.0"
assert plist(filter_path) == {"Filter": {"Bundles": ["com.apple.springboard", "com.apple.Preferences"]}}
registration = plist(entry)["entry"]
assert registration["bundle"] == "quicksettingsprefs" and registration["detail"] == "QSRootListController"
assert registration["label"] == "QuickSettings" and registration["icon"] == "icon.png"
rows = plist(bundle + "/Root.plist")["items"]
assert [r.get("label") for r in rows if r.get("label")] == [
    "Enable QuickSettings", "Other", "Updates", "GitHub", "Reddit", "Donate"]
switch = next(r for r in rows if r.get("key") == "enabled")
assert switch["defaults"] == "com.eolnmsuk.quicksettings" and switch["default"] is False
assert switch["PostNotification"] == "com.eolnmsuk.quicksettings/ReloadPrefs"
sizes = {"icon.png": (29,29), "icon@2x.png": (58,58), "icon@3x.png": (87,87),
         "package-icon.png": (1024,1024), "banner-dark.png": (1600,600),
         "banner-light.png": (1600,600), "banner-sileo-dark.png": (1600,600)}
for name, size in sizes.items():
    data = (root / bundle / name).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", data[16:24]) == size, name
for name in ("GitHub@2x.png","GitHub@3x.png","Reddit@2x.png","Reddit@3x.png"):
    assert (root / bundle / name).is_file(), name
assert "Lars Fröder" in (root / bundle / "ChoySee-LICENSE.txt").read_text(encoding="utf-8")
assert "GNU GENERAL PUBLIC LICENSE" in (root / bundle / "QuickSettings-LICENSE.txt").read_text(encoding="utf-8")
PY

for binary in "$extracted/$tweak" "$prefs"; do
    archs=$(xcrun lipo -archs "$binary")
    case "$archs" in 'arm64 arm64e'|'arm64e arm64') ;; *) fail "Expected both intended slices in $binary: $archs" ;; esac
    binary_strings=$(strings "$binary")
    grep -Fxq "$environment" <<< "$binary_strings" || fail "Missing compiled $environment metadata in $binary."
    for arch in arm64 arm64e; do
        libraries=$(xcrun otool -arch "$arch" -L "$binary")
        commands=$(xcrun otool -arch "$arch" -l "$binary")
        minos=$(awk '
            $1 == "cmd" {ios = $2 == "LC_BUILD_VERSION" || $2 == "LC_VERSION_MIN_IPHONEOS"}
            ios && ($1 == "minos" || $1 == "version") {print $2; exit}
        ' <<< "$commands")
        runpaths=$(awk '
            $1 == "cmd" {rpath = $2 == "LC_RPATH"}
            rpath && $1 == "path" {print $2}
        ' <<< "$commands")
        [[ "$minos" == 15.0 || "$minos" == 15.0.0 ]] || fail "Expected iOS 15.0 for $binary ($arch), found $minos."
        if grep -Eiq 'AltList' <<< "$libraries"; then fail "Unrelated framework in $binary."; fi
        if [[ "$variant" != rootless ]] && grep -Eq '^[[:space:]]*/var/jb(/|$)' <<< "$libraries"$'\n'"$runpaths"; then
            fail "Stock rootless load path in $variant binary."
        fi
        if [[ "$variant" == rootful ]] && grep -Fq '.jbroot' <<< "$libraries"$'\n'"$runpaths"; then
            fail "Relocated load path in rootful binary."
        fi
        if [[ "$variant" == rootless ]] && grep -Eq '^[[:space:]]*/Library/|^[[:space:]]*/usr/lib/libsubstrate' <<< "$libraries"; then
            fail "Unrelocated jailbreak library in rootless binary."
        fi
        if [[ "$binary" == "$extracted/$tweak" ]]; then
            substrate=$(awk '$1 ~ /(libsubstrate\.dylib|CydiaSubstrate\.framework\/CydiaSubstrate)$/ {print $1}' <<< "$libraries")
            case "$variant:$substrate" in
                roothide:@loader_path/.jbroot/usr/lib/libsubstrate.dylib|roothide:@loader_path/.jbroot/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate) ;;
                rootless:/var/jb/usr/lib/libsubstrate.dylib|rootless:/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate) ;;
                rootless:@rpath/libsubstrate.dylib)
                    grep -Eq '^(/var/jb|@loader_path/\.jbroot)/usr/lib$' <<< "$runpaths" || fail "Missing rootless substrate runpath." ;;
                rootless:@rpath/CydiaSubstrate.framework/CydiaSubstrate)
                    grep -Eq '^(/var/jb|@loader_path/\.jbroot)/Library/Frameworks$' <<< "$runpaths" || fail "Missing rootless framework runpath." ;;
                rootful:/usr/lib/libsubstrate.dylib|rootful:/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate) ;;
                *) fail "Unexpected substrate load path for $variant: ${substrate:-none}." ;;
            esac
        fi
        printf 'Verified %s (%s), iOS %s, %s\n' "$binary" "$arch" "$minos" "$environment"
        printf '%s\n' "$libraries"
    done
done
printf 'Verified package metadata, resources, notices, payload, slices and scheme paths: %s\n' "$package"
