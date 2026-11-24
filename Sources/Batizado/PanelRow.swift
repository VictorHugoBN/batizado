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
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                // The edge is a filled ring rather than a stroke, which drew stray marks at the capsule's ends.
                Capsule()
                    .fill(
                        configuration.isOn ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.trackEdge))
                Capsule()
                    .fill(Palette.track)
                    .padding(1)
                    .opacity(configuration.isOn ? 0 : 1)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .padding(2)
                    .frame(width: 20, height: 20)
            }
            .frame(width: 34, height: 20)
            .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        }
        .frame(minHeight: 24)
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

/// A row that does something once when clicked, laid out like the switch rows.
struct ActionRow: View {
    let icon: String
    let title: String
    var opensLink = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Label(title, systemImage: icon)
                    .labelStyle(RowLabelStyle())
                Spacer(minLength: 12)
                if opensLink {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 24)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 5).fill(hovering && isEnabled ? Palette.highlight : Tone.clear)
            )
            .padding(.horizontal, -6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
    }
}

struct RowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
                .frame(width: 20)
                .foregroundStyle(Palette.icon)
            configuration.title
        }
    }
}

/// A short message under the rows; `isWarning` marks one that needs the user to act.
struct PanelNote: View {
    let text: String
    var isWarning = true

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(isWarning ? AnyShapeStyle(Palette.warning) : AnyShapeStyle(.primary))
        } icon: {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(isWarning ? AnyShapeStyle(Palette.warning) : AnyShapeStyle(Palette.icon))
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension Tone {
    static let clear = Tone(light: 0, dark: 0, opacity: 0)
}
