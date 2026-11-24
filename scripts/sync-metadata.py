#!/usr/bin/env python3
"""Synchronize QuickSettings release metadata, using only the standard library."""
# QuickSettings — EolnMsuk. See ../LICENSE.
import argparse
import json
from pathlib import Path
import plistlib
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
VERSION = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")
START = "<!-- release-assets:start -->"
END = "<!-- release-assets:end -->"


def control_version():
    fields = {}
    for line in (ROOT / "control").read_text(encoding="utf-8").splitlines():
        key, separator, value = line.partition(":")
        if separator:
            if key in fields:
                raise ValueError(f"Duplicate control field: {key}")
            fields[key] = value.strip()
    if fields.get("Name") != "QuickSettings" or fields.get("Package") != "com.eolnmsuk.quicksettings":
        raise ValueError("Expected the exact QuickSettings Name and Package fields.")
    version = fields.get("Version", "")
    if not VERSION.fullmatch(version):
        raise ValueError("Expected exactly one stable major.minor.patch Version in control.")
    return version


def changelog(version):
    text = (ROOT / "changelog.md").read_text(encoding="utf-8")
    headings = list(re.finditer(r"^## ([^\n]+)\n", text, re.MULTILINE))
    if not headings:
        raise ValueError("No version sections in changelog.md.")
    sections = {}
    for index, heading in enumerate(headings):
        name = heading.group(1)
        if not VERSION.fullmatch(name) or name in sections:
            raise ValueError(f"Invalid or ambiguous changelog version: {name}")
        end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
        notes = text[heading.end():end].strip()
        if not notes or not re.search(r"^[-*] ", notes, re.MULTILINE):
            raise ValueError(f"Missing release notes for {name}")
        sections[name] = notes
    if headings[0].group(1) != version or version not in sections:
        raise ValueError("The first changelog section must match control's version.")
    history = "\n\n".join(f"## {name}\n\n{notes}" for name, notes in sections.items())
    return sections[version] + "\n", history


def asset_block(version):
    rows = [
        ("roothide", "RootHide", "iphoneos-arm64e"),
        ("rootless", "rootless", "iphoneos-arm64"),
        ("rootful", "rootful", "iphoneos-arm"),
    ]
    table = "\n".join(
        f"| `com.eolnmsuk.QuickSettings_{version}_{suffix}.deb` | {label} | `{arch}` |"
        for suffix, label, arch in rows
    )
    return (
        f"{START}\nCurrent version: **{version}**.\n\n"
        "| Download | Environment | Debian architecture |\n| --- | --- | --- |\n"
        f"{table}\n{END}"
    )


def exactly_one(values, description):
    if len(values) != 1:
        raise ValueError(f"Expected exactly one {description}; found {len(values)}.")
    return values[0]


def synchronize(version, history, check, skip_readme=False):
    drift = []
    info_path = ROOT / "quicksettingsprefs/Resources/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    expected_info = dict(info, CFBundleVersion=version, CFBundleShortVersionString=version)
    if info != expected_info:
        drift.append(str(info_path.relative_to(ROOT)))
        if not check:
            info_path.write_bytes(plistlib.dumps(expected_info, sort_keys=False))

    depiction_path = ROOT / "depiction.json"
    depiction = json.loads(depiction_path.read_text(encoding="utf-8"))
    original_depiction = json.loads(json.dumps(depiction))
    tabs = depiction["tabs"]
    changes = exactly_one([t for t in tabs if t.get("tabname") == "Changelog"], "Changelog tab")
    markdown = exactly_one([v for v in changes["views"] if v.get("class") == "DepictionMarkdownView"], "changelog markdown view")
    markdown["markdown"] = history
    information = exactly_one([t for t in tabs if t.get("tabname") == "Information"], "Information tab")
    version_row = exactly_one([v for v in information["views"] if v.get("title") == "Version"], "depiction Version row")
    version_row["text"] = version
    if depiction != original_depiction:
        drift.append("depiction.json")
        if not check:
            depiction_path.write_text(json.dumps(depiction, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    if not skip_readme:
        readme_path = ROOT / "README.md"
        readme = readme_path.read_text(encoding="utf-8")
        if readme.count(START) != 1 or readme.count(END) != 1 or readme.index(START) >= readme.index(END):
            raise ValueError("README must contain exactly one ordered release-assets marker pair.")
        start, end = readme.index(START), readme.index(END) + len(END)
        expected_readme = readme[:start] + asset_block(version) + readme[end:]
        if readme != expected_readme:
            drift.append("README.md")
            if not check:
                readme_path.write_text(expected_readme, encoding="utf-8", newline="\n")
    if drift and check:
        command = "python3 scripts/sync-metadata.py" + (" --skip-readme" if skip_readme else "")
        raise ValueError("Metadata drift: " + ", ".join(drift) + ". Run " + command + ".")
    return drift


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-readme", action="store_true",
                        help="exclude only README validation, generation and writes")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="fail on metadata drift, without writing")
    mode.add_argument("--release-notes", action="store_true", help="print only the current version's notes")
    mode.add_argument("--print-version", action="store_true", help="print the validated control version")
    args = parser.parse_args()
    try:
        version = control_version()
        notes, history = changelog(version)
        if args.print_version:
            print(version)
        elif args.release_notes:
            sys.stdout.write(notes)
        else:
            if args.skip_readme:
                print("README.md excluded (--skip-readme).")
            changed = synchronize(version, history, args.check, args.skip_readme)
            print(f"QuickSettings {version}: " + ("metadata consistent." if not changed else "synchronized " + ", ".join(changed)))
    except (ValueError, KeyError, OSError, plistlib.InvalidFileException, json.JSONDecodeError) as error:
        print(f"Metadata error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
