import BatizadoCore
import SwiftUI

@main
struct BatizadoApp: App {
    var body: some Scene {
        MenuBarExtra(AppInfo.name, systemImage: "cup.and.saucer") {
            MenuPanel()
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppInfo.name)
                .font(.headline)
            Text("Nothing to toggle yet.")
                .foregroundStyle(.secondary)
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}
