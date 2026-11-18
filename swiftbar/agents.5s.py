#!/usr/bin/env python3
"""Menu-bar widget (SwiftBar/xbar plugin): which coding agent is using CPU and memory, and on what.

Every process is attributed to the nearest ancestor that is an agent (Claude, Codex, Cursor,
Antigravity). Each agent session shows its total CPU/memory and the busiest work running under it.
Run with --text for a plain terminal view.
"""

import os
import subprocess
import sys
from collections import defaultdict

HOME = os.path.expanduser("~")
BUSY_CPU = 5.0  # a child process counts as "doing something" above this CPU %
OTHER_CPU = 30.0  # unattributed processes are listed above this CPU %
TOP_TASKS = 4


def classify(cmd):
    """Return (agent, kind) when this process is an agent's own process, else None."""
    exe = cmd.split(" --", 1)[0]
    base = os.path.basename(exe.split(" ")[0])
    if base == "claude" or "/claude/versions/" in exe:
        return "Claude Code", "cli"
    if "/Claude.app/" in exe:
        return "Claude Desktop", "app"
    if "/.codex/" in exe or base in ("codex", "codex-code-mode-host"):
        return "Codex", "app"
    if base == "cursor-agent":
        return "Cursor", "cli"
    if "/Cursor.app/" in exe or exe.startswith("Cursor Helper"):
        return "Cursor", "app"
    if "/Antigravity" in exe:
        return "Antigravity", "app"
    return None


def read_procs():
    out = subprocess.run(
        ["ps", "-Ao", "pid=,ppid=,pcpu=,rss=,etime=,command="],
        capture_output=True,
        text=True,
    ).stdout
    procs = {}
    for line in out.splitlines():
        parts = line.split(None, 5)
        if len(parts) < 6:
            continue
        pid, ppid, cpu, rss, etime, cmd = parts
        procs[int(pid)] = {
            "pid": int(pid),
            "ppid": int(ppid),
            "cpu": float(cpu),
            "rss": int(rss) * 1024,
            "etime": etime,
            "cmd": cmd,
        }
    return procs


def read_cwds(pids):
    if not pids:
        return {}
    out = subprocess.run(
        ["lsof", "-a", "-d", "cwd", "-Fn", "-p", ",".join(map(str, pids))],
        capture_output=True,
        text=True,
    ).stdout
    cwds, pid = {}, None
    for line in out.splitlines():
        if line.startswith("p"):
            pid = int(line[1:])
        elif line.startswith("n") and pid is not None:
            cwds[pid] = line[1:]
    return cwds


def short_path(path):
    if not path:
        return ""
    if "/.claude/worktrees/" in path:
        project = path.split("/.claude/worktrees/")[0]
        return f"{os.path.basename(project)} (worktree)"
    if path == HOME:
        return "~"
    return os.path.basename(path.rstrip("/")) or path


def short_cmd(cmd, limit=48):
    words = cmd.split()
    exe = os.path.basename(words[0]) if words else cmd
    args = [w for w in words[1:] if not w.startswith("-")][:3]
    args = [os.path.basename(a) if a.startswith("/") else a for a in args]
    text = " ".join([exe, *args])
    return text if len(text) <= limit else text[: limit - 1] + "…"


def fmt_mem(n):
    return f"{n / 2**30:.1f}G" if n >= 2**30 else f"{n / 2**20:.0f}M"


