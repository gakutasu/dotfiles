#!/usr/bin/env python3
"""Run one round of a Codex consultation in a locked-down, logged way.

  run.py new    --root DIR --topic SLUG --model M --effort E --cwd DIR --prompt-file F
  run.py resume --consult DIR --prompt-file F [--model M --effort E]
  run.py wait   --file OUTPUT [--max SECONDS]   # for a run that was moved to the background

Every round gets its own directory (<consult>/round-N/) holding prompt.md,
events.jsonl, stderr.txt, answer.md and result.json. The result is also
printed to stdout as JSON. Exit code: 0 on success, 1 on failure, 2 on misuse.
"""

import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

ALLOWED = {
    "gpt-6.1-sol": {"low", "medium", "high"},
    "gpt-6-astra": {"medium", "high"},
}
# Synced execpolicy rules may allow commands outside the sandbox, synced hooks
# inject Claude-side instructions, and apps / plugins / computer and browser use
# reach outside the command sandbox; none of them belong in a consultation.
DISABLED_FEATURES = [
    "hooks", "apps", "plugins", "computer_use", "browser_use", "browser_use_external",
    "browser_use_full_cdp_access", "in_app_browser", "multi_agent",
]
COMMON_FLAGS = [
    "--json",
    "--skip-git-repo-check",
    "--ignore-rules",
    "-c", 'approval_policy="never"',
    *[arg for feature in DISABLED_FEATURES for arg in ("--disable", feature)],
]
DEFAULT_TIMEOUT = 1800


def fail_usage(message):
    print(json.dumps({"status": "usage_error", "error": message}, ensure_ascii=False))
    sys.exit(2)


def check_model(model, effort):
    if model not in ALLOWED:
        fail_usage(f"model {model} is not allowed: {sorted(ALLOWED)}")
    if effort not in ALLOWED[model]:
        fail_usage(f"effort {effort} is not allowed for {model}: {sorted(ALLOWED[model])}")


def git_snapshot(cwd):
    def git(*args):
        proc = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, timeout=30)
        if proc.returncode != 0:
            raise RuntimeError(f"git {args[0]} failed: {proc.stderr.decode(errors='replace')[:200]}")
        return proc.stdout

    try:
        if subprocess.run(["git", "-C", str(cwd), "rev-parse", "--git-dir"],
                          capture_output=True, timeout=30).returncode != 0:
            return None
        head = git("rev-parse", "HEAD").decode().strip()
        digest = hashlib.sha256(git("diff", "HEAD", "--no-ext-diff", "--no-textconv", "--binary"))
        for name in git("ls-files", "-z", "--others", "--exclude-standard").split(b"\0"):
            if name:
                digest.update(b"\0" + name + b"\0")
                path = Path(cwd) / os.fsdecode(name)
                if path.is_file():
                    digest.update(path.read_bytes())
        return {"head": head, "worktree_sha256": digest.hexdigest()}
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as e:
        return {"error": str(e)}


def last_turn_event(events_file):
    """Return (last turn state, thread id). stdout is pure JSONL, so any line
    that is not a JSON object makes the state "malformed"."""
    last = None
    thread_id = None
    malformed = False
    with open(events_file, encoding="utf-8", errors="replace") as f:
        for line in f:
            if not line.strip():
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                malformed = True
                continue
            if not isinstance(event, dict):
                malformed = True
                continue
            kind = event.get("type", "")
            if kind == "thread.started" and thread_id is None:
                thread_id = event.get("thread_id")
            if kind == "turn.started":
                last = None
            elif kind in ("turn.completed", "turn.failed", "error"):
                last = kind
    return ("malformed" if malformed else last), thread_id


def kill_group(pgid, sig):
    try:
        os.killpg(pgid, sig)
    except ProcessLookupError:
        pass


def compare_snapshots(before, after):
    """True/False when both snapshots are usable, None when the version is unknown."""
    if before is None or after is None or "error" in before or "error" in after:
        return None
    return before != after


