#!/usr/bin/env python3
"""Move per-folder Claude Code history and memory into the shared project folder.

.config/environment.d/claude.conf makes Claude Code keep every session under
~/.claude/projects/<shared>. Whatever was written before that stays in
~/.claude/projects/<encoded cwd>, where it is no longer listed or loaded, so
this script brings it over:
  config   ~/.claude.json -> ~/.claude/.claude.json (copied when missing)
  memory   copied into <shared>/memory, indexed under a heading per folder
  sessions moved into <shared>, title prefixed with the folder they came from

claude.conf is read at login. Until then Claude Code keeps using the old
folders, and moving their contents away would hide the history from it. So
there are two modes:
  --prepare  setup: copy the config and say whether a reboot is still needed
  --hook     SessionStart hook (.claude/hooks/migrate_history.sh), with the
             hook input on stdin: move, but only when that session already
             keeps its transcript in the shared folder

Safe to re-run, also after a run that stopped halfway: a moved session is gone
from its old folder, a memory that is already in the shared folder is only
indexed if the index lacks it, and a merged memory folder is renamed to
memory.merged. Sessions still in use are left for the next run.

Output: one "<level>\t<message>" line per event (level: ok/skip/warn/relogin),
rendered by log_events in lib/common.sh.

Usage: claude_migrate.py <dotfiles_dir> <shared_project_name> --prepare|--hook
"""

import contextlib
import fcntl
import json
import os
import re
import shutil
import stat
import sys
import tempfile
import time
from pathlib import Path

if len(sys.argv) != 4 or sys.argv[3] not in ("--prepare", "--hook") or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", sys.argv[2]):
    # An empty name would make the projects folder itself the destination.
    sys.exit("usage: claude_migrate.py <dotfiles_dir> <shared_project_name> --prepare|--hook")
DOTFILES_DIR, SHARED_NAME, PREPARE = Path(sys.argv[1]), sys.argv[2], sys.argv[3] == "--prepare"

sys.dont_write_bytecode = True
sys.path.insert(0, str(DOTFILES_DIR / ".claude" / "hooks"))
import session_title_prefix as title  # noqa: E402

HOME = Path.home()
CLAUDE_HOME = HOME / ".claude"
PROJECTS = CLAUDE_HOME / "projects"
SHARED = PROJECTS / SHARED_NAME
OLD_CONFIG, CONFIG = HOME / ".claude.json", CLAUDE_HOME / ".claude.json"
IN_USE_SECONDS = 600
ENCODED_NAME_LIMIT = 200
LINK = re.compile(r"\(([^()]+)\)")
RELOGIN_REASON = "Claude Code の履歴とメモリの共通化（過去の履歴とメモリは、再起動後に Claude Code を開くと自動で共通フォルダへ移ります）"
MEMORY_NOTE = "見出しは、そのメモリを保存したときの作業フォルダ。別のフォルダで作業中は、該当する内容だけ使う。"


def log(level, msg):
    print(f"{level}\t{msg}", flush=True)


def read_json(path):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def read_lines(path):
    # Only a missing file counts as empty: an index that cannot be read must
    # stop the run before it gets rewritten.
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return []
    while lines and not lines[-1].strip():
        lines.pop()
    return lines


@contextlib.contextmanager
def replacing(path, make=tempfile.mkstemp):
    """Yield a temporary sibling that takes the place of path if the block succeeds."""
    made = make(dir=path.parent, prefix=path.name + ".")
    if isinstance(made, tuple):
        os.close(made[0])
        made = made[1]
    tmp = Path(made)
    try:
        yield tmp
        os.replace(tmp, path)
    except BaseException:
        if tmp.is_dir():
            shutil.rmtree(tmp, ignore_errors=True)
        else:
            tmp.unlink(missing_ok=True)
        raise


def write_atomic(path, text):
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    with replacing(path) as tmp:
        tmp.write_text(text, encoding="utf-8")
        tmp.chmod(mode)


