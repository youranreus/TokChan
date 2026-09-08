#!/usr/bin/env python3
"""Verify workflow actions match commits reviewed against upstream release tags."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/release.yml"
ACTION_PATTERN = re.compile(
    r"^\s*uses:\s*([^@\s]+)@([^\s#]+)(?:\s+#\s*(\S+))?\s*$", re.MULTILINE
)
FULL_COMMIT_PATTERN = re.compile(r"[0-9a-f]{40}")

# Each commit was independently resolved against the named tag in the action's
# authoritative GitHub repository. Keeping the allowlist local makes the release
# fixture deterministic offline while requiring an intentional review for upgrades.
REVIEWED_ACTION_PINS = {
    "actions/checkout": (
        "3d3c42e5aac5ba805825da76410c181273ba90b1",
        "v7.0.1",
    ),
    "actions/configure-pages": (
        "983d7736d9b0ae728b81ab479565c72886d7745b",
        "v5.0.0",
    ),
    "actions/upload-pages-artifact": (
        "7b1f4a764d45c48632c6b24a0339c27f5614fb0b",
        "v4.0.0",
    ),
    "actions/deploy-pages": (
        "d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e",
        "v4.0.5",
    ),
}


class WorkflowActionPinTests(unittest.TestCase):
    def test_release_workflow_uses_reviewed_upstream_release_commits(self) -> None:
        matches = ACTION_PATTERN.findall(WORKFLOW.read_text(encoding="utf-8"))
        self.assertTrue(matches, "release workflow contains no actions")

        actual: dict[str, tuple[str, str | None]] = {}
        for action, revision, version in matches:
            self.assertNotIn(action, actual, f"duplicate action invocation: {action}")
            self.assertRegex(
                revision,
                rf"\A{FULL_COMMIT_PATTERN.pattern}\Z",
                f"{action} is not pinned to a lowercase full commit",
            )
            actual[action] = (revision, version or None)

        self.assertEqual(actual, REVIEWED_ACTION_PINS)


if __name__ == "__main__":
    unittest.main()
