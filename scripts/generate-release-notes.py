#!/usr/bin/env python3
"""Generate deterministic Chinese release notes from append-only Git fragments."""

from __future__ import annotations

import argparse
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unicodedata

CATEGORIES = ("新增", "优化", "修复")
SEMVER_RE = re.compile(r"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
FRAGMENT_RE = re.compile(r"^release-notes/fragments/[0-9]{8}-[a-z0-9][a-z0-9-]*\.json$")
HAN_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
HTML_TAG_RE = re.compile(r"<[^>]*>")
SECURITY_PARAGRAPHS = (
    "本版本使用 Developer ID 签名并通过 Apple 公证，TokChan.app 与 DMG 均已装订公证票据。macOS 仍可能要求确认打开从互联网下载的应用。",
    "下载 DMG 后，将 TokChan.app 拖到镜像中的“应用程序”文件夹完成安装。使用前请按随附的 .sha256 文件校验 DMG 的 SHA-256；校验失败时不要安装或运行。",
)


class ReleaseNotesError(Exception):
    pass


def git(*args: str, text: bool = True) -> str | bytes:
    result = subprocess.run(
        ["git", *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=text, check=False
    )
    if result.returncode:
        detail = result.stderr.strip() if text else result.stderr.decode("utf-8", "replace").strip()
        raise ReleaseNotesError(f"Git command failed: git {' '.join(args)}: {detail}")
    return result.stdout


def parse_semver(tag: str) -> tuple[int, int, int]:
    match = SEMVER_RE.fullmatch(tag)
    if not match:
        raise ReleaseNotesError(f"Tag must be stable SemVer vX.Y.Z: {tag}")
    return tuple(map(int, match.groups()))  # type: ignore[return-value]


def resolve_tags(current_tag: str) -> tuple[str, str | None]:
    current_version = parse_semver(current_tag)
    current_commit = str(git("rev-parse", "--verify", f"{current_tag}^{{commit}}")).strip()
    tags: list[tuple[tuple[int, int, int], str, str]] = []
    for tag in str(git("tag", "--list")).splitlines():
        match = SEMVER_RE.fullmatch(tag)
        if tag == current_tag or not match:
            continue
        commit = str(git("rev-parse", "--verify", f"{tag}^{{commit}}")).strip()
        tags.append((tuple(map(int, match.groups())), tag, commit))

    ancestors = []
    for version, tag, commit in tags:
        status = subprocess.run(
            ["git", "merge-base", "--is-ancestor", commit, current_commit],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            check=False,
        ).returncode
        if status == 0:
            if version >= current_version:
                raise ReleaseNotesError(f"Stable ancestor {tag} is not older than {current_tag}")
            ancestors.append((version, tag))
        elif status != 1:
            raise ReleaseNotesError(f"Could not inspect ancestry for {tag}")
    if ancestors:
        return current_commit, max(ancestors)[1]
    if tags:
        raise ReleaseNotesError("Repository has stable Tags but current Tag has no stable ancestor")
    return current_commit, None


def tree_entries(ref: str) -> dict[str, str]:
    output = str(git("ls-tree", "-r", ref, "--", "release-notes/fragments"))
    entries: dict[str, str] = {}
    for line in output.splitlines():
        metadata, path = line.split("\t", 1)
        mode, kind, object_id = metadata.split()
        if mode != "100644" or kind != "blob":
            raise ReleaseNotesError(f"Fragment must be a regular non-symlink file: {path}")
        if not FRAGMENT_RE.fullmatch(path):
            raise ReleaseNotesError(f"Invalid fragment path: {path}")
        entries[path] = object_id
    return entries


def touched_paths(previous: str, current: str) -> set[str]:
    output = str(
        git(
            "log",
            "--format=",
            "--name-only",
            f"{previous}..{current}",
            "--",
            "release-notes/fragments",
        )
    )
    return {line for line in output.splitlines() if line}


def reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ReleaseNotesError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def read_fragment(ref: str, path: str) -> dict[str, str]:
    raw = git("show", f"{ref}:{path}", text=False)
    assert isinstance(raw, bytes)
    try:
        source = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ReleaseNotesError(f"Fragment is not UTF-8: {path}") from error
    try:
        value = json.loads(source, object_pairs_hook=reject_duplicate_keys)
    except (json.JSONDecodeError, ReleaseNotesError) as error:
        raise ReleaseNotesError(f"Invalid JSON fragment {path}: {error}") from error
    if not isinstance(value, dict) or set(value) != {"category", "summary"}:
        raise ReleaseNotesError(f"Fragment must contain exactly category and summary: {path}")
    category, summary = value["category"], value["summary"]
    if not isinstance(category, str) or category not in CATEGORIES:
        raise ReleaseNotesError(f"Invalid category in fragment: {path}")
    if not isinstance(summary, str):
        raise ReleaseNotesError(f"Summary must be a string: {path}")
    if summary != summary.strip() or "\n" in summary or "\r" in summary:
        raise ReleaseNotesError(f"Summary must be trimmed and single-line: {path}")
    if summary != unicodedata.normalize("NFC", summary):
        raise ReleaseNotesError(f"Summary must use NFC normalization: {path}")
    if any(unicodedata.category(character) == "Cc" for character in summary):
        raise ReleaseNotesError(f"Summary contains a control character: {path}")
    if HTML_TAG_RE.search(summary):
        raise ReleaseNotesError(f"Summary must not contain HTML tags: {path}")
    if not HAN_RE.search(summary):
        raise ReleaseNotesError(f"Summary must contain Chinese text: {path}")
    if not 8 <= len(summary) <= 80:
        raise ReleaseNotesError(f"Summary must contain 8–80 Unicode code points: {path}")
    return {"category": category, "summary": summary, "path": path}


def select_fragments(current: str, previous: str | None) -> list[dict[str, str]]:
    current_entries = tree_entries(current)
    if previous is None:
        selected_paths = set(current_entries)
    else:
        previous_entries = tree_entries(previous)
        touched = touched_paths(previous, current)
        selected_paths: set[str] = set()
        for path in touched:
            before, after = previous_entries.get(path), current_entries.get(path)
            if before is None and after is not None:
                selected_paths.add(path)
            elif before is not None and after == before:
                continue
            elif before is not None:
                raise ReleaseNotesError(f"Historical fragment was modified, deleted, or renamed: {path}")
            else:
                raise ReleaseNotesError(f"Fragment was added and removed within the release range: {path}")
        unexpected = set(current_entries) - set(previous_entries) - selected_paths
        if unexpected:
            raise ReleaseNotesError(f"New fragment was not attributable to the release range: {min(unexpected)}")

    # Validate the complete current directory, including permanent historical fragments.
    parsed = {path: read_fragment(current, path) for path in sorted(current_entries)}
    selected = [parsed[path] for path in sorted(selected_paths)]
    if not selected:
        raise ReleaseNotesError("No user-visible release-note fragments were selected")
    if len(selected) > 12:
        raise ReleaseNotesError("A release may contain at most 12 fragments")
    summaries: set[str] = set()
    for item in selected:
        if item["summary"] in summaries:
            raise ReleaseNotesError(f"Duplicate release-note summary: {item['summary']}")
        summaries.add(item["summary"])
    return sorted(selected, key=lambda item: (CATEGORIES.index(item["category"]), item["path"]))


def markdown_escape(value: str) -> str:
    return re.sub(r"([\\`*_[\]<>])", r"\\\1", value)


def render_markdown(items: list[dict[str, str]]) -> str:
    lines = ["## 本次更新", ""]
    for category in CATEGORIES:
        matching = [item for item in items if item["category"] == category]
        if matching:
            lines.extend([f"### {category}", *[f"- {markdown_escape(item['summary'])}" for item in matching], ""])
    lines.extend(["## 下载与安全说明", "", "> [!NOTE]", f"> {SECURITY_PARAGRAPHS[0]}", "", SECURITY_PARAGRAPHS[1], ""])
    return "\n".join(lines)


def render_html(version: str, repository: str, items: list[dict[str, str]]) -> str:
    lines = [
        "<!doctype html>",
        '<html lang="zh-CN">',
        "  <head>",
        '    <meta charset="utf-8">',
        f"    <title>TokChan {html.escape(version)} 更新说明</title>",
        "  </head>",
        "  <body>",
        f"    <h1>TokChan {html.escape(version)}</h1>",
        "    <h2>本次更新</h2>",
    ]
    for category in CATEGORIES:
        matching = [item for item in items if item["category"] == category]
        if matching:
            lines.extend([f"    <h3>{category}</h3>", "    <ul>"])
            lines.extend(f"      <li>{html.escape(item['summary'])}</li>" for item in matching)
            lines.append("    </ul>")
    lines.extend(
        [
            "    <h2>下载与安全说明</h2>",
            f"    <p>{html.escape(SECURITY_PARAGRAPHS[0])}</p>",
            f"    <p>{html.escape(SECURITY_PARAGRAPHS[1])}</p>",
            f'    <p><a href="https://github.com/{html.escape(repository, quote=True)}/releases/tag/v{html.escape(version, quote=True)}">在 GitHub 查看此版本</a></p>',
            "  </body>",
            "</html>",
            "",
        ]
    )
    return "\n".join(lines)


def validate_repository(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise argparse.ArgumentTypeError("repository must have owner/name form")
    return value


def publish_outputs(output_dir: Path, files: dict[str, str]) -> None:
    if output_dir.is_symlink():
        raise ReleaseNotesError("Output directory must not be a symlink")
    if output_dir.exists() and (not output_dir.is_dir() or any(output_dir.iterdir())):
        raise ReleaseNotesError("Output directory must be absent or empty")
    output_dir.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=".release-notes-", dir=output_dir.parent))
    try:
        for name, content in files.items():
            (stage / name).write_bytes(content.encode("utf-8"))
        for name in files:
            os.replace(stage / name, output_dir / name)
    except Exception:
        for name in files:
            (output_dir / name).unlink(missing_ok=True)
        raise
    finally:
        shutil.rmtree(stage, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--repository", required=True, type=validate_repository)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    try:
        current, previous = resolve_tags(args.tag)
        items = select_fragments(current, previous)
        version = args.tag.removeprefix("v")
        manifest = {
            "version": version,
            "previousTag": previous,
            "categories": [
                {
                    "category": category,
                    "items": [
                        {"path": item["path"], "summary": item["summary"]}
                        for item in items
                        if item["category"] == category
                    ],
                }
                for category in CATEGORIES
                if any(item["category"] == category for item in items)
            ],
        }
        publish_outputs(
            args.output_dir,
            {
                "github.md": render_markdown(items),
                "sparkle.html": render_html(version, args.repository, items),
                "manifest.json": json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            },
        )
    except (OSError, ReleaseNotesError) as error:
        parser.exit(1, f"generate-release-notes: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