def build():
    procs = read_procs()
    children = defaultdict(list)
    for p in procs.values():
        children[p["ppid"]].append(p["pid"])
    for p in procs.values():
        p["agent"] = classify(p["cmd"])

    def agent_parent(pid):
        """Nearest strict ancestor that is an agent process."""
        seen = set()
        pid = procs[pid]["ppid"]
        while pid in procs and pid not in seen and pid > 1:
            seen.add(pid)
            if procs[pid]["agent"]:
                return pid
            pid = procs[pid]["ppid"]
        return None

    # A session root is an agent process whose nearest agent ancestor is not the same agent.
    # Apps (Cursor, Codex…) collapse to one session; each Claude Code / cursor-agent CLI is its own.
    roots = {}
    for pid, p in procs.items():
        if not p["agent"]:
            continue
        up = agent_parent(pid)
        name, kind = p["agent"]
        if up and procs[up]["agent"][0] == name and kind == "app":
            continue
        if up and procs[up]["agent"] == p["agent"] and kind == "cli":
            continue
        roots[pid] = p

    def session_of(pid):
        seen = set()
        while pid in procs and pid not in seen and pid > 1:
            if pid in roots:
                return pid
            seen.add(pid)
            pid = procs[pid]["ppid"]
        return None

    sessions = {r: {"root": procs[r], "procs": []} for r in roots}
    other = []
    for pid, p in procs.items():
        s = session_of(pid)
        if s:
            sessions[s]["procs"].append(p)
        elif p["cpu"] >= OTHER_CPU:
            other.append(p)

    busy = [
        p
        for s in sessions.values()
        for p in s["procs"]
        if not p["agent"] and p["cpu"] >= BUSY_CPU
    ]
    cwd_pids = [r for r, p in roots.items() if p["agent"][1] == "cli"]
    cwd_pids += [p["pid"] for p in busy + other]
    cwds = read_cwds(cwd_pids)

    # Desktop apps leave orphaned helpers (crashpad, updaters); fold each app into one session.
    merged = {}
    for r, s in sessions.items():
        name, kind = s["root"]["agent"]
        if kind == "app" and name in merged:
            merged[name]["procs"] += s["procs"]
            continue
        merged[name if kind == "app" else r] = s
    sessions = {s["root"]["pid"]: s for s in merged.values()}

    groups = defaultdict(list)
    for r, s in sessions.items():
        ps_ = s["procs"]
        name, kind = s["root"]["agent"]
        label = short_path(cwds.get(r)) if kind == "cli" else ""
        tasks = sorted(
            (p for p in ps_ if not p["agent"] and p["cpu"] >= BUSY_CPU),
            key=lambda p: -p["cpu"],
        )[:TOP_TASKS]
        groups[name].append(
            {
                "label": label,
                "cpu": sum(p["cpu"] for p in ps_),
                "rss": sum(p["rss"] for p in ps_),
                "n": len(ps_),
                "up": s["root"]["etime"],
                "tasks": [
                    (p, short_cmd(p["cmd"]), short_path(cwds.get(p["pid"])))
                    for p in tasks
                ],
            }
        )
    for g in groups.values():
        g.sort(key=lambda s: -s["cpu"])
    ordered = sorted(groups.items(), key=lambda kv: -sum(s["cpu"] for s in kv[1]))
    other.sort(key=lambda p: -p["cpu"])
    return ordered, [(p, short_cmd(p["cmd"]), short_path(cwds.get(p["pid"]))) for p in other]


def status(s):
    if s["tasks"]:
        p, cmd, where = s["tasks"][0]
        return f"running {cmd}" + (f" in {where}" if where else "")
    return "working" if s["cpu"] >= BUSY_CPU else "idle"


def render_swiftbar(groups, other):
    total = sum(s["cpu"] for _, ss in groups for s in ss)
    hot = total >= 100 or any(p["cpu"] >= 90 for p, _, _ in other)
    print(f"⚙︎ {total:.0f}%" + (" | color=#d9480f" if hot else ""))
    print("---")
    mono = "font=Menlo size=12"
    small = "font=Menlo size=11"
    for name, ss in groups:
        cpu = sum(s["cpu"] for s in ss)
        rss = sum(s["rss"] for s in ss)
        print(f"{name}  {cpu:.0f}% · {fmt_mem(rss)} | {mono}")
        for s in ss:
            label = s["label"] or name
            line = f"{label}: {status(s)}"
            print(f"  {line} | {small} color=#868e96")
            print(f"--{label} · {s['cpu']:.0f}% · {fmt_mem(s['rss'])} · {s['n']} procs · up {s['up']} | {mono}")
            for p, cmd, where in s["tasks"]:
                print(f"--{p['cpu']:5.0f}%  {fmt_mem(p['rss']):>5}  {cmd}  [{where}] | {small}")
                print(f"----Kill {p['pid']} | bash=/bin/kill param1={p['pid']} terminal=false refresh=true")
    if other:
        print("---")
        print(f"Not an agent | {mono} color=#868e96")
        for p, cmd, where in other:
            print(f"  {p['cpu']:.0f}%  {cmd}  [{where or p['pid']}] | {small}")
    print("---")
    print("Refresh | refresh=true")


def render_text(groups, other):
    for name, ss in groups:
        cpu = sum(s["cpu"] for s in ss)
        print(f"{name}  {cpu:.0f}% CPU  {fmt_mem(sum(s['rss'] for s in ss))}")
        for s in ss:
            print(f"  {s['label'] or name}: {status(s)}  ({s['cpu']:.0f}%, {fmt_mem(s['rss'])}, {s['n']} procs)")
            for p, cmd, where in s["tasks"]:
                print(f"    {p['pid']:>6} {p['cpu']:5.0f}% {fmt_mem(p['rss']):>5}  {cmd}  [{where}]")
    if other:
        print("Not an agent")
        for p, cmd, where in other:
            print(f"  {p['pid']:>6} {p['cpu']:5.0f}%  {cmd}  [{where}]")


if __name__ == "__main__":
    groups, other = build()
    (render_text if "--text" in sys.argv else render_swiftbar)(groups, other)