def run_round(consult, round_dir, cmd, cwd, prompt_file, timeout, meta):
    round_dir.mkdir()
    prompt_copy = round_dir / "prompt.md"
    shutil.copyfile(prompt_file, prompt_copy)
    answer = round_dir / "answer.md"
    events = round_dir / "events.jsonl"
    stderr = round_dir / "stderr.txt"
    cmd = [*cmd, "-o", str(answer), "-"]

    started = datetime.datetime.now().isoformat(timespec="seconds")
    before = git_snapshot(cwd)
    status = None
    error = None
    exit_code = None
    with open(prompt_copy, "rb") as fin, open(events, "wb") as fout, open(stderr, "wb") as ferr:
        try:
            # A new session lets a timeout kill codex together with its descendants.
            proc = subprocess.Popen(cmd, stdin=fin, stdout=fout, stderr=ferr, cwd=cwd,
                                    start_new_session=True)
            try:
                exit_code = proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                status = "timeout"
                kill_group(proc.pid, signal.SIGTERM)
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    pass
                # Descendants may ignore SIGTERM even after codex itself exits.
                kill_group(proc.pid, signal.SIGKILL)
                proc.wait()
        except OSError as e:
            status = "failed"
            error = f"could not start codex: {e}"
    after = git_snapshot(cwd)

    last_event, thread_id = last_turn_event(events)
    answered = answer.exists() and answer.stat().st_size > 0
    if status is None:
        status = "ok" if exit_code == 0 and last_event == "turn.completed" and answered else "failed"

    result = {
        "status": status,
        "consult": str(consult),
        "round": round_dir.name,
        "thread_id": thread_id or meta.get("thread_id"),
        "answer_file": str(answer) if answered else None,
        "exit_code": exit_code,
        "last_event": last_event,
        "model": meta["model"],
        "effort": meta["effort"],
        "started": started,
        "finished": datetime.datetime.now().isoformat(timespec="seconds"),
        "snapshot_before": before,
        "snapshot_after": after,
        "changed_during": compare_snapshots(before, after),
        "error": error,
        "stderr_tail": stderr.read_text(errors="replace")[-800:] if status != "ok" else "",
    }
    (round_dir / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
    return result


def cmd_new(args):
    check_model(args.model, args.effort)
    cwd = Path(args.cwd).resolve()
    if not cwd.is_dir():
        fail_usage(f"cwd {cwd} is not a directory")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", args.topic):
        fail_usage("topic must be an ASCII slug")
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    consult = Path(args.root).resolve() / f"{args.topic}-{stamp}-{os.getpid()}"
    consult.mkdir(parents=True)
    meta = {"topic": args.topic, "cwd": str(cwd), "model": args.model, "effort": args.effort,
            "thread_id": None, "history": []}

    cmd = ["codex", "exec", *COMMON_FLAGS, "-s", "read-only",
           "-m", args.model, "-c", f"model_reasoning_effort={args.effort}", "-C", str(cwd)]
    result = run_round(consult, consult / "round-1", cmd, cwd, args.prompt_file, args.timeout, meta)
    meta["thread_id"] = result["thread_id"]
    meta["history"].append({"round": "round-1", "model": args.model, "effort": args.effort,
                            "status": result["status"]})
    (consult / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2))
    return result


def cmd_resume(args):
    consult = Path(args.consult).resolve()
    meta_file = consult / "meta.json"
    if not meta_file.exists():
        fail_usage(f"{meta_file} not found")

    lock = consult / ".lock"
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        fail_usage(f"another round is running on {consult} (remove {lock} if it is stale)")
    os.close(fd)
    try:
        meta = json.loads(meta_file.read_text())
        if not meta.get("thread_id"):
            fail_usage("no thread_id recorded; start a new consultation instead")
        model = args.model or meta["model"]
        effort = args.effort or meta["effort"]
        check_model(model, effort)
        n = len(list(consult.glob("round-*"))) + 1
        meta["model"], meta["effort"] = model, effort
        # resume rejects -s and -C, so the sandbox goes through -c and cwd through the process.
        cmd = ["codex", "exec", "resume", meta["thread_id"], *COMMON_FLAGS,
               "-c", 'sandbox_mode="read-only"',
               "-m", model, "-c", f"model_reasoning_effort={effort}"]
        result = run_round(consult, consult / f"round-{n}", cmd, meta["cwd"], args.prompt_file,
                           args.timeout, meta)
        meta["history"].append({"round": f"round-{n}", "model": model, "effort": effort,
                                "status": result["status"]})
        meta_file.write_text(json.dumps(meta, ensure_ascii=False, indent=2))
    finally:
        lock.unlink(missing_ok=True)
    return result


def last_json(text):
    start = text.rfind("\n{")
    start = 0 if start < 0 else start + 1
    try:
        # raw_decode ignores trailers such as the harness's "[exited with code N]".
        return json.JSONDecoder().raw_decode(text[start:])[0]
    except json.JSONDecodeError:
        return None


def cmd_wait(args):
    """Block until a backgrounded run.py has printed its final JSON."""
    path = Path(args.file)
    deadline = time.monotonic() + args.max
    while time.monotonic() < deadline:
        if path.exists():
            text = path.read_text(errors="replace")
            result = last_json(text)
            if result and "status" in result:
                return result
            exited = re.search(r"\[exited with code (-?\d+)\]\s*$", text)
            if exited:
                return {"status": "failed", "error": f"run.py exited with code {exited.group(1)} "
                        "without a result", "file": str(path), "output_tail": text[-800:]}
        time.sleep(5)
    return {"status": "running", "file": str(path)}


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    wait = sub.add_parser("wait")
    wait.add_argument("--file", required=True)
    wait.add_argument("--max", type=int, default=570)

    new = sub.add_parser("new")
    new.add_argument("--root", required=True)
    new.add_argument("--topic", required=True)
    new.add_argument("--model", required=True)
    new.add_argument("--effort", required=True)
    new.add_argument("--cwd", required=True)
    new.add_argument("--prompt-file", required=True)
    new.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)

    resume = sub.add_parser("resume")
    resume.add_argument("--consult", required=True)
    resume.add_argument("--prompt-file", required=True)
    resume.add_argument("--model")
    resume.add_argument("--effort")
    resume.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)

    args = parser.parse_args()
    if args.command == "wait":
        result = cmd_wait(args)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        sys.exit(0 if result["status"] == "ok" else 1)
    if not Path(args.prompt_file).is_file() or Path(args.prompt_file).stat().st_size == 0:
        fail_usage(f"prompt file {args.prompt_file} is missing or empty")
    if shutil.which("codex") is None:
        print(json.dumps({"status": "failed", "error": "codex not found in PATH"}))
        sys.exit(1)

    try:
        result = cmd_new(args) if args.command == "new" else cmd_resume(args)
    except SystemExit:
        raise
    except Exception as e:
        result = {"status": "failed", "error": f"{type(e).__name__}: {e}"}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    sys.exit(0 if result["status"] == "ok" else 1)


if __name__ == "__main__":
    main()
