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

To release, push a tag such as `v0.2.0`. GitHub Actions runs the tests, builds a universal app and publishes it, and `install.sh` then picks it up.
