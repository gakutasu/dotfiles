#!/usr/bin/env python3
"""Prefix the session title with the folder the session was started in.

Every session is stored under one project directory (see
.config/environment.d/claude.conf), so the history list no longer tells which
folder a session belongs to. The title is the only place left to show it.

A title set by a hook counts as a rename and stops Claude Code from generating
one, so the prefix can only be added once the generated title exists. No hook
event reports that moment, hence the watcher.
"""

import fcntl
import json
import os
import subprocess
import sys
import tempfile
import time

OPEN, CLOSE = "【", "】"
WATCH_SECONDS = 120
WATCH_INTERVAL = 0.5


def folder_label(path):
    home = os.path.expanduser("~")
    path = os.path.normpath(path)
    if path == home:
        return "~"
    if path.startswith(home + os.sep):
        return path[len(home) + 1 :]
    return path


def read_titles(transcript):
    """Return the last (custom, ai) titles recorded in the transcript."""
    custom = ai = None
    try:
        with open(transcript, encoding="utf-8", errors="replace") as f:
            for line in f:
                if '"custom-title"' in line:
                    custom = _field(line, "customTitle") or custom
                elif '"ai-title"' in line:
                    ai = _field(line, "aiTitle") or ai
    except OSError:
        pass
    return custom, ai


def _field(line, key):
    try:
        return json.loads(line).get(key)
    except ValueError:
        return None


def append_custom_title(transcript, session_id, title):
    entry = json.dumps(
        {"type": "custom-title", "sessionId": session_id, "customTitle": title},
        ensure_ascii=False,
        separators=(",", ":"),
    )
    with open(transcript, "rb") as f:
        f.seek(0, os.SEEK_END)
        if f.tell() == 0:
            return
        f.seek(-1, os.SEEK_END)
        needs_newline = f.read(1) != b"\n"
    with open(transcript, "a", encoding="utf-8") as f:
        f.write(("\n" if needs_newline else "") + entry + "\n")


def prefix_generated_title(transcript, session_id, prefix):
    """Return True once the session has a custom title and needs no more work."""
    custom, ai = read_titles(transcript)
    if custom:
        return True
    if not ai:
        return False
    append_custom_title(transcript, session_id, prefix + ai)
    return True


def lock_session(session_id):
    """Return a held lock, or None while another process handles this session."""
    directory = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
    lock = open(os.path.join(directory, f"claude-title-{session_id}.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        lock.close()
        return None
    return lock


def unlock_session(lock):
    try:
        os.unlink(lock.name)
    except OSError:
        pass
    lock.close()


def watch(transcript, session_id, prefix):
    lock = lock_session(session_id)
    if not lock:
        return
    try:
        deadline = time.monotonic() + WATCH_SECONDS
        while not prefix_generated_title(transcript, session_id, prefix):
            if time.monotonic() >= deadline:
                break
            time.sleep(WATCH_INTERVAL)
    finally:
        unlock_session(lock)


def spawn_watcher(transcript, session_id, prefix):
    # Detached so that it outlives the hook, which has to return at once.
    subprocess.Popen(
        [sys.executable, os.path.abspath(__file__), "--watch", transcript, session_id, prefix],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def main():
    if sys.argv[1:2] == ["--watch"]:
        watch(*sys.argv[2:5])
        return

    data = json.load(sys.stdin)
    event = data.get("hook_event_name")
    transcript = data.get("transcript_path") or ""
    session_id = data.get("session_id") or ""
    prefix = OPEN + folder_label(os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or "") + CLOSE

    if event == "UserPromptSubmit":
        title = data.get("session_title")
        if title and title.startswith(OPEN):
            return
        if not title:
            custom, ai = read_titles(transcript)
            title = custom or ai
            # The title is generated in the background after this prompt.
            if not title:
                if transcript and session_id:
                    spawn_watcher(transcript, session_id, prefix)
                return
        if not title.startswith(OPEN):
            title = prefix + title
        print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "sessionTitle": title}}, ensure_ascii=False))

    elif event == "Stop":
        # Fallback for a title that appeared after the watcher gave up.
        lock = lock_session(session_id)
        if not lock:
            return
        try:
            prefix_generated_title(transcript, session_id, prefix)
        finally:
            unlock_session(lock)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Never block a prompt or a stop over a cosmetic title.
        pass
