#!/usr/bin/env python3
"""Read or update TokChan's app-target version settings safely."""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

BUNDLE_IDENTIFIER = "com.youranreus.TokChan"
CONFIGURATION_PATTERN = re.compile(
    r"(?P<prefix>\t\t[A-F0-9]+ = \{\n"
    r"\t\t\tisa = XCBuildConfiguration;\n"
    r"\t\t\tbuildSettings = \{\n)"
    r"(?P<settings>.*?)"
    r"(?P<suffix>\t\t\t\};\n\t\t\tname = (?P<name>Debug|Release);\n\t\t\};)",
    re.DOTALL,
)
SEMVER_COMPONENT = r"(?:0|[1-9][0-9]*)"
SEMVER_PATTERN = re.compile(
    rf"{SEMVER_COMPONENT}\.{SEMVER_COMPONENT}\.{SEMVER_COMPONENT}"
)
POSITIVE_INTEGER_PATTERN = re.compile(r"[1-9][0-9]*")


class VersionError(RuntimeError):
    pass


@dataclass(frozen=True)
class Version:
    marketing: str
    build: str


def setting(settings: str, name: str) -> str:
    matches = re.findall(rf"^\s*{re.escape(name)} = ([^;]+);$", settings, re.MULTILINE)
    if len(matches) != 1:
        raise VersionError(f"expected exactly one {name} setting, found {len(matches)}")
    return matches[0].strip().strip('"')


def app_configurations(contents: str) -> list[re.Match[str]]:
    matches: list[re.Match[str]] = []
    for match in CONFIGURATION_PATTERN.finditer(contents):
        identifiers = re.findall(
            r"^\s*PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);$",
            match.group("settings"),
            re.MULTILINE,
        )
        normalized_identifiers = [value.strip().strip('"') for value in identifiers]
        if BUNDLE_IDENTIFIER not in normalized_identifiers:
            continue
        if normalized_identifiers != [BUNDLE_IDENTIFIER]:
            raise VersionError(
                f"{match.group('name')} must contain exactly one TokChan bundle identifier"
            )
        matches.append(match)
    names = sorted(match.group("name") for match in matches)
    if names != ["Debug", "Release"]:
        raise VersionError(
            "expected exactly the TokChan Debug and Release app configurations; "
            f"found {names}"
        )
    return matches


def read_version(contents: str) -> Version:
    versions: list[Version] = []
    for match in app_configurations(contents):
        settings = match.group("settings")
        if setting(settings, "VERSIONING_SYSTEM") != "apple-generic":
            raise VersionError(
                f"{match.group('name')} must use VERSIONING_SYSTEM = apple-generic"
            )
        versions.append(
            Version(
                marketing=setting(settings, "MARKETING_VERSION"),
                build=setting(settings, "CURRENT_PROJECT_VERSION"),
            )
        )

    if versions[0] != versions[1]:
        raise VersionError(
            "TokChan Debug and Release versions differ: "
            f"{versions[0]} versus {versions[1]}"
        )
    version = versions[0]
    if not SEMVER_PATTERN.fullmatch(version.marketing):
        raise VersionError(f"marketing version is not stable SemVer: {version.marketing}")
    if not POSITIVE_INTEGER_PATTERN.fullmatch(version.build):
        raise VersionError(f"build number is not a positive integer: {version.build}")
    return version


def update_version(contents: str, version: Version) -> str:
    current = read_version(contents)
    if not SEMVER_PATTERN.fullmatch(version.marketing):
        raise VersionError(f"new marketing version is not stable SemVer: {version.marketing}")
    if not POSITIVE_INTEGER_PATTERN.fullmatch(version.build):
        raise VersionError(f"new build number is not a positive integer: {version.build}")

    replacements = 0

    def replace_configuration(match: re.Match[str]) -> str:
        nonlocal replacements
        settings = match.group("settings")
        if not re.search(
            rf'^\s*PRODUCT_BUNDLE_IDENTIFIER = "?{re.escape(BUNDLE_IDENTIFIER)}"?;$',
            settings,
            re.MULTILINE,
        ):
            return match.group(0)
        if setting(settings, "MARKETING_VERSION") != current.marketing:
            raise VersionError("marketing version changed while preparing update")
        if setting(settings, "CURRENT_PROJECT_VERSION") != current.build:
            raise VersionError("build number changed while preparing update")
        settings, marketing_count = re.subn(
            r"(^\s*MARKETING_VERSION = )[^;]+(;)$",
            rf"\g<1>{version.marketing}\2",
            settings,
            count=1,
            flags=re.MULTILINE,
        )
        settings, build_count = re.subn(
            r"(^\s*CURRENT_PROJECT_VERSION = )[^;]+(;)$",
            rf"\g<1>{version.build}\2",
            settings,
            count=1,
            flags=re.MULTILINE,
        )
        if marketing_count != 1 or build_count != 1:
            raise VersionError("could not update both version settings")
        replacements += 1
        return match.group("prefix") + settings + match.group("suffix")

    updated = CONFIGURATION_PATTERN.sub(replace_configuration, contents)
    if replacements != 2:
        raise VersionError(f"expected to update 2 app configurations, updated {replacements}")
    if read_version(updated) != version:
        raise VersionError("updated project did not round-trip to the requested version")
    return updated


def write_project_file(path: Path, contents: str) -> None:
    """Atomically replace the project file without changing its permission bits."""
    stat_result = path.stat()
    descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", suffix=".tmp"
    )
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, stat_result.st_mode)
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as file:
            descriptor = -1
            file.write(contents)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary_path, path)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        temporary_path.unlink(missing_ok=True)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("project_file", type=Path)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("get")
    set_parser = subparsers.add_parser("set")
    set_parser.add_argument("--marketing", required=True)
    set_parser.add_argument("--build", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_arguments()
    try:
        contents = args.project_file.read_text(encoding="utf-8")
        if args.command == "get":
            version = read_version(contents)
            print(f"{version.marketing} {version.build}")
        else:
            requested = Version(marketing=args.marketing, build=args.build)
            updated = update_version(contents, requested)
            write_project_file(args.project_file, updated)
            print(f"{requested.marketing} {requested.build}")
    except (OSError, VersionError) as error:
        print(f"project-version: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
