# agent-monitor

Activity Monitor for AI coding agents. A macOS menu-bar app that shows which agent (Claude Code, Codex, Cursor, Antigravity) is using your CPU, memory and energy, and what each one is running right now. Throttle, pause or kill a runaway session from the menu.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/aryamantepal/agent-monitor/main/install.sh | sh
```

This installs the latest release into `/Applications` and starts it. Run it again to update. To keep it running across restarts, tick **Open at login** at the bottom of its menu. Requires macOS 14 or later, on Apple Silicon or Intel.

<details>
<summary>Installing by hand</summary>

Download `AgentMonitor.zip` from [Releases](https://github.com/aryamantepal/agent-monitor/releases), unzip it, and move `AgentMonitor.app` to Applications. The app isn't notarized, so macOS blocks it the first time you open it. To allow it, open **System Settings → Privacy & Security** and click **Open Anyway**, or run:

```sh
xattr -d com.apple.quarantine /Applications/AgentMonitor.app
```

The install script avoids this step: files fetched with `curl` aren't quarantined the way browser downloads are.
</details>

To uninstall, quit it from its menu and delete `/Applications/AgentMonitor.app`.

Or build it yourself (the Command Line Tools are enough):

```sh
scripts/bundle.sh        # → dist/AgentMonitor.app
```

## What it does

**In the menu bar:** a CPU icon and the total CPU all your agents are using, such as `212%`. 100% means one full core, so an agent running parallel builds or tests can go well past 100%.

**When you click it**, agents are grouped by tool (Claude Code, Codex, Cursor, Antigravity, Claude Desktop), with CPU, memory and power totals for each. Every session gets a card:

- Each Claude Code or `cursor-agent` terminal is its own session, labeled by its project folder (worktrees are marked). A desktop app like Cursor is one card for the app and all its helpers.
- A sparkline of the last three minutes of CPU, plus current CPU and memory.
- A status line: `idle`, `working`, or what it's running, such as `running cargo build in forge`.
- Badges for any ports its processes are listening on, such as `:3000`, so you can tell which worktree's dev server is which.
- Up to four of the busiest commands under it, each with a kill button.

**Orphaned from closed agents** lists processes that outlived the session that started them, such as a `next dev` server, a headless browser or an MCP server left running after you closed Claude Code. Each row shows which session it came from. Kill them one by one or use **Clean up all**. Nothing is ever killed automatically, because sometimes you want that dev server to stay up.

Below that, **Not an agent** lists any of your other processes using more than 30% CPU, such as Chrome helpers.

## Controls

The `⋯` button on each card acts on the session's whole process tree:

- **Throttle** (the safe default): moves everything the agent spawned (builds, tests, dev servers) to macOS's background priority, the same policy as `taskpolicy -b`. Those processes run on efficiency cores with throttled disk and network I/O. The agent's own process stays at normal priority, so its UI and model connection stay responsive while the heavy work slows down. Existing child processes don't inherit the policy, so it is re-applied on every poll to catch new ones.
- **Pause**: freezes every process with `SIGSTOP`, parent first so it can't spawn children that get missed, re-reading the tree until nothing new appears. Resume continues them in reverse order. It frees the CPU immediately, but while paused the agent's connection to its model can time out.
- **Kill session**: sends `SIGTERM` to every process (plus `SIGCONT`, so paused ones can handle it), then `SIGKILL` to anything still running after 3 seconds.

## How it works

Every 2 seconds it reads the process list straight from the kernel, which costs about 0.8% of one core. Each process is assigned to the nearest agent above it in the process tree. That's how it knows a `node vitest` process belongs to your Claude session in `web`.

- CPU is measured over each 2-second interval, not taken from `ps`, whose figure is averaged over roughly the last minute.
- Memory is the physical footprint, the number Activity Monitor shows, not RSS.

## Limits

- Power is the kernel's estimate, not a measurement. The chip only measures power per group of cores, and the kernel divides that among processes.
- It can't see CPU use by system processes that run as root.
- It keeps no history and doesn't track cost.

## Terminal view

```sh
/Applications/AgentMonitor.app/Contents/MacOS/AgentMonitor --text
```

The original v0, a SwiftBar plugin in Python, is kept in [`swiftbar/`](swiftbar/).

## Development

```sh
scripts/test.sh          # unit tests, plus a pause/throttle/kill test on a real process tree
swift run AgentMonitor   # run from source
```

`Sources/AgentMonitorCore` holds the sampler (libproc and sysctl), attribution and process control, and has no UI dependencies. `Sources/AgentMonitor` holds the SwiftUI menu-bar app.

To release, push a tag such as `v0.2.0`. GitHub Actions runs the tests, builds a universal app and publishes it, and `install.sh` then picks it up.
