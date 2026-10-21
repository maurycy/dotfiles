"""Behavioral checks using temporary homes, fake documents, and offline tools."""

import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import time
import unittest
from concurrent.futures import ThreadPoolExecutor


REPO = Path(__file__).resolve().parents[1]
BIN = REPO / "private_dot_local/private_bin"
ZSH = shutil.which("zsh")


class Shell:
    def __init__(self, env, cwd):
        self.master, slave = pty.openpty()
        self.proc = subprocess.Popen(
            [ZSH, "-di"], stdin=slave, stdout=slave, stderr=slave,
            env=env, cwd=cwd, close_fds=True,
        )
        os.close(slave)
        self.read_prompt()

    def read_prompt(self):
        data = b""
        deadline = time.monotonic() + 10
        while b"REVIEW_PROMPT> " not in data:
            if time.monotonic() > deadline:
                raise AssertionError(f"shell prompt timeout: {data!r}")
            if select.select([self.master], [], [], 0.1)[0]:
                data += os.read(self.master, 65536)
        return data.decode(errors="replace")

    def send(self, command):
        os.write(self.master, command.encode() + b"\n")
        return self.read_prompt()

    def close(self):
        if self.master is None:
            return
        if self.proc.poll() is None:
            os.write(self.master, b"exit\n")
            deadline = time.monotonic() + 10
            # Drain the PTY while the shell exits; waiting without a reader
            # can block terminal teardown on macOS.
            while self.proc.poll() is None and time.monotonic() < deadline:
                if select.select([self.master], [], [], 0.1)[0]:
                    try:
                        os.read(self.master, 65536)
                    except OSError:
                        break
            if self.proc.poll() is None:
                try:
                    self.proc.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    self.proc.kill()
                    self.proc.wait()
            if self.proc.returncode != 0:
                code = self.proc.returncode
                os.close(self.master)
                self.master = None
                raise AssertionError(f"shell failed to exit normally: {code}")
        os.close(self.master)
        self.master = None


