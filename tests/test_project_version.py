#!/usr/bin/env python3

import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts/lib/project-version.py"
FIXTURE_VERSION = "7.8.9"
FIXTURE_BUILD = "42"
UPDATED_VERSION = "7.8.10"
UPDATED_BUILD = "43"
spec = importlib.util.spec_from_file_location("project_version", MODULE_PATH)
project_version = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = project_version
spec.loader.exec_module(project_version)


class ProjectVersionTests(unittest.TestCase):
    def setUp(self) -> None:
        repository_contents = (ROOT / "TokChan.xcodeproj/project.pbxproj").read_text()
        # Normalize the isolated input so a real release bump cannot invalidate the tests.
        self.contents = project_version.update_version(
            repository_contents,
            project_version.Version(FIXTURE_VERSION, FIXTURE_BUILD),
        )

    def test_reads_matching_app_configurations(self) -> None:
        version = project_version.read_version(self.contents)
        self.assertEqual(
            version, project_version.Version(FIXTURE_VERSION, FIXTURE_BUILD)
        )

    def test_updates_only_two_authoritative_settings(self) -> None:
        updated = project_version.update_version(
            self.contents, project_version.Version(UPDATED_VERSION, UPDATED_BUILD)
        )
        self.assertEqual(
            updated.count(f"MARKETING_VERSION = {UPDATED_VERSION};"), 2
        )
        self.assertEqual(
            updated.count(f"CURRENT_PROJECT_VERSION = {UPDATED_BUILD};"), 2
        )
        self.assertEqual(
            project_version.read_version(updated),
            project_version.Version(UPDATED_VERSION, UPDATED_BUILD),
        )

    def test_writes_project_file_atomically_and_preserves_permissions(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "project.pbxproj"
            path.write_text(self.contents, encoding="utf-8")
            path.chmod(0o640)
            updated = project_version.update_version(
                self.contents, project_version.Version(UPDATED_VERSION, UPDATED_BUILD)
            )

            project_version.write_project_file(path, updated)

            self.assertEqual(path.read_text(encoding="utf-8"), updated)
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o640)
            self.assertEqual(list(path.parent.glob(".project.pbxproj.*.tmp")), [])

    def test_supports_xcode_quoting_the_bundle_identifier(self) -> None:
        quoted = self.contents.replace(
            "PRODUCT_BUNDLE_IDENTIFIER = com.youranreus.TokChan;",
            'PRODUCT_BUNDLE_IDENTIFIER = "com.youranreus.TokChan";',
        )
        updated = project_version.update_version(
            quoted, project_version.Version(UPDATED_VERSION, UPDATED_BUILD)
        )
        self.assertEqual(
            project_version.read_version(updated),
            project_version.Version(UPDATED_VERSION, UPDATED_BUILD),
        )

    def test_rejects_configuration_drift(self) -> None:
        drifted = self.contents.replace(
            f"MARKETING_VERSION = {FIXTURE_VERSION};",
            "MARKETING_VERSION = 7.8.99;",
            1,
        )
        with self.assertRaisesRegex(project_version.VersionError, "versions differ"):
            project_version.read_version(drifted)

    def test_rejects_prerelease_and_zero_build(self) -> None:
        with self.assertRaisesRegex(project_version.VersionError, "stable SemVer"):
            project_version.update_version(
                self.contents, project_version.Version("0.2.0-beta.1", "2")
            )
        with self.assertRaisesRegex(project_version.VersionError, "positive integer"):
            project_version.update_version(
                self.contents, project_version.Version("0.2.0", "0")
            )

    def test_rejects_missing_generic_versioning_contract(self) -> None:
        broken = self.contents.replace('\t\t\t\tVERSIONING_SYSTEM = "apple-generic";\n', "", 1)
        with self.assertRaisesRegex(project_version.VersionError, "VERSIONING_SYSTEM"):
            project_version.read_version(broken)


if __name__ == "__main__":
    unittest.main()
