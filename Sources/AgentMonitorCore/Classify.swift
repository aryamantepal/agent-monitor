import Foundation

/// Returns the agent when this process is one of an agent's own processes, else nil.
public func classify(_ command: String) -> Agent? {
    let exe = command.components(separatedBy: " --").first ?? command
    let base = basename(exe.split(separator: " ", maxSplits: 1).first.map(String.init) ?? exe)
    if base == "claude" || exe.contains("/claude/versions/") { return Agent("Claude Code", .cli) }
    if exe.contains("/Claude.app/") { return Agent("Claude Desktop", .app) }
    if exe.contains("/.codex/") || base == "codex" || base == "codex-code-mode-host" {
        return Agent("Codex", .app)
    }
    if base == "cursor-agent" { return Agent("Cursor", .cli) }
    if exe.contains("/Cursor.app/") || exe.hasPrefix("Cursor Helper") { return Agent("Cursor", .app) }
    if exe.contains("/Antigravity") { return Agent("Antigravity", .app) }
    return nil
}

func basename(_ path: String) -> String {
    let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
    return trimmed.split(separator: "/").last.map(String.init) ?? trimmed
}

public func shortPath(_ path: String?, home: String = NSHomeDirectory()) -> String {
    guard let path, !path.isEmpty, path != "/" else { return "" }
    if let range = path.range(of: "/.claude/worktrees/") {
        return "\(basename(String(path[..<range.lowerBound]))) (worktree)"
    }
    if path == home { return "~" }
    let base = basename(path)
    return base.isEmpty ? path : base
}

/// "node /a/b/vitest.mjs run --watch" -> "node vitest.mjs run"
public func shortCommand(_ command: String, limit: Int = 48) -> String {
    // App executables have spaces in their paths ("…/Vibe Helper (Renderer).app/Contents/MacOS/…"),
    // so word-splitting them gives garbage; use the executable name instead.
    if let r = command.range(of: ".app/Contents/MacOS/") {
        let name = command[r.upperBound...].components(separatedBy: " -").first ?? ""
        return name.count <= limit ? name : String(name.prefix(limit - 1)) + "…"
    }
    let words = command.split(separator: " ").map(String.init)
    guard let first = words.first else { return command }
    let args = words.dropFirst().filter { !$0.hasPrefix("-") }.prefix(3)
        .map { $0.hasPrefix("/") ? basename($0) : $0 }
    let text = ([basename(first)] + args).joined(separator: " ")
    return text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
}
