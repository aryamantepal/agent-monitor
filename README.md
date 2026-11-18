# agent-monitor

Activity Monitor for AI coding agents. A macOS menu-bar app that shows which agent (Claude Code, Codex, Cursor, Antigravity) is using your CPU, memory and energy, and what each one is running right now. Throttle, pause or kill a runaway session from the menu.

## Install

Download `AgentMonitor.zip` from [Releases](https://github.com/aryamantepal/agent-monitor/releases), unzip it, and move `AgentMonitor.app` to Applications. It's ad-hoc signed, not notarized, so the first time either right-click it and choose **Open**, or run:

```sh
xattr -d com.apple.quarantine /Applications/AgentMonitor.app
```

Requires macOS 14 or later on Apple Silicon.

Or build it yourself (only needs the Command Line Tools):

```sh
scripts/bundle.sh        # → dist/AgentMonitor.app
```

## What it shows

Every process is attributed to its nearest ancestor that is an agent. Each Claude Code or `cursor-agent` CLI is its own session, labeled by its working directory, and desktop apps fold into one session together with their helpers. Each session shows:

- CPU, with a sparkline of the last three minutes. 100% is one full core, so a session running parallel builds or tests can show 300% or more.
- Memory, as physical footprint (what Activity Monitor shows), not RSS.
- The busiest commands running under it, each with a kill button.
- Power, from the kernel's per-process energy counter. This is an estimate: the chip only measures power per cluster, and the kernel divides it among processes.

Busy processes that belong to no agent are listed under "Not an agent". This only covers your own processes, because reading root processes' CPU needs root.

## Controls

The `⋯` menu on each session acts on its whole process tree:

- **Throttle** puts every process in the session under macOS's background policy (`PRIO_DARWIN_BG`, the same as `taskpolicy -b`): lowest CPU priority, efficiency cores, throttled disk and network I/O. The agent keeps working, only slower, and nothing times out. Existing children don't inherit the policy, so it is re-applied on every poll to catch new ones.
- **Pause** sends `SIGSTOP` top-down: the parent first, so it can't spawn children that get missed, re-reading the tree until nothing new appears. Resume continues them bottom-up. While paused, the agent's connection to its model API can time out, so prefer throttle unless you need the CPU back immediately.
- **Kill** sends `SIGTERM` to the whole tree (plus `SIGCONT`, so paused processes can handle it), then `SIGKILL` to anything still alive after 3 seconds.

## Terminal view

```sh
dist/AgentMonitor.app/Contents/MacOS/AgentMonitor --text
```

The original v0, a SwiftBar plugin in Python, is kept in [`swiftbar/`](swiftbar/).

## Development

```sh
scripts/test.sh          # unit tests, plus a pause/throttle/kill test on a real process tree
swift run AgentMonitor   # run from source
```

`Sources/AgentMonitorCore` holds the sampler (libproc and sysctl), attribution and process control, and has no UI dependencies. `Sources/AgentMonitor` holds the SwiftUI menu-bar app.
