import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "private_dot_local/private_bin/executable_llm-archive"
)


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.dest = self.root / "archive"
        self.month = self.dest / "2026/2026.11"
        self.env = dict(os.environ)

    def file(self, name, contents):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        return path

    def archive(self, *args):
        return subprocess.run(
            [
                "bash",
                str(SCRIPT),
                "-d",
                "2026-11-10",
                "-D",
                str(self.dest),
                *map(str, args),
            ],
            cwd=self.root,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
            timeout=10,
        )

    def fake_cp(self, body):
        command = self.file("bin/cp", "#!/bin/sh\n" + body + "\n")
        command.chmod(0o700)
        self.env["PATH"] = str(command.parent) + os.pathsep + self.env["PATH"]

    def test_copy_and_duplicate(self):
        first = self.file("input/scan.pdf", "document")
        same = self.file("input/copy.pdf", "document")
        result = self.archive(first, same)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "Copied: 1 | Duplicates: 1 | Skipped: 0 | Failed: 0", result.stderr
        )
        self.assertEqual((self.month / "scan.pdf").read_text(), "document")
        self.assertFalse((self.month / "copy.pdf").exists())

    def test_collision_keeps_both_sources_and_continues(self):
        first = self.file("a/scan.pdf", "first")
        second = self.file("b/scan.pdf", "second")
        third = self.file("b/other.pdf", "third")
        result = self.archive(first, second, third)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(
            "Copied: 2 | Duplicates: 0 | Skipped: 0 | Failed: 1", result.stderr
        )
        self.assertEqual((self.month / "scan.pdf").read_text(), "first")
        self.assertEqual((self.month / "other.pdf").read_text(), "third")
        self.assertEqual(first.read_text(), "first")
        self.assertEqual(second.read_text(), "second")

    def test_directory_mode_reports_collision(self):
        self.file("input/a/scan.pdf", "first")
        self.file("input/b/scan.pdf", "second")
        result = self.archive(self.root / "input")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(
            "Copied: 1 | Duplicates: 0 | Skipped: 0 | Failed: 1", result.stderr
        )

    def test_dry_run_reports_existing_collision(self):
        first = self.file("a/scan.pdf", "first")
        second = self.file("b/scan.pdf", "second")
        self.assertEqual(self.archive(first).returncode, 0)
        result = self.archive("--dry-run", second)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(
            "Copied: 0 | Duplicates: 0 | Skipped: 0 | Failed: 1", result.stderr
        )
        self.assertEqual((self.month / "scan.pdf").read_text(), "first")

    def test_copy_failure_is_not_counted(self):
        source = self.file("scan.pdf", "document")
        self.fake_cp("exit 1")
        result = self.archive(source)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(
            "Copied: 0 | Duplicates: 0 | Skipped: 0 | Failed: 1", result.stderr
        )

    def test_successful_cp_without_copy_is_not_counted(self):
        source = self.file("scan.pdf", "document")
        self.fake_cp("exit 0")
        result = self.archive(source)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(
            "Copied: 0 | Duplicates: 0 | Skipped: 0 | Failed: 1", result.stderr
        )

    def test_destination_appearing_during_copy_is_verified(self):
        source = self.file("scan.pdf", "document")
        self.fake_cp('printf different > "$3/scan.pdf"\nexit 0')
        result = self.archive(source)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(
            "Copied: 0 | Duplicates: 0 | Skipped: 0 | Failed: 1", result.stderr
        )
        self.assertEqual(source.read_text(), "document")
        self.assertEqual((self.month / "scan.pdf").read_text(), "different")


if __name__ == "__main__":
    unittest.main()
