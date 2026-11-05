#!/usr/bin/env python3
"""Mirror the Claude Code setup into Codex (one way: Claude -> Codex).

Regenerated from the current Claude state on every run:
  skills  -> ~/.agents/skills/<name>   (symlinks; plugin commands become generated skills)
  hooks   -> ~/.codex/hooks.json       (settings.json hooks + enabled plugin hooks)
  rules   -> ~/.codex/rules/claude.rules (Bash(...) permissions as prefix_rule)
  plugins -> native Codex plugins for the ones listed in NATIVE_PLUGINS

Everything this script creates is recorded in a manifest, so entries whose
Claude source disappeared are removed on the next run, and entries it did not
create are never touched.

Output: one "<level>\t<message>" line per event (level: ok/link/move/skip/warn),
rendered by modules/codex.sh.

Usage: codex_sync.py <dotfiles_dir>
"""

import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
CLAUDE_HOME = HOME / ".claude"
CODEX_HOME = Path(os.environ.get("CODEX_HOME", HOME / ".codex"))
AGENTS_SKILLS = HOME / ".agents" / "skills"
LEGACY_CODEX_SKILLS = CODEX_HOME / "skills"
HOOKS_FILE = CODEX_HOME / "hooks.json"
RULES_FILE = CODEX_HOME / "rules" / "claude.rules"
MANIFEST = CODEX_HOME / "claude-sync.json"
INSTALLED_PLUGINS = CLAUDE_HOME / "plugins" / "installed_plugins.json"

# Claude plugin -> Codex plugin installed natively instead of being converted.
NATIVE_PLUGINS = {
    "superpowers@superpowers-marketplace": "superpowers@openai-curated-remote",
}
# Claude plugins that make no sense inside Codex.
EXCLUDED_PLUGINS = {
    "codex@openai-codex",  # bridge from Claude Code to Codex itself
}
# Dotfiles skill directories that are not skills.
EXCLUDED_DOTFILES_SKILLS = {"synced"}

CODEX_HOOK_EVENTS = {
    "SessionStart", "SessionEnd", "SubagentStart", "SubagentStop",
    "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse",
    "PreCompact", "PostCompact", "Stop", "Interrupt",
}
CODEX_HANDLER_KEYS = {"type", "command", "timeout", "async", "statusMessage"}
DROPPED_HANDLER_KEYS = {"shell", "powershell"}

GENERATED_MARKER = ".claude-sync-generated"


def emit(level, msg):
    print(f"{level}\t{msg}", flush=True)


def load_json(path, default):
    try:
        return json.loads(Path(path).read_text())
    except FileNotFoundError:
        return default
    except (OSError, json.JSONDecodeError) as exc:
        emit("warn", f"cannot read {path}: {exc}")
        return default


def backup(path):
    dest = Path(f"{path}.backup.{time.strftime('%Y%m%d-%H%M%S')}")
    path.rename(dest)
    emit("move", f"existing {path} => {dest}")


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


# --- Sources ---------------------------------------------------------------

class Plugin:
    def __init__(self, plugin_id, root):
        self.id = plugin_id
        self.root = Path(root)
        self.manifest = load_json(self.root / ".claude-plugin" / "plugin.json", {})

    def paths(self, key, default):
        value = self.manifest.get(key, default)
        values = value if isinstance(value, list) else [value]
        return [self.root / v for v in values if isinstance(v, str)]


def enabled_plugins(settings):
    installed = load_json(INSTALLED_PLUGINS, {}).get("plugins", {})
    for plugin_id, enabled in settings.get("enabledPlugins", {}).items():
        if not enabled:
            continue
        entries = installed.get(plugin_id, [])
        entry = next((e for e in entries if e.get("scope") == "user"), None)
        entry = entry or (entries[0] if entries else None)
        if not entry or not Path(entry.get("installPath", "")).is_dir():
            emit("warn", f"plugin {plugin_id} is enabled but not installed; run: sh setup.sh claude")
            continue
        yield Plugin(plugin_id, entry["installPath"])


# --- Skills ----------------------------------------------------------------

