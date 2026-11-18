# agent-monitor

Activity Monitor for AI coding agents. A macOS menu-bar app that shows which agent (Claude Code, Codex, Cursor, Antigravity) is using your CPU and memory, and what each one is running right now.

```
⚙︎ 212%
─────────────────────────────
Claude Code  180% · 2.1G
  agent-monitor: running node vitest in web
  forge (worktree): idle
Cursor  32% · 1.4G
  Cursor: working
```

## How it works

Every process is attributed to its nearest ancestor that is an agent. Each Claude Code or `cursor-agent` CLI is its own session, labeled by its working directory, and desktop apps fold into one session. Each session shows its total CPU and memory plus the busiest commands running under it, and you can kill any of them from the menu.

CPU follows Activity Monitor's convention: 100% is one full core, so a session running parallel work can show 300% or more.

## Install (v0, SwiftBar plugin)

1. Install [SwiftBar](https://github.com/swiftbar/SwiftBar): `brew install swiftbar`
2. Copy or symlink `agents.5s.py` into your SwiftBar plugins folder. The `5s` in the name is the refresh interval.

For a plain terminal view:

```sh
./agents.5s.py --text
```

## Roadmap

- Native SwiftUI menu-bar app with live sparklines
- Throttle (`taskpolicy` background policy) and pause for a whole session's process tree
- Estimated energy impact per session