def copy_new(src, dest):
    """Copy src to dest without ever replacing a file that shows up there meanwhile."""
    fd, tmp = tempfile.mkstemp(dir=dest.parent, prefix=dest.name + ".")
    os.close(fd)
    try:
        shutil.copy2(src, tmp)
        os.link(tmp, dest)
    finally:
        os.unlink(tmp)


def copytree_atomic(src, dest):
    with replacing(dest, tempfile.mkdtemp) as tmp:
        shutil.copytree(src, tmp, dirs_exist_ok=True)


def free_path(path):
    candidate, n = path, 2
    while candidate.exists():
        candidate = path.with_name(f"{path.stem}-{n}{path.suffix}")
        n += 1
    return candidate


def sharing_active():
    """Whether the caller's environment makes Claude Code use the shared folder.

    A shell is weak evidence, as its variables can differ from those of the
    Claude Code started from the desktop. It only decides whether setup asks
    for a reboot; the move also needs hook_session_shared.
    """
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    return (
        os.environ.get("CLAUDE_CODE_PROJECT_DIR_NAME") == SHARED_NAME
        and bool(config_dir)
        and Path(config_dir).resolve() == CLAUDE_HOME.resolve()
    )


def hook_session_shared():
    """Whether the session that ran the hook keeps its transcript in the shared folder.

    That Claude Code will still see the history after the move. It also keeps
    Codex out, which gets the same hook through codex_sync.py.
    """
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return False
    transcript = data.get("transcript_path") if isinstance(data, dict) else None
    if not isinstance(transcript, str) or not transcript.endswith(".jsonl"):
        return False
    return Path(transcript).parent.resolve() == SHARED.resolve()


def migrate_config():
    if CONFIG.exists() or not OLD_CONFIG.exists():
        return
    CLAUDE_HOME.mkdir(parents=True, exist_ok=True)
    try:
        copy_new(OLD_CONFIG, CONFIG)
    except FileExistsError:
        return
    log("ok", f"copied {OLD_CONFIG} to {CONFIG}")


def encode(path):
    """Name Claude Code gives the project folder of a working directory."""
    return re.sub(r"[^a-zA-Z0-9]", "-", path)


def is_project_of(name, path):
    encoded = encode(path)
    if len(encoded) <= ENCODED_NAME_LIMIT:
        return name == encoded
    # Long names are cut and given a hash suffix.
    return name.startswith(encoded[:ENCODED_NAME_LIMIT])


def session_cwd(jsonl):
    try:
        with open(jsonl, encoding="utf-8", errors="replace") as f:
            for line in f:
                if '"cwd"' not in line:
                    continue
                try:
                    cwd = json.loads(line).get("cwd")
                except (ValueError, AttributeError):
                    continue
                if cwd:
                    return cwd
    except OSError:
        pass
    return None


def project_path(old_dir):
    """Working directory an old project folder belongs to; its name is lossy."""
    for jsonl in sorted(old_dir.glob("*.jsonl")):
        cwd = session_cwd(jsonl)
        if cwd and is_project_of(old_dir.name, cwd):
            return cwd
    configured = {
        path
        for config in (OLD_CONFIG, CONFIG)
        for path in read_json(config).get("projects", {})
        if is_project_of(old_dir.name, path)
    }
    return configured.pop() if len(configured) == 1 else None


def memory_heading(path, old_dir):
    if not path:
        return old_dir.name
    label = title.folder_label(path)
    if label == "~":
        return "~（ホーム）"
    return label if os.path.isabs(label) else "~/" + label


def merged_copy(memory, target):
    """Return the copy of memory already in the shared folder, if any."""
    variant = re.compile(re.escape(target.stem) + r"-\d+" + re.escape(target.suffix))
    candidates = [target, *sorted(p for p in target.parent.iterdir() if variant.fullmatch(p.name))]
    data = memory.read_bytes()
    return next((p for p in candidates if p.is_file() and p.read_bytes() == data), None)


