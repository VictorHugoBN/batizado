import BatizadoCore
import SwiftUI

@main
struct BatizadoApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra(AppInfo.name, systemImage: "cup.and.saucer") {
            MenuPanel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuPanel: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppInfo.name)
                .font(.headline)
            ToggleRow(
                icon: "cup.and.saucer.fill",
                title: "Keep awake",
                isOn: Binding(
                    get: { model.state.keepAwake },
                    set: { model.send(.setKeepAwake($0)) }
                )
            )
            ToggleRow(
                icon: "display",
                title: "Keep display on",
                isOn: Binding(
                    get: { model.state.keepDisplayOn },
                    set: { model.send(.setKeepDisplayOn($0)) }
                )
            )
            .disabled(!model.state.keepAwake)
            Divider()
            Button("Quit") {
                model.send(.quit)
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}
