#!/usr/bin/env python3
from __future__ import annotations

import json
from html.parser import HTMLParser
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/generate-release-notes.py"


class NotesParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.heading = None
        self.items = []
        self.in_li = False

    def handle_starttag(self, tag, attrs):
        if tag == "h3": self.heading = ""
        if tag == "li": self.in_li = True

    def handle_endtag(self, tag):
        if tag == "li": self.in_li = False

    def handle_data(self, data):
        if self.heading == "": self.heading = data
        elif self.in_li: self.items.append((self.heading, data))


class ReleaseNotesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp.name) / "repo"
        self.repo.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.com")
        self.commit("initial")

    def tearDown(self): self.temp.cleanup()

    def git(self, *args, check=True):
        return subprocess.run(["git", *args], cwd=self.repo, text=True, capture_output=True, check=check)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", message)

    def tag(self, name): self.git("tag", "-a", name, "-m", name)

    def fragment(self, name, category="修复", summary="修复自动提交服务无法恢复的问题"):
        path = self.repo / "release-notes/fragments" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"category": category, "summary": summary}, ensure_ascii=False), encoding="utf-8")
        return path

    def generate(self, tag, output="out"):
        return subprocess.run(
            ["python3", str(SCRIPT), "--tag", tag, "--repository", "owner/repo", "--output-dir", output],
            cwd=self.repo, text=True, capture_output=True,
        )

    def test_first_release_orders_categories_and_channels_match(self):
        self.fragment("20260103-fix.json", "修复", "修复更新失败后无法重试的问题")
        self.fragment("20260101-new.json", "新增", "新增菜单栏手动检查更新入口")
        self.fragment("20260102-opt.json", "优化", "优化设置页面的状态显示方式")
        self.commit("features"); self.tag("v1.0.0")
        result = self.generate("v1.0.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((self.repo / "out/manifest.json").read_text())
        self.assertEqual([x["category"] for x in manifest["categories"]], ["新增", "优化", "修复"])
        parser = NotesParser(); parser.feed((self.repo / "out/sparkle.html").read_text())
        expected = [(group["category"], item["summary"]) for group in manifest["categories"] for item in group["items"]]
        self.assertEqual(parser.items, expected)
        markdown = (self.repo / "out/github.md").read_text()
        self.assertIn("## 本次更新", markdown)
        self.assertIn("Developer ID", markdown)
        self.assertIn("SHA-256", markdown)

    def test_previous_fragments_are_excluded_and_empty_categories_omitted(self):
        self.fragment("20260101-old.json"); self.commit("old"); self.tag("v1.0.0")
        self.fragment("20260102-new.json", "新增", "新增自动检查版本更新的操作入口")
        self.commit("new"); self.tag("v1.1.0")
        result = self.generate("v1.1.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        body = (self.repo / "out/github.md").read_text()
        self.assertIn("### 新增", body); self.assertNotIn("### 修复", body)
        self.assertNotIn("自动提交服务", body)

    def test_repeated_run_is_byte_identical(self):
        self.fragment("20260101-fix.json"); self.commit("fix"); self.tag("v1.0.0")
        self.assertEqual(self.generate("v1.0.0", "one").returncode, 0)
        self.assertEqual(self.generate("v1.0.0", "two").returncode, 0)
        for name in ("github.md", "sparkle.html", "manifest.json"):
            self.assertEqual((self.repo/"one"/name).read_bytes(), (self.repo/"two"/name).read_bytes())

    def test_html_is_escaped(self):
        self.fragment("20260101-fix.json", summary="修复 A&B 配置无法正确保存的问题")
        self.commit("fix"); self.tag("v1.0.0")
        self.assertEqual(self.generate("v1.0.0").returncode, 0)
        self.assertIn("A&amp;B", (self.repo/"out/sparkle.html").read_text())

    def test_rejects_empty_release_without_partial_outputs(self):
        self.tag("v1.0.0")
        result = self.generate("v1.0.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No user-visible", result.stderr)
        self.assertEqual(list((self.repo/"out").glob("*")), [])

    def test_rejects_history_mutation_deletion_and_transient_fragment(self):
        for action in ("modify", "delete", "transient"):
            with self.subTest(action=action):
                # A fresh repository per subtest is simpler than rewinding annotated tags.
                self.tearDown(); self.setUp()
                old = self.fragment("20260101-old.json"); self.commit("old"); self.tag("v1.0.0")
                if action == "modify": old.write_text(json.dumps({"category":"修复","summary":"修复历史内容遭到错误修改的问题"}, ensure_ascii=False))
                elif action == "delete": old.unlink()
                else:
                    temp = self.fragment("20260102-temp.json"); self.commit("add transient"); temp.unlink()
                self.commit(action); self.tag("v1.1.0")
                result = self.generate("v1.1.0")
                self.assertNotEqual(result.returncode, 0)

    def test_rejects_divergent_stable_history(self):
        self.tag("v1.0.0")
        self.git("checkout", "-q", "--orphan", "other")
        self.git("rm", "-rf", ".", check=False)
        self.fragment("20260102-fix.json"); self.commit("other"); self.tag("v2.0.0")
        result = self.generate("v2.0.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no stable ancestor", result.stderr)

    def test_rejects_invalid_fragment_contracts(self):
        cases = [
            '{"category":"修复","category":"新增","summary":"新增一个符合长度要求的功能"}',
            '{"category":"其他","summary":"修复一个符合长度要求的问题"}',
            '{"category":"修复","summary":"plain english only"}',
            '{"category":"修复","summary":" 修复一个符合长度要求的问题"}',
            '{"category":"修复","summary":"修复包含 <b>标签</b> 的问题"}',
            '{"category":"修复","summary":"修复一个符合长度要求的问题","extra":1}',
        ]
        for index, source in enumerate(cases):
            with self.subTest(index=index):
                self.tearDown(); self.setUp()
                path = self.fragment("20260101-bad.json")
                path.write_text(source)
                self.commit("bad"); self.tag("v1.0.0")
                self.assertNotEqual(self.generate("v1.0.0").returncode, 0)


if __name__ == "__main__": unittest.main()
