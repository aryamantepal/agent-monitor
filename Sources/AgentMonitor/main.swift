import AgentMonitorCore
import AppKit
import SwiftUI

struct AgentMonitorApp: App {
    @State private var monitor = Monitor()

    init() {
        // No Dock icon when run outside the .app bundle (the bundle sets LSUIElement).
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(monitor: monitor)
        } label: {
            let cpu = monitor.snapshot.cpu
            Image(systemName: "cpu")
            Text(formatCPU(cpu)).monospacedDigit()
                .onAppear { monitor.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

let usage = """
    Usage: AgentMonitor [option]
      (no option)          run the menu-bar app
      --text               print a report once
      --json               print a JSON report once
      --json --watch       print one JSON line every 2 seconds (NDJSON)
      --snapshot out.png [--seconds n] [--dark]
                           render the menu to an image after sampling for n seconds
    """

/// One-shot reports sample twice, a second apart, because CPU % is a rate.
func report(_ sampler: DarwinSampler) -> Snapshot {
    Attribution.snapshot(sampler.sample(), cwd: sampler.workingDirectory, ports: sampler.listeningPorts)
}

let args = CommandLine.arguments
if args.contains("--help") || args.contains("-h") {
    print(usage)
} else if args.contains("--json") && args.contains("--watch") {
    let sampler = DarwinSampler()
    _ = sampler.sample()
    while true {
        Thread.sleep(forTimeInterval: 2)
        print(JSONReport.render(report(sampler), pretty: false))
        fflush(stdout)
    }
} else if args.contains("--json") || args.contains("--text") {
    let sampler = DarwinSampler()
    _ = sampler.sample()
    Thread.sleep(forTimeInterval: 1)
    let snap = report(sampler)
    print(args.contains("--json") ? JSONReport.render(snap, pretty: true) : TextReport.render(snap))
} else if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    let seconds = args.firstIndex(of: "--seconds").flatMap { Int(args[$0 + 1]) } ?? 10
    MainActor.assumeIsolated {
        let monitor = Monitor()
        Task { @MainActor in
            for _ in 0..<max(seconds, 2) {
                await monitor.tick()
                try? await Task.sleep(for: .seconds(1))
            }
            let view = MenuView(monitor: monitor, interactive: false, sparklineLength: max(seconds, 2))
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, args.contains("--dark") ? .dark : .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: args[i + 1]))
                print("wrote \(args[i + 1])")
            }
            exit(0)
        }
        RunLoop.main.run()
    }
} else {
    AgentMonitorApp.main()
}
