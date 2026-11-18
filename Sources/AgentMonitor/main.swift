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

/// `--text`: print once to the terminal. `--snapshot out.png [--seconds n]`: render the menu to
/// an image after sampling for n seconds (used for the README screenshot).
let args = CommandLine.arguments
if args.contains("--text") {
    let sampler = DarwinSampler()
    _ = sampler.sample()
    Thread.sleep(forTimeInterval: 1)
    print(TextReport.render(Attribution.snapshot(sampler.sample(), cwd: sampler.workingDirectory)))
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
