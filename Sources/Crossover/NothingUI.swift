import AppKit
import CoreText
import SwiftUI

enum ZoneColorRole: String, CaseIterable {
    case connected = "CONNECTED"
    case standby = "STANDBY"
    case disconnected = "DISCONNECTED"
}

enum FontRegistrar {
    static func register() {
        let folders = [Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
                       Bundle.module.resourceURL?.appendingPathComponent("Resources/Fonts")].compactMap { $0 }
        for folder in folders {
            guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for url in urls where url.pathExtension == "ttf" {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

@MainActor
func renderPreviews(to directory: String) throws {
    let folder = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let monitor = ConnectionMonitor(previewOnly: true)
    for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
        let renderer = ImageRenderer(content: NothingPopover(monitor: monitor, previewScheme: scheme, previewMode: true).preview)
        renderer.proposedSize = ProposedViewSize(width: 320, height: nil)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Crossover.Preview", code: 1)
        }
        try data.write(to: folder.appendingPathComponent("nothing-\(name).png"))
    }
}

@MainActor
func renderTrayIconSheet(to path: String) throws {
    let renderer = ImageRenderer(content: TrayIconSheet())
    renderer.proposedSize = ProposedViewSize(width: 700, height: 112)
    renderer.scale = 2
    guard let image = renderer.cgImage,
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Crossover.Preview", code: 2)
    }
    try data.write(to: URL(fileURLWithPath: path))
}

private struct TrayIconSheet: View {
    private let labels = ["CONNECTED", "STANDBY", "DISCONNECTED", "OFF", "UNKNOWN"]

    var body: some View {
        HStack(spacing: 24) {
            ForEach(Array(TrayState.allCases.enumerated()), id: \.offset) { index, state in
                let spec = trayIconSpec(for: state)
                VStack(spacing: 8) {
                    Image(systemName: spec.symbol)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white)
                        .opacity(spec.opacity)
                        .overlay(alignment: .topTrailing) {
                            if spec.showsRedDot {
                                Circle().fill(Color(red: 0.843, green: 0.098, blue: 0.129)).frame(width: 8, height: 8)
                            }
                        }
                    Text(labels[index])
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(white: 0.72))
                }
                .frame(width: 112)
            }
        }
        .frame(width: 700, height: 112)
        .background(Color(white: 0.08))
    }
}

struct NothingPopover: View {
    @ObservedObject var monitor: ConnectionMonitor
    @Environment(\.colorScheme) private var scheme
    var previewScheme: ColorScheme? = nil
    var previewMode = false

    private var effectiveScheme: ColorScheme { previewScheme ?? scheme }
    private var background: Color { effectiveScheme == .dark ? .black : Color(red: 0.961, green: 0.953, blue: 0.937) }
    private var surface: Color { effectiveScheme == .dark ? Color(white: 0.067) : .white }
    private var border: Color { effectiveScheme == .dark ? Color(white: 0.2) : Color(white: 0.8) }
    private var primary: Color { effectiveScheme == .dark ? Color(white: 0.91) : Color(white: 0.1) }
    private var secondary: Color { effectiveScheme == .dark ? Color(white: 0.6) : Color(white: 0.4) }

    private var hero: String {
        switch monitor.trayState {
        case .connected: "CONNECTED"
        case .standby: "STANDBY"
        case .disconnected: "DISCONNECTED"
        case .off: "OFF"
        case .unknown: "UNKNOWN"
        }
    }

    private var heroColor: Color {
        switch monitor.trayState {
        case .connected: Color(red: 0.29, green: 0.62, blue: 0.36)
        case .disconnected: Color(red: 0.843, green: 0.098, blue: 0.129)
        default: primary
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("CROSSOVER").nothingLabel(secondary)
                Text(hero)
                    .font(.custom("Doto", size: 38).weight(.bold))
                    .foregroundStyle(heroColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                ForEach(Array(monitor.positionLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.custom("Space Grotesk", size: 14))
                        .foregroundStyle(primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text("LAST CHANGE  \(formattedLastChange(monitor.changedAt))")
                    .nothingLabel(secondary)
            }

            VStack(spacing: 12) {
                Button { monitor.reconnectNow() } label: {
                    HStack {
                        Text("RECONNECT").nothingLabel(primary).lineLimit(1).layoutPriority(1)
                        Spacer()
                        Text(monitor.reconnectStatus ?? "[READY]").nothingLabel(secondary)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .overlay(Capsule().stroke(border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                NothingToggle(label: "AUTO-RECONNECT", isOn: $monitor.autoReconnectEnabled,
                              primary: primary, secondary: secondary, border: border)
                NothingToggle(label: "SHOW CROSSING ZONE", isOn: $monitor.showCrossingZone,
                              primary: primary, secondary: secondary, border: border)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("CROSSING ZONE COLORS").nothingLabel(secondary)
                ForEach(ZoneColorRole.allCases, id: \.self) { role in
                    HStack(spacing: 8) {
                        Text(role.rawValue).nothingLabel(primary).lineLimit(1)
                            .frame(width: 112, alignment: .leading)
                        Spacer(minLength: 0)
                        if previewMode {
                            RoundedRectangle(cornerRadius: 4).fill(colorBinding(role).wrappedValue)
                                .frame(width: 28, height: 20)
                        } else {
                            ColorPicker("", selection: colorBinding(role), supportsOpacity: true)
                                .labelsHidden()
                                .frame(width: 28, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .frame(height: 28)
                }
                HStack {
                    Spacer()
                    Button("[ RESET DEFAULTS ]") { monitor.resetZoneColors() }
                        .buttonStyle(.plain)
                        .nothingLabel(secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .background { surface.padding(.horizontal, -14) }
            .overlay { Rectangle().stroke(border, lineWidth: 1).padding(.horizontal, -14) }

            HStack {
                Text("SYSTEM APPEARANCE").nothingLabel(secondary).lineLimit(1).layoutPriority(1)
                Spacer()
                Button("[ QUIT ]") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .nothingLabel(primary)
            }
        }
        .padding(20)
    }

    var preview: some View { content.frame(width: 320).background(background).focusEffectDisabled() }

    var body: some View {
        content
        .frame(width: 320)
        .background(background)
        .focusEffectDisabled()
    }

    private func colorBinding(_ role: ZoneColorRole) -> Binding<Color> {
        Binding {
            switch role {
            case .connected: Color(monitor.zoneColors.connected.nsColor)
            case .standby: Color(monitor.zoneColors.standby.nsColor)
            case .disconnected: Color(monitor.zoneColors.disconnected.nsColor)
            }
        } set: { monitor.setZoneColor(role, color: NSColor($0)) }
    }
}

private struct NothingToggle: View {
    let label: String
    @Binding var isOn: Bool
    let primary: Color
    let secondary: Color
    let border: Color

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack {
                Text(label).nothingLabel(isOn ? primary : secondary).lineLimit(1).layoutPriority(1)
                Spacer()
                Text(isOn ? "[ ON ]" : "[ OFF ]").nothingLabel(isOn ? primary : secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 56)
                    .padding(.vertical, 5)
                    .overlay(Rectangle().stroke(border, lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private extension View {
    func nothingLabel(_ color: Color) -> some View {
        font(.custom("Space Mono", size: 11).weight(.medium))
            .foregroundStyle(color)
            .tracking(0.5)
    }
}