def parse_frontmatter(text):
    match = re.match(r"^---\n(.*?)\n---\n?(.*)$", text, re.S)
    if not match:
        return {}, text
    meta = {}
    for line in match.group(1).splitlines():
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if m:
            meta[m.group(1)] = m.group(2).strip().strip("\"'")
    return meta, match.group(2)


def command_to_skill(name, path):
    meta, body = parse_frontmatter(path.read_text())
    description = meta.get("description") or f"Claude Code command /{name}"
    if meta.get("argument-hint"):
        description += f" (arguments: {meta['argument-hint']})"
    note = ""
    if "$ARGUMENTS" in body or re.search(r"\$\d", body):
        note = ("$ARGUMENTS (and $1, $2, ...) below stand for the arguments "
                "the user gave with this request.\n\n")
    return (f"---\nname: {json.dumps(name, ensure_ascii=False)}\n"
            f"description: {json.dumps(description, ensure_ascii=False)}\n---\n\n"
            f"{note}{body.lstrip()}")


def collect_skills(dotfiles, plugins):
    """name -> ("link", target) or ("generate", SKILL.md text)."""
    skills = {}

    def add(name, spec, origin):
        if name in skills:
            emit("warn", f"skill {name} from {origin} skipped: name already taken by {skills[name][2]}")
            return
        skills[name] = (*spec, origin)

    for skill in sorted((dotfiles / ".claude" / "skills").glob("*/SKILL.md")):
        name = skill.parent.name
        if name not in EXCLUDED_DOTFILES_SKILLS:
            add(name, ("link", skill.parent), "dotfiles")

    for plugin in plugins:
        for base in plugin.paths("skills", "skills"):
            dirs = [base] if (base / "SKILL.md").is_file() else sorted(base.glob("*/"))
            for d in dirs:
                if (d / "SKILL.md").is_file():
                    add(d.name, ("link", d), plugin.id)
        for base in plugin.paths("commands", "commands"):
            files = [base] if base.is_file() else sorted(base.rglob("*.md"))
            for f in files:
                rel = f.relative_to(base) if base.is_dir() else Path(f.name)
                name = "-".join(rel.with_suffix("").parts)
                if name in skills and skills[name][2] == plugin.id:
                    continue  # the plugin ships a skill with the same name
                add(name, ("generate", command_to_skill(name, f)), plugin.id)
    return {k: v[:2] for k, v in skills.items()}


