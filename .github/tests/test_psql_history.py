import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[2]


class PsqlHistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.cache = self.home / ".cache"
        self.store = self.cache / "psql"
        self.store.mkdir(parents=True, mode=0o700)
        self.helper = self.home / ".local/bin/psql-history"
        self.helper.parent.mkdir(parents=True)
        shutil.copyfile(SOURCE / "private_dot_zshenv", self.home / ".zshenv")
        shutil.copyfile(
            SOURCE / "private_dot_local/private_bin/executable_psql-history",
            self.helper,
        )
        self.helper.chmod(0o700)
        self.env = dict(
            os.environ,
            HOME=str(self.home),
            ZDOTDIR=str(self.home),
            XDG_CACHE_HOME=str(self.cache),
            PSQL_HISTORY_DB="database",
        )
        self.bucket = int(time.time()) // 28800

    def run_helper(self, *args, database=None):
        env = dict(self.env)
        if database is not None:
            env["PSQL_HISTORY_DB"] = database
        return subprocess.run(
            ["zsh", str(self.helper), *map(str, args)],
            cwd=self.home,
            env=env,
            text=True,
            capture_output=True,
            check=False,
            timeout=10,
        )

    def history(self, bucket, database, contents):
        path = self.store / f"{bucket}-{database.encode().hex()}"
        path.write_text(contents)
        path.chmod(0o600)
        return path

    def test_reuses_current_window_and_separates_databases(self):
        first = self.run_helper()
        self.assertEqual(first.returncode, 0, first.stderr)
        path = Path(first.stdout.strip())
        path.write_text("select 1;\n")
        again = self.run_helper()
        other = self.run_helper(database="other database")
        self.assertEqual(first.stdout, again.stdout)
        self.assertNotEqual(first.stdout, other.stdout)
        self.assertEqual(path.read_text(), "select 1;\n")
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.store.stat().st_mode & 0o777, 0o700)

    def test_expiry_uses_window_not_file_mtime(self):
        expired = self.history(self.bucket - 1, "database", "old query\n")
        recent = self.history(self.bucket, "database", "recent query\n")
        os.utime(recent, (0, 0))
        result = self.run_helper("--expire")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(expired.exists())
        self.assertTrue(recent.exists())

    def test_expiry_removes_history_recreated_by_old_session(self):
        for _ in range(2):
            expired = self.history(self.bucket - 1, "database", "old query\n")
            result = self.run_helper("--expire")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(expired.exists())

    def test_legacy_history_is_retired(self):
        legacy = self.cache / "psql-history-database"
        legacy.write_text("undated query\n")
        legacy.chmod(0o600)
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(legacy.exists())

    def test_database_name_cannot_escape_or_execute(self):
        name = "../../test ' $(touch sentinel)\n"
        result = self.run_helper(database=name)
        self.assertEqual(result.returncode, 0, result.stderr)
        path = Path(result.stdout.strip())
        self.assertEqual(path.parent, self.store)
        self.assertEqual(path.name.split("-", 1)[1], name.encode().hex())
        self.assertFalse((self.home / "sentinel").exists())

    def test_symlink_history_is_rejected(self):
        target = self.home / "unrelated"
        target.write_text("keep")
        path = self.store / f"{self.bucket}-{b'database'.hex()}"
        path.symlink_to(target)
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(target.read_text(), "keep")

    def test_symlink_directory_is_rejected(self):
        self.store.rmdir()
        target = self.home / "unrelated"
        target.mkdir()
        self.store.symlink_to(target, target_is_directory=True)
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(list(target.iterdir()), [])

    def test_sourcing_only_defines_functions(self):
        result = subprocess.run(
            ["zsh", "-c", 'source "$1"; print ready', "_", str(self.helper)],
            cwd=self.home,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "ready\n")
        self.assertEqual(list(self.store.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