class Hardening(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dotfiles-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir(mode=0o700)
        self.bin = self.home / ".local/bin"
        self.bin.mkdir(parents=True, mode=0o700)
        self.record = self.root / "record"
        self.env = {
            "HOME": str(self.home), "ZDOTDIR": str(self.home),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_CACHE_HOME": str(self.home / ".cache"),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
            "PATH": str(self.bin) + ":/usr/bin:/bin:/usr/sbin:/sbin",
            "SHELL": ZSH, "TERM": "dumb", "LC_ALL": "C",
            "REPO": str(REPO), "RECORD": str(self.record),
        }
        for name in ("rg", "jq"):
            tool = shutil.which(name)
            if tool:
                (self.bin / name).symlink_to(tool)
        shutil.copyfile(BIN / "executable_prm", self.bin / "prm")
        (self.bin / "prm").chmod(0o700)
        shutil.copyfile(REPO / "private_dot_zshenv", self.home / ".zshenv")
        (self.home / ".zshenv").chmod(0o600)
        if not shutil.which("sha256sum", path=self.env["PATH"]):
            self.stub("sha256sum", 'exec /usr/bin/shasum -a 256 "$@"')

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o700)
        return path

    def run_command(self, args, *, check=True):
        result = subprocess.run(args, cwd=self.root, env=self.env,
                                capture_output=True, text=True, timeout=20)
        if check:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def zsh(self, script, *, interactive=False, check=True):
        return self.run_command([ZSH, "-dfic" if interactive else "-dfc", script], check=check)

    def file(self, name, text="fixture\n", mode=0o600):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        path.chmod(mode)
        return path

    def test_source_rejects_writable_and_symlinked_parents(self):
        path = self.file("home/loose/init.zsh", ":\n")
        path.parent.chmod(0o777)
        (self.home / "link").symlink_to(path.parent, target_is_directory=True)
        self.zsh('source "$REPO/private_dot_zshenv"; '
                 '! _is_safe_source "$HOME/loose/init.zsh" && '
                 '! _is_safe_source "$HOME/link/init.zsh" && '
                 '! _is_safe_dir "$HOME/loose"')
        path.parent.chmod(0o700)
        self.zsh('source "$REPO/private_dot_zshenv"; '
                 '_is_safe_source "$HOME/loose/init.zsh" && '
                 '! _is_safe_source "$HOME/link/init.zsh"; '
                 'local -i value=18; [[ $value == 18 ]]')

    def test_source_rejects_unsafe_compiled_companion(self):
        path = self.file("home/init.zsh", ":\n")
        self.file("home/init.zsh.zwc", "fake compiled file", 0o666)
        self.zsh('source "$REPO/private_dot_zshenv"; '
                 '! _is_safe_source "$HOME/init.zsh"')

    def test_source_rejects_symlink_before_parent_traversal(self):
        self.file("loose/init.zsh", ":\n")
        (self.root / "loose/nested").mkdir()
        (self.root / "loose").chmod(0o777)
        (self.home / "link").symlink_to(self.root / "loose/nested", target_is_directory=True)
        self.zsh('source "$REPO/private_dot_zshenv"; '
                 '! _is_safe_source "$HOME/link/../init.zsh"')

    def test_cache_does_not_follow_symlinked_directory(self):
        outside = self.root / "outside"
        outside.mkdir()
        (self.home / "cache").symlink_to(outside, target_is_directory=True)
        self.zsh('source "$REPO/private_dot_zshenv"; '
                 '! _cache_file "$HOME/cache/init.zsh" "" print -r -- malicious')
        self.assertEqual(list(outside.iterdir()), [])

    def test_compinit_never_loads_rejected_dump(self):
        self.zsh('autoload -Uz compinit; compinit')
        dump = self.home / ".zcompdump"
        with dump.open("a") as stream:
            stream.write('\nprint EXECUTED > "$HOME/marker"\n')
        dump.chmod(0o666)
        text = (REPO / "private_dot_zshrc.tmpl").read_text()
        function = text[text.index("_compinit_real() {"):text.index("\nautoload -U select-word-style")]
        self.file("compinit.zsh", function)
        self.zsh('source "$REPO/private_dot_zshenv"; '
                 'typeset -a _compdef_queue _post_compinit_hooks; '
                 'source ./compinit.zsh; _compinit_real')
        self.assertFalse((self.home / "marker").exists())

    def setup_notes(self):
        notes = self.root / "notes'quoted"
        notes.mkdir()
        self.env["NOTES_DIR"] = str(notes)
        self.stub("fzf", "tail -n 1")
        self.env["EDITOR"] = str(self.stub("editor", 'printf "%s\\n" "$@" > "$RECORD"'))
        return notes

    def test_notes_treats_colons_as_filename_data(self):
        notes = self.setup_notes()
        name = "evil:!touch NOTES_EXECUTED:.md"
        (notes / name).write_text("uniqueneedle\n")
        self.zsh('source "$REPO/.chezmoitemplates/notes.zsh"; _notes_search uniqueneedle')
        args = self.record.read_text().splitlines()
        self.assertEqual(args[:2], ["+1", "--"])
        self.assertEqual(Path(args[2]).resolve(), notes / name)
        self.assertFalse((self.root / "NOTES_EXECUTED").exists())

    def test_notes_rejects_ambiguous_search_filename(self):
        notes = self.setup_notes()
        (notes / "bad\t!touch NOTES_EXECUTED\t.md").write_text("uniqueneedle\n")
        self.zsh('source "$REPO/.chezmoitemplates/notes.zsh"; '
                 '! _notes_search uniqueneedle')
        self.assertFalse(self.record.exists())

    def test_pdf_worker_preserves_literal_output_path(self):
        self.stub("qpdf", 'if [ "$1" = --show-npages ]; then echo 1; '
                  'else for arg do last=$arg; done; printf "page\\n" > "$last"; fi')
        self.file("pdfs/input.pdf")
        out = '$(touch PDF_EXECUTED) "quoted"'
        self.run_command(["/bin/sh", str(BIN / "executable_pdf-split"),
                          "--parallel", "2", "--outdir", out, "pdfs"])
        self.assertFalse((self.root / "PDF_EXECUTED").exists())
        self.assertTrue((self.root / out / "page_01.pdf").is_file())

    def setup_ocr(self, fail=False):
        self.stub("uvx", 'printf "%s\\n" "$@" >> "$RECORD"; '
                  'printf "fake OCR response\\n"; ' + ("exit 1" if fail else "exit 0"))
        return self.file("document.png")

    def test_ocr_output_is_private_and_logging_is_disabled(self):
        fixture = self.setup_ocr()
        self.run_command(["/bin/sh", "-c", 'umask 022; exec /bin/sh "$1" "$2"',
                          "test", str(BIN / "executable_llm-ocr"), str(fixture)])
        outputs = list(self.root.glob("document.*.txt"))
        self.assertEqual(len(outputs), 1)
        self.assertEqual(outputs[0].stat().st_mode & 0o777, 0o600)
        self.assertIn("--no-log", self.record.read_text().splitlines())
        self.assertFalse(list(self.root.glob("*.tmp.*")))

    def test_failed_ocr_removes_partial_output(self):
        fixture = self.setup_ocr(fail=True)
        self.run_command(["/bin/sh", str(BIN / "executable_llm-ocr"), str(fixture)], check=False)
        self.assertFalse(list(self.root.glob("document.*.txt")))
        self.assertFalse(list(self.root.glob("*.tmp.*")))

    def test_rename_worker_preserves_literal_model_and_disables_logging(self):
        self.stub("qpdf", 'if [ "$1" = --show-npages ]; then echo 1; '
                  'else for arg do last=$arg; done; printf "excerpt\\n" > "$last"; fi')
        self.stub("file", 'echo application/pdf')
        self.stub("uvx", 'printf "%s\\n" "$@" >> "$RECORD"; '
                  'printf \'{"date":"2020-01-01","description":"fixture"}\\n\'')
        self.file("pdfs/document.pdf")
        model = '$(touch RENAME_EXECUTED) "model"'
        self.run_command(["/bin/sh", str(BIN / "executable_llm-rename"),
                          "--parallel", "2", "--model", model, "--dry-run", "pdfs"])
        self.assertFalse((self.root / "RENAME_EXECUTED").exists())
        args = self.record.read_text().splitlines()
        self.assertIn(model, args)
        self.assertIn("--no-log", args)

    def test_prm_only_deletes_named_file(self):
        target = self.file("target")
        twin = self.file("identical")
        self.stub("shred", 'printf "%s\\n" "$@" > "$RECORD"; '
                  'for arg do last=$arg; done; rm -f -- "$last"')
        self.run_command([str(self.bin / "prm"), "--files-only", "--", str(target)])
        self.assertFalse(target.exists())
        self.assertTrue(twin.exists())
        self.assertEqual(self.record.read_text().splitlines()[-1], str(target))

    def test_prm_does_not_overwrite_symlink_or_hardlink_target(self):
        target = self.file("target")
        hard = self.root / "hard"
        os.link(target, hard)
        link = self.root / "link"
        link.symlink_to(target)
        self.stub("shred", 'echo UNEXPECTED > "$RECORD"; exit 1')
        self.run_command([str(self.bin / "prm"), "--files-only", "--", str(link), str(hard)])
        self.assertEqual(target.read_text(), "fixture\n")
        self.assertFalse(self.record.exists())

    def test_prm_falls_back_to_rm_and_handles_option_like_names(self):
        target = self.file("-n")
        self.stub("shred", "exit 1")
        self.run_command([str(self.bin / "prm"), "--files-only", "--", "-n"])
        self.assertFalse(target.exists())

    def test_prm_dry_run_keeps_files(self):
        target = self.file("target")
        self.stub("shred", 'echo UNEXPECTED > "$RECORD"; exit 1')
        self.run_command([str(self.bin / "prm"), "--dry", "--files-only", "--", str(target)])
        self.assertTrue(target.exists())
        self.assertFalse(self.record.exists())

    def test_prm_empty_cleanup_is_a_noop(self):
        self.run_command([str(self.bin / "prm"), "--files-only", "--"])

    def history_shell(self):
        rc = ('source "$REPO/.chezmoitemplates/history.zsh"\n'
              'PS1="REVIEW_PROMPT> "\nRPROMPT=\n')
        (self.home / ".zshrc").write_text(rc)
        shell = Shell(self.env, self.root)
        self.addCleanup(shell.close)
        return shell

    def test_history_expires_entries_and_preserves_multiline_records(self):
        now = int(time.time())
        history = self.file("home/.zsh_history",
                            f": {now - 9 * 3600}:0;expired command\n"
                            "expired continuation\n"
                            f": {now - 60}:0;recent command\\\n"
                            ": 1:0;continuation that looks like a timestamp\n")
        shell = self.history_shell()
        text = history.read_text()
        self.assertNotIn("expired", text)
        self.assertIn("recent command", text)
        self.assertIn("continuation that looks like a timestamp", text)
        self.assertEqual(history.stat().st_mode & 0o777, 0o600)

    def test_two_shells_do_not_restore_expired_history_on_exit(self):
        now = int(time.time())
        history = self.file("home/.zsh_history", f": {now}:0;stale_marker\n")
        first = self.history_shell()
        history.write_text(f": {now - 9 * 3600}:0;stale_marker\n")
        os.utime(history, (now - 1, now - 1))
        second = self.history_shell()
        first.send("echo shell_one_marker")
        second.send("echo shell_two_marker")
        first.send("TOKEN=fake_sensitive_marker")
        first.send("true")
        first.close()
        second.close()
        text = history.read_text()
        self.assertNotIn("stale_marker", text)
        self.assertNotIn("fake_sensitive_marker", text)
        self.assertIn("shell_one_marker", text)
        self.assertIn("shell_two_marker", text)

    def test_history_expires_at_prompt_after_cached_deadline(self):
        now = int(time.time())
        history = self.file("home/.zsh_history", f": {now - 8 * 3600}:0;due_marker\n")
        shell = self.history_shell()
        # Cross the real expiry boundary without an eight-hour test delay.
        time.sleep(1.1)
        shell.send("true")
        self.assertNotIn("due_marker", history.read_text())

    def test_history_does_not_follow_symlinks(self):
        target = self.file("external_history", "private external data\n")
        (self.home / ".zsh_history").symlink_to(target)
        shell = self.history_shell()
        shell.send("echo local_command")
        shell.close()
        self.assertEqual(target.read_text(), "private external data\n")

    def test_concurrent_history_writers_keep_both_commands(self):
        first = self.history_shell()
        second = self.history_shell()
        with ThreadPoolExecutor(max_workers=2) as pool:
            one = pool.submit(first.send, "echo concurrent_one_marker")
            two = pool.submit(second.send, "echo concurrent_two_marker")
            one.result(timeout=15)
            two.result(timeout=15)
        first.close()
        second.close()
        text = (self.home / ".zsh_history").read_text()
        self.assertEqual(text.count("echo concurrent_one_marker"), 1)
        self.assertEqual(text.count("echo concurrent_two_marker"), 1)

    def test_ssh_disables_master_reuse_and_limits_agent_lifetime(self):
        # Exclude encrypted host overrides and the machine's SSH configuration.
        config = self.file("ssh_config", (REPO / "private_dot_ssh/private_config").read_text()
                           .replace("Include config.d/*", ""))
        result = self.run_command(["ssh", "-G", "-F", str(config), "test.invalid"])
        values = dict(line.split(" ", 1) for line in result.stdout.splitlines())
        self.assertEqual(values["controlmaster"], "false")
        self.assertNotIn("controlpath", values)
        self.assertEqual(values["forwardagent"], "no")
        self.assertEqual(values["addkeystoagent"], "3600")


if __name__ == "__main__":
    unittest.main()