def named_elsewhere(name, old_dir, old_dirs):
    """Whether another old project folder has, or had, a memory of this name."""
    return any(
        (memory / name).exists() for other in old_dirs if other != old_dir for memory in other.glob("memory*")
    )


def copy_memories(old_dir, dest, old_dirs):
    """Copy the memories over. Return {old name: new name} and the names left out."""
    names, left_out = {}, set()
    src = old_dir / "memory"
    for item in sorted(src.iterdir()):
        if item.name == "MEMORY.md":
            continue
        target = dest / item.name
        if item.is_dir():
            if target.exists():
                log("warn", f"kept {target}, not merged with {item}")
            else:
                copytree_atomic(item, target)
            continue
        copy = merged_copy(item, target)
        if not copy:
            # When no other folder uses the name, a differing file is this
            # memory, edited after an earlier merge. Otherwise it is another
            # folder's memory and this one goes in under a numbered name.
            if target.exists() and not named_elsewhere(item.name, old_dir, old_dirs):
                log("warn", f"kept {target}, which differs from {item}")
                left_out.add(item.name)
                continue
            copy = free_path(target)
            copy_new(item, copy)
        names[item.name] = copy.name
    return names, left_out


def index_entries(old_index, shared_index, names, left_out):
    """Lines of the old index that the shared index still lacks."""
    indexed = "\n".join(shared_index)
    entries, mentioned = [], set()
    for line in old_index:
        if not line.strip() or line.startswith("#"):
            continue
        targets = LINK.findall(line)
        if any(name in left_out for name in targets):
            continue
        linked = [name for name in targets if name in names]
        mentioned.update(linked)
        line = LINK.sub(lambda m: f"({names.get(m.group(1), m.group(1))})", line)
        if line in shared_index or (linked and all(f"({names[name]})" in indexed for name in linked)):
            continue
        entries.append(line)
    for name, new_name in names.items():
        if name.endswith(".md") and name not in mentioned and f"({new_name})" not in indexed:
            entries.append(f"- [{Path(new_name).stem}]({new_name})")
    return entries


def add_index_entries(index, heading, entries):
    lines = read_lines(index) or [MEMORY_NOTE]
    header = f"## {heading}"
    if header in lines:
        end = lines.index(header) + 1
        while end < len(lines) and not lines[end].startswith("## "):
            end += 1
        while not lines[end - 1].strip():
            end -= 1
        lines[end:end] = entries
    else:
        lines += ["", header, *entries]
    write_atomic(index, "\n".join(lines) + "\n")


def merge_memory(old_dir, heading, old_dirs):
    src = old_dir / "memory"
    if not src.is_dir():
        return
    dest = SHARED / "memory"
    dest.mkdir(parents=True, exist_ok=True)
    index = dest / "MEMORY.md"
    names, left_out = copy_memories(old_dir, dest, old_dirs)
    entries = index_entries(read_lines(src / "MEMORY.md"), read_lines(index), names, left_out)
    if entries:
        add_index_entries(index, heading, entries)
        log("ok", f"merged {len(entries)} memory entries from {old_dir.name} under '{heading}'")
    src.rename(free_path(old_dir / "memory.merged"))


def pid_domain():
    try:
        machine = Path("/etc/machine-id").read_text().strip()
        return f"linux:{machine}:{os.readlink('/proc/self/ns/pid')}"
    except OSError:
        return None


def live_sessions():
    """Session ids held by a Claude Code process that may still be running."""
    live = set()
    domain = pid_domain()
    for record in (CLAUDE_HOME / "sessions").glob("*.json"):
        data = read_json(record)
        session_id = data.get("sessionId")
        if not session_id:
            continue
        # A pid from another pid namespace or machine cannot be probed here.
        if data.get("pidDomain") and data["pidDomain"] != domain:
            live.add(session_id)
            continue
        try:
            os.kill(int(data.get("pid")), 0)
        except (TypeError, ValueError, ProcessLookupError):
            continue
        except PermissionError:
            pass
        live.add(session_id)
    return live


