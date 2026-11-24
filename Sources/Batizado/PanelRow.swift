import SwiftUI

struct ToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: icon)
        }
        .toggleStyle(PillToggleStyle())
    }
}

struct PillToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
                .labelStyle(RowLabelStyle())
            Spacer(minLength: 12)
            Capsule()
                .fill(configuration.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                .frame(width: 38, height: 22)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                        .padding(2)
                }
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

private struct RowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
                .frame(width: 20)
                .foregroundStyle(.secondary)
            configuration.title
        }
    }
}
