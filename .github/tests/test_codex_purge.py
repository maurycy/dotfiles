"""Exercise the executable against a real WebSocket server on a Unix socket."""

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

from websockets.exceptions import ConnectionClosedError
from websockets.sync.server import unix_serve

SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "private_dot_local/private_bin/executable_codex-purge"
)


def thread(tid, **fields):
    return {
        "id": tid,
        "updatedAt": 1,
        "status": {"type": "notLoaded"},
        "ephemeral": False,
        **fields,
    }


class PurgeTests(unittest.TestCase):
    def run_purge(
        self,
        threads,
        *,
        apply=False,
        error=None,
        changes=None,
        rollouts=(),
        default_home=False,
        daemon_status="alreadyRunning",
    ):
        requests, deleted, api_errors = [], set(), []

        def respond(connection):
            initialized = False
            for raw in connection:
                request = json.loads(raw)
                requests.append(request)
                method, params = request["method"], request.get("params", {})
                if method == "initialized":
                    initialized = True
                    continue
                response = {"id": request["id"]}
                if method == error:
                    response["error"] = {"message": "test failure"}
                elif method == "initialize":
                    response["result"] = {}
                elif not initialized:
                    response["error"] = {"message": "initialize first"}
                elif method == "thread/list":
                    selected = [
                        t
                        for t in threads
                        if t["id"] not in deleted
                        and t.get("archived", False) == params["archived"]
                    ]
                    if "ancestorThreadId" in params:
                        selected = [
                            t
                            for t in selected
                            if params["ancestorThreadId"] in t.get("ancestors", [])
                        ]
                    else:
                        selected = [
                            t
                            for t in selected
                            if (params["archived"] or t.get("preview", "message"))
                            and t.get("source", "cli") in params["sourceKinds"]
                        ]
                    offset = int(params["cursor"] or 0)
                    response["result"] = {
                        "data": selected[offset : offset + 1],
                        "nextCursor": str(offset + 1)
                        if offset + 1 < len(selected)
                        else None,
                    }
                elif method == "thread/read":
                    current = next(
                        (t for t in threads if t["id"] == params["threadId"]), None
                    )
                    if current is None:
                        response["error"] = {"message": "thread not found"}
                    else:
                        response["result"] = {
                            "thread": {
                                **current,
                                **(changes or {}).get(current["id"], {}),
                            }
                        }
                elif method == "thread/delete":
                    tid = params["threadId"]
                    if tid in deleted:
                        response["error"] = {"message": "already deleted"}
                    else:
                        deleted.update(
                            t["id"]
                            for t in threads
                            if t["id"] == tid or tid in t.get("ancestors", [])
                        )
                        response["result"] = {}
                else:
                    response["error"] = {"message": "unexpected method"}
                if "error" in response:
                    api_errors.append(response["error"])
                connection.send(json.dumps({"method": "test/notification"}))
                connection.send(json.dumps(response))

        def handle(connection):
            try:
                respond(connection)
            except ConnectionClosedError:
                if not api_errors:
                    raise

        with tempfile.TemporaryDirectory(dir="/tmp", prefix="purge-test-") as tmp:
            sock = str(Path(tmp, "server.sock"))
            cli = Path(tmp, "codex")
            calls = Path(tmp, "daemon-calls")
            info = json.dumps({"status": daemon_status, "socketPath": sock})
            cli.write_text(
                f"#!{sys.executable}\nimport sys\n"
                "assert sys.argv[1:3] == ['app-server', 'daemon']\n"
                f"open({str(calls)!r}, 'a').write(sys.argv[3] + '\\n')\n"
                f"print({info!r} if sys.argv[3] == 'start' else '{{}}')\n"
            )
            cli.chmod(0o700)
            home = Path(tmp, "home")
            codex_home = home / ".codex" if default_home else Path(tmp, "custom-codex")
            for tid, archived in rollouts:
                directory = (
                    codex_home / "archived_sessions"
                    if archived
                    else codex_home / "sessions/2000/01/01"
                )
                directory.mkdir(parents=True, exist_ok=True)
                (directory / f"rollout-2000-01-01T00-00-00-{tid}.jsonl").write_text(
                    "{}\n"
                )
            env = dict(
                os.environ, HOME=str(home), PATH=tmp + os.pathsep + os.environ["PATH"]
            )
            if default_home:
                env.pop("CODEX_HOME", None)
            else:
                env["CODEX_HOME"] = str(codex_home)
            with unix_serve(handle, sock) as server:
                worker = threading.Thread(target=server.serve_forever)
                worker.start()
                try:
                    result = subprocess.run(
                        [sys.executable, str(SCRIPT), *(["--apply"] if apply else [])],
                        check=False,
                        env=env,
                        capture_output=True,
                        text=True,
                        timeout=10,
                    )
                finally:
                    server.shutdown()
                    worker.join(timeout=5)
            self.daemon_calls = calls.read_text().split() if calls.exists() else []
        return result, requests, deleted

    def test_preview_paginates_active_and_archived_without_deleting(self):
        result, requests, deleted = self.run_purge(
            [thread("a"), thread("b"), thread("c", archived=True)]
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("3 sessions eligible", result.stdout)
        self.assertFalse(deleted)
        self.assertTrue(any(r.get("params", {}).get("cursor") == "1" for r in requests))
        for r in requests:
            if r["method"] == "thread/list":
                self.assertTrue(r["params"]["useStateDbOnly"])
                self.assertIn("subAgentThreadSpawn", r["params"]["sourceKinds"])

    def test_monthly_apply_keeps_recent_open_and_ephemeral(self):
        now = datetime.now(timezone.utc).timestamp()
        entries = [
            thread("old", updatedAt=now - 60 * 86400),
            thread("recent", updatedAt=now - 20 * 86400),
            thread("loaded", status={"type": "idle"}),
            thread("active", status={"type": "active"}),
            thread("temporary", ephemeral=True),
        ]
        result, _, deleted = self.run_purge(entries, apply=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(deleted, {"old"})

    def test_empty_preview_rollout_is_discovered(self):
        tid = "00000000-0000-0000-0000-000000000001"
        for apply in (False, True):
            with self.subTest(apply=apply):
                result, _, deleted = self.run_purge(
                    [thread(tid, preview="")],
                    apply=apply,
                    rollouts=[(tid, False)],
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("codex-purge: 1 sessions", result.stdout)
                self.assertEqual(deleted, {tid} if apply else set())

    def test_hidden_archived_rollout_is_discovered(self):
        tid = "00000000-0000-0000-0000-000000000001"
        result, _, deleted = self.run_purge(
            [thread(tid, archived=True, source="futureSource")],
            apply=True,
            rollouts=[(tid, True)],
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(deleted, {tid})

    def test_default_codex_home_is_scanned(self):
        tid = "00000000-0000-0000-0000-000000000001"
        result, _, deleted = self.run_purge(
            [thread(tid, preview="")],
            apply=True,
            rollouts=[(tid, False)],
            default_home=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(deleted, {tid})

    def test_duplicate_rollouts_are_counted_once(self):
        tid = "00000000-0000-0000-0000-000000000001"
        result, requests, deleted = self.run_purge(
            [thread(tid, preview="")],
            apply=True,
            rollouts=[(tid, False), (tid, True)],
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(deleted, {tid})
        self.assertIn("codex-purge: 1 sessions deleted", result.stdout)
        self.assertEqual(sum(r["method"] == "thread/delete" for r in requests), 1)

    def test_hidden_rollouts_still_protect_recent_open_and_ephemeral(self):
        fields = [
            {"updatedAt": datetime.now(timezone.utc).timestamp()},
            {"status": {"type": "active"}},
            {"status": {"type": "idle"}},
            {"ephemeral": True},
        ]
        entries = [
            thread(f"00000000-0000-0000-0000-{i:012d}", preview="", **extra)
            for i, extra in enumerate(fields)
        ]
        result, requests, deleted = self.run_purge(
            entries, apply=True, rollouts=[(t["id"], False) for t in entries]
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(deleted)
        self.assertEqual(
            sum(r["method"] == "thread/read" for r in requests), len(entries)
        )

    def test_hidden_recent_child_protects_parent(self):
        parent = "00000000-0000-0000-0000-000000000001"
        child = "00000000-0000-0000-0000-000000000002"
        result, _, deleted = self.run_purge(
            [
                thread(parent, preview=""),
                thread(
                    child,
                    preview="",
                    ancestors=[parent],
                    updatedAt=datetime.now(timezone.utc).timestamp(),
                ),
            ],
            apply=True,
            rollouts=[(parent, False), (child, False)],
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(deleted)

    def test_unreadable_rollout_stops_before_any_deletion(self):
        result, _, deleted = self.run_purge(
            [thread("visible")],
            apply=True,
            rollouts=[("00000000-0000-0000-0000-000000000001", False)],
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("thread/read", result.stderr)
        self.assertFalse(deleted)

    def test_recent_archived_grandchild_protects_ancestors(self):
        entries = [
            thread("root"),
            thread("child", ancestors=["root"]),
            thread(
                "grandchild",
                ancestors=["root", "child"],
                archived=True,
                updatedAt=datetime.now(timezone.utc).timestamp(),
            ),
        ]
        result, _, deleted = self.run_purge(entries, apply=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(deleted)

    def test_child_before_parent_is_counted_once(self):
        entries = [thread("child", ancestors=["root"]), thread("root")]
        for apply in (False, True):
            with self.subTest(apply=apply):
                result, _, deleted = self.run_purge(entries, apply=apply)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("codex-purge: 2 sessions", result.stdout)
                self.assertEqual(deleted, {"root", "child"} if apply else set())

    def test_recheck_preserves_resumed_session(self):
        result, _, deleted = self.run_purge(
            [thread("root")],
            apply=True,
            changes={"root": {"status": {"type": "active"}}},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(deleted)

    def test_api_error_stops_cleanup(self):
        for method in ("thread/list", "thread/read", "thread/delete"):
            with self.subTest(method=method):
                result, _, deleted = self.run_purge(
                    [thread("a"), thread("b")], apply=True, error=method
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(method, result.stderr)
                self.assertFalse(deleted)

    def test_daemon_left_running_when_already_up(self):
        result, _, _ = self.run_purge([thread("a")])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.daemon_calls, ["start"])

    def test_daemon_started_here_is_stopped(self):
        result, _, _ = self.run_purge([thread("a")], daemon_status="started")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.daemon_calls, ["start", "stop"])

    def test_daemon_started_here_is_stopped_after_failure(self):
        result, _, _ = self.run_purge(
            [thread("a")], daemon_status="started", error="thread/list"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.daemon_calls, ["start", "stop"])

    def test_unexpected_daemon_status_fails(self):
        result, requests, _ = self.run_purge([thread("a")], daemon_status="stopped")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stopped", result.stderr)
        self.assertFalse(requests)
        self.assertEqual(self.daemon_calls, ["start"])

    def test_calendar_boundary(self):
        loader = importlib.machinery.SourceFileLoader("codex_purge", str(SCRIPT))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        with patch.object(sys, "dont_write_bytecode", True):
            loader.exec_module(module)
        for now, expected in [
            (
                datetime(2026, 3, 31, tzinfo=timezone.utc),
                datetime(2026, 2, 28, tzinfo=timezone.utc),
            ),
            (
                datetime(2024, 3, 31, tzinfo=timezone.utc),
                datetime(2024, 2, 29, tzinfo=timezone.utc),
            ),
            (
                datetime(2026, 1, 31, tzinfo=timezone.utc),
                datetime(2025, 12, 31, tzinfo=timezone.utc),
            ),
        ]:
            self.assertEqual(module.month_ago(now), expected.timestamp())


if __name__ == "__main__":
    unittest.main()
