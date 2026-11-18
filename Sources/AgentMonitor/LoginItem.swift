import ServiceManagement
import SwiftUI

/// "Open at login" via SMAppService. Only shown when running from the .app bundle, since a bare
/// `swift run` binary can't be registered as a login item.
struct LoginItemToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var error: String?

    var body: some View {
        if Bundle.main.bundleIdentifier != nil {
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Open at login", isOn: Binding(get: { status == .enabled }, set: set))
                    .toggleStyle(.checkbox)
                if status == .requiresApproval {
                    Button("Allow in System Settings…") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.link).font(.caption)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .onAppear { status = SMAppService.mainApp.status }
        }
    }

    private func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }
}