def remove_entry(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def sync_skills(skills, previous):
    AGENTS_SKILLS.mkdir(parents=True, exist_ok=True)
    managed = []
    for name, (kind, value) in sorted(skills.items()):
        dest = AGENTS_SKILLS / name
        ours = name in previous
        if kind == "link":
            if dest.is_symlink() and Path(os.readlink(dest)) == value:
                emit("ok", f"skill {name} (already linked)")
                managed.append(name)
                continue
            if dest.exists() or dest.is_symlink():
                if ours:
                    remove_entry(dest)
                else:
                    emit("warn", f"skill {name} skipped: {dest} exists and is not managed by this sync")
                    continue
            dest.symlink_to(value)
            emit("link", f"{dest} -> {value}")
        else:
            skill_md = dest / "SKILL.md"
            if dest.exists() or dest.is_symlink():
                if not ours:
                    emit("warn", f"skill {name} skipped: {dest} exists and is not managed by this sync")
                    continue
                if (dest.is_dir() and not dest.is_symlink() and skill_md.is_file()
                        and skill_md.read_text() == value):
                    emit("ok", f"skill {name} (already generated)")
                    managed.append(name)
                    continue
                remove_entry(dest)
            dest.mkdir()
            skill_md.write_text(value)
            (dest / GENERATED_MARKER).write_text("generated from a Claude Code plugin command\n")
            emit("ok", f"skill {name} generated from command")
        managed.append(name)

    for name in sorted(set(previous) - set(managed)):
        dest = AGENTS_SKILLS / name
        if dest.exists() or dest.is_symlink():
            remove_entry(dest)
            emit("ok", f"skill {name} removed (gone from Claude Code)")
    return managed


def cleanup_legacy_skills(dotfiles):
    """Drop the old per-skill links into dotfiles from ~/.codex/skills."""
    if not LEGACY_CODEX_SKILLS.is_dir():
        return
    root = str(dotfiles / ".claude" / "skills")
    for entry in sorted(LEGACY_CODEX_SKILLS.iterdir()):
        if entry.is_symlink() and os.readlink(entry).startswith(root + os.sep):
            entry.unlink()
            emit("ok", f"removed legacy link {entry}")


# --- Hooks -----------------------------------------------------------------

def plugin_hooks(plugin):
    value = plugin.manifest.get("hooks")
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        return load_json(plugin.root / value, {}).get("hooks", {})
    return load_json(plugin.root / "hooks" / "hooks.json", {}).get("hooks", {})


def convert_handler(handler, origin, plugin_root):
    if handler.get("type", "command") != "command" or "command" not in handler:
        emit("warn", f"hook from {origin} skipped: type {handler.get('type')} is not supported by Codex")
        return None
    unknown = set(handler) - CODEX_HANDLER_KEYS - DROPPED_HANDLER_KEYS
    if unknown:
        emit("warn", f"hook from {origin}: dropped unsupported keys {sorted(unknown)}")
    out = {k: v for k, v in handler.items() if k in CODEX_HANDLER_KEYS}
    out["type"] = "command"
    command = out["command"]
    if plugin_root is not None:
        command = re.sub(r"\$\{CLAUDE_PLUGIN_ROOT\}|\$CLAUDE_PLUGIN_ROOT\b", str(plugin_root), command)
    if re.search(r"\$\{?CLAUDE_", command):
        emit("warn", f"hook from {origin} uses a Claude-only variable: {command}")
    out["command"] = command
    return out


def merge_hooks(target, hooks, origin, plugin_root=None):
    for event, groups in hooks.items():
        if event not in CODEX_HOOK_EVENTS:
            emit("warn", f"hook {event} from {origin} skipped: no such event in Codex")
            continue
        for group in groups:
            handlers = [h for h in (convert_handler(h, origin, plugin_root)
                                    for h in group.get("hooks", [])) if h]
            if not handlers:
                continue
            converted = {"hooks": handlers}
            if group.get("matcher"):
                converted["matcher"] = group["matcher"]
            target.setdefault(event, []).append(converted)


def write_owned(path, text, previous_digest, label):
    """Write a generated file, backing up a version this sync did not write."""
    if path.exists():
        current = path.read_text()
        if current == text:
            emit("ok", f"{label} {path} (up to date)")
            return digest(text)
        if digest(current) != previous_digest:
            backup(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    emit("ok", f"{label} {path} written")
    return digest(text)


def remove_owned(path, previous_digest, label):
    if path.exists() and previous_digest and digest(path.read_text()) == previous_digest:
        path.unlink()
        emit("ok", f"{label} {path} removed (nothing to sync)")


def sync_hooks(settings, plugins, previous_digest):
    hooks = {}
    merge_hooks(hooks, settings.get("hooks", {}), "settings.json")
    for plugin in plugins:
        merge_hooks(hooks, plugin_hooks(plugin), plugin.id, plugin.root)
    if not hooks:
        remove_owned(HOOKS_FILE, previous_digest, "hooks")
        return None
    text = json.dumps({"hooks": hooks}, indent=2, ensure_ascii=False) + "\n"
    new_digest = write_owned(HOOKS_FILE, text, previous_digest, "hooks")
    if new_digest != previous_digest:
        emit("warn", "Codex hooks changed: approve them once with /hooks inside Codex")
    return new_digest


# --- Rules -----------------------------------------------------------------

def bash_pattern(entry, allow_exact):
    m = re.fullmatch(r"Bash\((.*)\)", entry)
    if not m:
        return None, "not a Bash permission"
    spec = m.group(1).strip()
    if spec.endswith(":*"):
        spec = spec[:-2]
    elif spec.endswith(" *"):
        spec = spec[:-2]
    elif not allow_exact:
        return None, "exact match cannot be expressed as a Codex prefix rule"
    if not spec or any(c in spec for c in "*?"):
        return None, "wildcard inside the command cannot be expressed as a Codex prefix rule"
    try:
        return shlex.split(spec), None
    except ValueError as exc:
        return None, str(exc)


def sync_rules(settings, previous_digest):
    permissions = settings.get("permissions", {})
    lines = [
        "# Generated by dotfiles lib/codex_sync.py from ~/.claude/settings.json.",
        "# Do not edit: changes are overwritten by `sh setup.sh codex`.",
        "",
    ]
    count = 0
    allowed_prefixes = [p for p in (bash_pattern(e, False)[0] for e in permissions.get("allow", [])) if p]
    # deny/ask only get stricter when an exact match widens to a prefix.
    for key, decision, allow_exact in (("deny", "forbidden", True), ("ask", "prompt", True),
                                       ("allow", "allow", False)):
        for entry in permissions.get(key, []):
            pattern, reason = bash_pattern(entry, allow_exact)
            if pattern is None:
                exact, _ = bash_pattern(entry, True)
                covered = key == "allow" and exact and any(
                    exact[:len(p)] == p for p in allowed_prefixes)
                if entry.startswith("Bash(") and not covered:
                    emit("skip", f"permission {key} {entry}: {reason}")
                continue
            lines.append(f"prefix_rule(pattern = {json.dumps(pattern)}, decision = \"{decision}\", "
                         f"justification = {json.dumps('Claude Code: ' + entry)})")
            count += 1
    if count == 0:
        remove_owned(RULES_FILE, previous_digest, "rules")
        return None
    text = "\n".join(lines) + "\n"
    return write_owned(RULES_FILE, text, previous_digest, f"rules ({count})")


# --- Native plugins ----------------------------------------------------------

def codex(*args):
    return subprocess.run(["codex", *args], capture_output=True, text=True)


def sync_native_plugins(settings, previous):
    wanted = {NATIVE_PLUGINS[p] for p, on in settings.get("enabledPlugins", {}).items()
              if on and p in NATIVE_PLUGINS}
    result = codex("plugin", "list", "--json")
    if result.returncode != 0:
        emit("warn", f"codex plugin list failed: {result.stderr.strip()}")
        return sorted(set(previous) & wanted)
    installed = {p["pluginId"] for p in json.loads(result.stdout).get("installed", [])
                 if p.get("installed")}
    managed = []
    for plugin in sorted(wanted):
        if plugin in installed:
            emit("ok", f"plugin {plugin} (already installed)")
            managed.append(plugin)
            continue
        result = codex("plugin", "add", plugin)
        if result.returncode == 0:
            emit("ok", f"plugin {plugin} installed")
            managed.append(plugin)
        else:
            emit("warn", f"codex plugin add {plugin} failed: {(result.stderr or result.stdout).strip()}")
    for plugin in sorted(set(previous) - wanted):
        if plugin in installed:
            result = codex("plugin", "remove", plugin)
            level = "ok" if result.returncode == 0 else "warn"
            emit(level, f"plugin {plugin} removed (gone from Claude Code)"
                 if level == "ok" else f"codex plugin remove {plugin} failed")
    return managed


def main():
    dotfiles = Path(sys.argv[1]).resolve()
    settings = load_json(dotfiles / ".claude" / "settings.json", {})
    previous = load_json(MANIFEST, {})

    plugins = []
    for plugin in enabled_plugins(settings):
        if plugin.id in EXCLUDED_PLUGINS:
            emit("skip", f"plugin {plugin.id} (excluded: Claude Code only)")
        elif plugin.id in NATIVE_PLUGINS:
            emit("skip", f"plugin {plugin.id} (installed natively as {NATIVE_PLUGINS[plugin.id]})")
        else:
            plugins.append(plugin)

    cleanup_legacy_skills(dotfiles)
    manifest = {
        "skills": sync_skills(collect_skills(dotfiles, plugins), previous.get("skills", [])),
        "hooks": sync_hooks(settings, plugins, previous.get("hooks")),
        "rules": sync_rules(settings, previous.get("rules")),
        "plugins": sync_native_plugins(settings, previous.get("plugins", [])),
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