def last_modified(jsonl, side_dir):
    paths = [jsonl]
    if side_dir.is_dir():
        paths += [p for p in side_dir.rglob("*") if p.is_file()]
    return max(p.stat().st_mtime for p in paths)


def prefix_title(jsonl, side_dir, session_id, folder):
    custom, ai = title.read_titles(jsonl)
    current = custom or ai
    if not current:
        return
    if not current.startswith(title.OPEN):
        custom = title.OPEN + title.folder_label(folder) + title.CLOSE + current
        # The history list is ordered by modification time.
        before = jsonl.stat()
        title.append_custom_title(jsonl, session_id, custom)
        with contextlib.suppress(OSError):
            os.utime(jsonl, ns=(before.st_atime_ns, before.st_mtime_ns))
    # Checked on its own so that a run stopped after the append still fixes it.
    sidecar = side_dir / "custom-title.json"
    if custom and custom.startswith(title.OPEN) and sidecar.exists() and read_json(sidecar).get("customTitle") != custom:
        write_atomic(sidecar, json.dumps({"customTitle": custom}, ensure_ascii=False, separators=(",", ":")))


def recover_side_dirs(old_dir):
    """Finish a move that stopped between a session file and its folder."""
    for side_dir in sorted(p for p in old_dir.iterdir() if p.is_dir()):
        jsonl = f"{side_dir.name}.jsonl"
        target = SHARED / side_dir.name
        if not (SHARED / jsonl).exists() or (old_dir / jsonl).exists() or target.exists():
            continue
        if side_dir.name not in live_sessions():
            shutil.move(side_dir, target)


def move_sessions(old_dir, path):
    recover_side_dirs(old_dir)
    moved = in_use = 0
    for jsonl in sorted(old_dir.glob("*.jsonl")):
        session_id = jsonl.stem
        side_dir = old_dir / session_id
        # The session file is appended to by path, so moving one that is still
        # open would split it in two.
        if session_id in live_sessions() or time.time() - last_modified(jsonl, side_dir) < IN_USE_SECONDS:
            in_use += 1
            continue
        target, side_target = SHARED / jsonl.name, SHARED / session_id
        if target.exists() or side_target.exists():
            log("warn", f"left {jsonl} in place, {target} already exists")
            continue
        prefix_title(jsonl, side_dir, session_id, session_cwd(jsonl) or path or old_dir.name)
        shutil.move(jsonl, target)
        if side_dir.is_dir():
            shutil.move(side_dir, side_target)
        moved += 1
    if moved:
        log("ok", f"moved {moved} sessions from {old_dir.name}")
    if in_use:
        log("skip", f"{in_use} sessions in {old_dir.name} are in use, re-run later to move them")


def main():
    old_dirs = sorted(d for d in PROJECTS.iterdir() if d.is_dir() and d.name != SHARED_NAME) if PROJECTS.is_dir() else []
    leftovers = any(not p.name.startswith("memory.merged") for d in old_dirs for p in d.iterdir())
    if PREPARE:
        # Copied ahead of the login, or Claude Code would start it without a config.
        migrate_config()
        if not sharing_active():
            log("relogin", RELOGIN_REASON)
        elif leftovers:
            log("skip", "history and memory will be moved when Claude Code next starts")
        return
    if not leftovers or not sharing_active() or not hook_session_shared():
        return
    lock = os.open(PROJECTS, os.O_RDONLY)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        log("skip", "another migration is running")
        return
    SHARED.mkdir(parents=True, exist_ok=True)
    for old_dir in old_dirs:
        path = project_path(old_dir)
        merge_memory(old_dir, memory_heading(path, old_dir), old_dirs)
        move_sessions(old_dir, path)


if __name__ == "__main__":
    main()
